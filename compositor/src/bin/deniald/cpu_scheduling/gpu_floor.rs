//! An interaction floor for a GPU whose kernel driver scales it by load.
//!
//! A devfreq governor such as simple_ondemand averages GPU utilization over a
//! polling window, typically 50 ms. Denial's frames are serialized: the GPU
//! waits while the CPU prepares each frame, and its work must finish before
//! the next vblank. A frame that misses its vblank halves the frame rate and
//! so lowers the measured load. The governor then sees headroom exactly when
//! frames are late, and an animation can run at the device's lowest useful
//! frequency from its first frame to its last.
//!
//! The semantic hint worker knows when the user interacts before any frame
//! work starts. For the same hold time as the CPU floors, the GPU's minimum
//! frequency becomes its highest operating point, and returns to its lowest
//! afterwards. Thermal limits still apply: devfreq never raises the minimum
//! above the current maximum.
//!
//! Only a GPU devfreq device whose `min_freq` Denial may write is used. The
//! system grants that permission with a udev rule (the phone image does for
//! every Adreno), so a GPU without devfreq, or one whose system does not opt
//! in, is unchanged. The grant hands that minimum to the session: Denial sets
//! it to the lowest operating point when it starts, which is the floor devfreq
//! applies when nobody asks for one, and returns it there after every
//! interaction.
//!
//! Denial never reads back which minimum to return to. Reading `min_freq`
//! gives the highest of all minimum-frequency requests on the device, clamped
//! to the current maximum (`devfreq_get_freq_range`), not the value written
//! to it. On msm one of those requests is the driver's own boost: twice the
//! current frequency for one 50 ms polling period, whenever a fence is still
//! pending 3 ms before its deadline or the GPU turns active after more than
//! 50 ms idle (`msm_devfreq_boost`). Denial sets a deadline on every frame's
//! fence, so while frames run that boost comes and goes all the time. A
//! minimum read back at the start of a touch and written back at its end kept
//! such a boost for good, and the GPU no longer went below the operating point
//! above it. A value read when Denial starts is no better: a minimum an
//! earlier Denial left behind stays in the device until the device is removed.
//!
//! DENIAL_GPU_HINTS=0 disables the floor.
use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::unix::fs::FileExt;
use std::path::{Path, PathBuf};

const DEVFREQ: &str = "/sys/class/devfreq";
/// Kernel drivers whose devfreq device is a GPU. The msm driver binds its
/// Adreno GPU as a separate platform device named "adreno".
const GPU_DRIVERS: &[&str] = &["adreno"];

/// A devfreq device's `min_freq` attribute. A write replaces the minimum this
/// attribute requests; a read returns the device's effective minimum, which
/// other requests can raise and the current maximum can lower.
pub(super) trait MinFreq {
    fn read_hz(&self) -> io::Result<u64>;
    fn write_hz(&self, hz: u64) -> io::Result<()>;
}

impl MinFreq for File {
    fn read_hz(&self) -> io::Result<u64> {
        let mut buffer = [0u8; 32];
        let length = self.read_at(&mut buffer, 0)?;
        std::str::from_utf8(&buffer[..length])
            .ok()
            .and_then(|value| value.trim().parse().ok())
            .ok_or_else(|| io::ErrorKind::InvalidData.into())
    }

    fn write_hz(&self, hz: u64) -> io::Result<()> {
        let value = hz.to_string();
        let written = self.write_at(value.as_bytes(), 0)?;
        if written == value.len() {
            Ok(())
        } else {
            Err(io::ErrorKind::WriteZero.into())
        }
    }
}

pub(super) struct GpuFloor<M: MinFreq = File> {
    device: PathBuf,
    min_freq: M,
    /// The highest operating point, the minimum during an interaction.
    boost: u64,
    /// The lowest operating point, the minimum otherwise.
    resting: u64,
    raised: bool,
}

impl GpuFloor {
    /// Finds the first GPU devfreq device Denial may raise. Returns `None`
    /// without a log line when the system has no such GPU at all.
    pub(super) fn discover() -> Option<Self> {
        Self::discover_in(Path::new(DEVFREQ))
    }

    fn discover_in(devfreq: &Path) -> Option<Self> {
        let mut entries = fs::read_dir(devfreq)
            .ok()?
            .flatten()
            .map(|entry| entry.path())
            .collect::<Vec<_>>();
        entries.sort();
        for device in entries {
            let driver = fs::read_link(device.join("device/driver")).ok();
            let Some(driver) = driver.as_deref().and_then(Path::file_name) else {
                continue;
            };
            if !GPU_DRIVERS.iter().any(|known| driver == *known) {
                continue;
            }
            let path = device.join("min_freq");
            let min_freq = match OpenOptions::new().read(true).write(true).open(&path) {
                Ok(file) => file,
                Err(error) => {
                    tracing::info!(
                        %error,
                        device = %device.display(),
                        "GPU interaction floor unavailable: the platform does not let Denial raise this GPU"
                    );
                    continue;
                }
            };
            let Ok(frequencies) = fs::read_to_string(device.join("available_frequencies")) else {
                continue;
            };
            if let Some(floor) = Self::new(device, min_freq, &frequencies) {
                return Some(floor);
            }
        }
        None
    }
}

impl<M: MinFreq> GpuFloor<M> {
    /// Takes over the device's minimum and sets it to the lowest operating
    /// point. That also undoes a floor an earlier Denial left raised when it
    /// exited.
    fn new(device: PathBuf, min_freq: M, frequencies: &str) -> Option<Self> {
        let (resting, boost) = operating_range(frequencies)?;
        let found = min_freq.read_hz().ok();
        if let Err(error) = min_freq.write_hz(resting) {
            tracing::info!(
                %error,
                device = %device.display(),
                "GPU interaction floor unavailable: could not set the GPU minimum frequency"
            );
            return None;
        }
        tracing::info!(
            device = %device.display(),
            boost_hz = boost,
            resting_hz = resting,
            found_hz = found,
            "GPU interaction floor active"
        );
        Some(Self {
            device,
            min_freq,
            boost,
            resting,
            raised: false,
        })
    }

    /// Raises the minimum frequency to the highest operating point for an
    /// interaction. It writes even when the minimum already reads that high:
    /// the reading may be the driver's boost, which lapses after 50 ms.
    pub(super) fn raise(&mut self) {
        if self.raised {
            return;
        }
        match self.min_freq.write_hz(self.boost) {
            Ok(()) => self.raised = true,
            Err(error) => tracing::debug!(%error, "could not raise the GPU interaction floor"),
        }
    }

    /// Returns the minimum to the lowest operating point.
    pub(super) fn lower(&mut self) {
        if !self.raised {
            return;
        }
        self.raised = false;
        if let Err(error) = self.min_freq.write_hz(self.resting) {
            tracing::warn!(
                %error,
                device = %self.device.display(),
                resting_hz = self.resting,
                "could not return the GPU minimum frequency to its resting value"
            );
        }
    }
}

impl<M: MinFreq> Drop for GpuFloor<M> {
    fn drop(&mut self) {
        self.lower();
    }
}

/// The lowest and the highest of the device's operating points, from its
/// `available_frequencies`, which devfreq lists in the driver's order.
fn operating_range(list: &str) -> Option<(u64, u64)> {
    let frequencies = list
        .split_whitespace()
        .filter_map(|value| value.parse::<u64>().ok());
    frequencies.fold(None, |range, hz| match range {
        None => Some((hz, hz)),
        Some((lowest, highest)) => Some((lowest.min(hz), highest.max(hz))),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};
    use std::os::unix::fs::symlink;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// The Adreno 830 of the OnePlus Pad 3 (SM8750).
    const FREQUENCIES: &str = "1100000000 967000000 900000000 832000000 734000000 660000000 \
                               607000000 525000000 443000000 389000000 342000000 222000000 \
                               160000000\n";
    const LOWEST: u64 = 160_000_000;
    const HIGHEST: u64 = 1_100_000_000;

    /// A GPU devfreq device as msm and devfreq keep it. PM QoS holds every
    /// minimum request in kHz; `min_freq` shows the highest of them, at
    /// least the lowest operating point and at most the current maximum
    /// (`devfreq_get_freq_range`). A write replaces only the request that
    /// `min_freq` owns (`min_freq_store`, rounded down to kHz).
    struct Devfreq {
        maximum_khz: Cell<u64>,
        user_khz: Cell<u64>,
        /// msm's boost request (`msm_devfreq_boost`), 0 when none is active.
        boost_khz: Cell<u64>,
        writes: RefCell<Vec<u64>>,
    }

    impl Devfreq {
        fn new() -> Self {
            Self {
                maximum_khz: Cell::new(HIGHEST / 1000),
                user_khz: Cell::new(0),
                boost_khz: Cell::new(0),
                writes: RefCell::new(Vec::new()),
            }
        }

        /// The driver's boost: twice the frequency it runs at.
        fn boost(&self, running_hz: u64) {
            self.boost_khz.set(running_hz * 2 / 1000);
        }

        fn boost_lapses(&self) {
            self.boost_khz.set(0);
        }

        fn user_hz(&self) -> u64 {
            self.user_khz.get() * 1000
        }
    }

    impl MinFreq for &Devfreq {
        fn read_hz(&self) -> io::Result<u64> {
            let requested = self.user_khz.get().max(self.boost_khz.get()) * 1000;
            let maximum = self.maximum_khz.get() * 1000;
            Ok(requested.max(LOWEST).min(maximum))
        }

        fn write_hz(&self, hz: u64) -> io::Result<()> {
            self.writes.borrow_mut().push(hz);
            self.user_khz.set(hz / 1000);
            Ok(())
        }
    }

    fn floor(devfreq: &Devfreq) -> GpuFloor<&Devfreq> {
        GpuFloor::new(
            PathBuf::from("/sys/class/devfreq/3d00000.gpu"),
            devfreq,
            FREQUENCIES,
        )
        .unwrap()
    }

    #[test]
    fn finds_the_lowest_and_highest_operating_points() {
        assert_eq!(operating_range(FREQUENCIES), Some((LOWEST, HIGHEST)));
        let ascending = "259000000 355000000 600000000 900000000 1150000000 975000000\n";
        assert_eq!(
            operating_range(ascending),
            Some((259_000_000, 1_150_000_000))
        );
        assert_eq!(operating_range(" \n"), None);
    }

    /// The tablet's minimum stuck at 684 MHz: a touch arrived while msm
    /// boosted the GPU from 342 MHz, and the boost was read back as the
    /// minimum to restore. The GPU then never ran below 734 MHz.
    #[test]
    fn touches_during_driver_boosts_return_to_the_lowest_operating_point() {
        let devfreq = Devfreq::new();
        let mut floor = floor(&devfreq);
        assert_eq!(devfreq.user_hz(), LOWEST);
        for running in [342_000_000, 734_000_000, 222_000_000, 660_000_000] {
            devfreq.boost(running);
            floor.raise();
            assert_eq!(devfreq.user_hz(), HIGHEST);
            floor.lower();
            assert_eq!(devfreq.user_hz(), LOWEST, "after a touch at {running} Hz");
            devfreq.boost_lapses();
            assert_eq!((&devfreq).read_hz().unwrap(), LOWEST);
        }
        assert_eq!(
            *devfreq.writes.borrow(),
            [
                LOWEST, HIGHEST, LOWEST, HIGHEST, LOWEST, HIGHEST, LOWEST, HIGHEST, LOWEST
            ]
        );
    }

    /// A boost from 550 MHz or more reads as the highest operating point.
    /// The floor must still be requested, or it ends with the boost, 50 ms
    /// into the touch.
    #[test]
    fn raises_while_a_driver_boost_reads_as_the_highest_point() {
        let devfreq = Devfreq::new();
        let mut floor = floor(&devfreq);
        devfreq.boost(607_000_000);
        assert_eq!((&devfreq).read_hz().unwrap(), HIGHEST);
        floor.raise();
        devfreq.boost_lapses();
        assert_eq!((&devfreq).read_hz().unwrap(), HIGHEST);
        floor.lower();
        assert_eq!((&devfreq).read_hz().unwrap(), LOWEST);
    }

    /// A thermal limit lowers what `min_freq` reads, not the request.
    #[test]
    fn a_thermal_limit_does_not_change_the_resting_floor() {
        let devfreq = Devfreq::new();
        let mut floor = floor(&devfreq);
        devfreq.maximum_khz.set(734_000);
        floor.raise();
        assert_eq!((&devfreq).read_hz().unwrap(), 734_000_000);
        floor.lower();
        devfreq.maximum_khz.set(HIGHEST / 1000);
        assert_eq!(devfreq.user_hz(), LOWEST);
        assert_eq!((&devfreq).read_hz().unwrap(), LOWEST);
    }

    #[test]
    fn start_undoes_a_floor_left_behind_and_drop_lowers() {
        let devfreq = Devfreq::new();
        // An earlier Denial exited with its floor raised, or with a boost
        // kept as its minimum; msm is boosting as well.
        devfreq.user_khz.set(684_000);
        devfreq.boost(734_000_000);
        let mut floor = floor(&devfreq);
        assert_eq!(devfreq.user_hz(), LOWEST);
        floor.raise();
        floor.raise();
        assert_eq!(
            devfreq.writes.borrow().len(),
            2,
            "a raised floor is not rewritten"
        );
        drop(floor);
        assert_eq!(devfreq.user_hz(), LOWEST);
        assert_eq!(*devfreq.writes.borrow(), [LOWEST, HIGHEST, LOWEST]);
    }

    #[test]
    fn lowering_without_a_raise_writes_nothing() {
        let devfreq = Devfreq::new();
        let mut floor = floor(&devfreq);
        floor.lower();
        drop(floor);
        assert_eq!(*devfreq.writes.borrow(), [LOWEST]);
    }

    static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(0);

    /// A `/sys/class/devfreq` with a storage controller and an Adreno GPU.
    struct SysfsFixture(PathBuf);

    impl SysfsFixture {
        fn new() -> Self {
            let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
            let root = std::env::temp_dir().join(format!(
                "denial-gpu-floor-{}-{sequence}",
                std::process::id()
            ));
            for directory in [
                "devfreq",
                "devices",
                "drivers/adreno",
                "drivers/ufshcd-qcom",
            ] {
                fs::create_dir_all(root.join(directory)).unwrap();
            }
            Self(root)
        }

        fn device(&self, name: &str, driver: &str, minimum: &str) -> PathBuf {
            let device = self.0.join("devices").join(name);
            fs::create_dir(&device).unwrap();
            symlink(self.0.join("drivers").join(driver), device.join("driver")).unwrap();
            let node = self.0.join("devfreq").join(name);
            fs::create_dir(&node).unwrap();
            symlink(&device, node.join("device")).unwrap();
            fs::write(node.join("min_freq"), minimum).unwrap();
            fs::write(node.join("available_frequencies"), FREQUENCIES).unwrap();
            node
        }
    }

    impl Drop for SysfsFixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn discovers_the_adreno_device_and_sets_its_resting_floor() {
        let sysfs = SysfsFixture::new();
        // Sorted first, but not a GPU: left alone.
        let storage = sysfs.device("1d84000.ufshc", "ufshcd-qcom", "300000000\n");
        // sysfs takes each write whole; a regular file keeps the bytes after
        // a shorter one, so the values here have the same length.
        let gpu = sysfs.device("3d00000.gpu", "adreno", "684000000\n");
        let mut floor = GpuFloor::discover_in(&sysfs.0.join("devfreq")).unwrap();
        assert_eq!(floor.device, gpu);
        assert_eq!((floor.resting, floor.boost), (LOWEST, HIGHEST));
        assert_eq!(
            fs::read_to_string(gpu.join("min_freq")).unwrap(),
            "160000000\n"
        );
        assert_eq!(
            fs::read_to_string(storage.join("min_freq")).unwrap(),
            "300000000\n"
        );
        floor.raise();
        assert_eq!(floor.min_freq.read_hz().unwrap(), HIGHEST);
    }

    #[test]
    fn discovery_skips_a_gpu_without_operating_points() {
        let sysfs = SysfsFixture::new();
        let gpu = sysfs.device("3d00000.gpu", "adreno", "684000000\n");
        fs::write(gpu.join("available_frequencies"), "\n").unwrap();
        assert!(GpuFloor::discover_in(&sysfs.0.join("devfreq")).is_none());
        assert_eq!(
            fs::read_to_string(gpu.join("min_freq")).unwrap(),
            "684000000\n"
        );
    }
}
