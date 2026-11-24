//! Finger motion from a touchpad, resampled at the display's pace.
//!
//! A touchpad reports at its own rate, and not evenly: the Pad 3 keyboard
//! cover's scans at 118.6 Hz and delivers about 7 % of its reports late,
//! 13–17 ms after the one before, the next one 2–3 ms after that
//! (`research/touchpad.md` in the distro workspace). Motion applied as
//! reports arrive advances on some refreshes twice and on others not at all:
//! at 120 Hz a strip or an overview following three fingers holds still for a
//! refresh whenever a report is late or the two rates beat, and the next
//! refresh jumps. Flutter resamples touch pointers for the same reason.
//!
//! [`MotionResampler`] keeps the reports of one motion with their times and
//! gives every output frame the motion up to [`SAMPLE_DELAY`] before the
//! frame: interpolated between the two reports around that time, or, when
//! the next report is late, carried on at the last reports' speed for at most
//! [`EXTRAPOLATION_LIMIT`]. A late report then corrects the position over the
//! following frames instead of stalling one. The motion reaches its last
//! report when it ends ([`MotionResampler::finish`]), so nothing is lost.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// How long before a frame the motion is sampled: about three quarters of a
/// report interval of the cover's touchpad, so a report that arrived on time
/// usually lies on both sides of the sample, at the cost of that much
/// latency. Its reports carry their arrival time; with the late ones that is
/// as uneven as their delivery, which a shorter delay follows more closely.
pub(super) const SAMPLE_DELAY: Duration = Duration::from_micros(6_000);

/// How far past its last report a motion is carried on at its speed: one
/// report interval, the length of a late report's gap.
pub(super) const EXTRAPOLATION_LIMIT: Duration = Duration::from_micros(8_500);

/// Reports older than this are not needed to interpolate or to measure the
/// speed.
const HISTORY: Duration = Duration::from_millis(100);

#[derive(Clone, Copy, Debug, PartialEq)]
struct Report {
    time_micros: u64,
    /// The motion since the start, up to and including this report.
    position: f64,
}

/// One finger motion along one axis, in the reports' own units.
#[derive(Debug, Default)]
pub(super) struct MotionResampler {
    reports: VecDeque<Report>,
    /// Where the motion is, by its last report.
    position: f64,
    /// How much of it frames have been given.
    applied: f64,
}

impl MotionResampler {
    /// Starts a motion at `time_micros` from where it is (zero).
    pub(super) fn begin(time_micros: u64) -> Self {
        let mut resampler = Self::default();
        resampler.reports.push_back(Report {
            time_micros,
            position: 0.0,
        });
        resampler
    }

    /// A report: the fingers moved by `delta` at `time_micros`. A report
    /// older than the last one is merged into it.
    pub(super) fn push(&mut self, time_micros: u64, delta: f64) {
        self.position += delta;
        let time_micros = self
            .reports
            .back()
            .map_or(time_micros, |last| time_micros.max(last.time_micros));
        if let Some(last) = self.reports.back_mut()
            && last.time_micros == time_micros
        {
            last.position = self.position;
        } else {
            self.reports.push_back(Report {
                time_micros,
                position: self.position,
            });
        }
        while self.reports.len() > 2
            && self.reports[1].time_micros + (HISTORY.as_micros() as u64) < time_micros
        {
            self.reports.pop_front();
        }
    }

    /// Whether frames have not yet been given all the motion reported.
    pub(super) fn pending(&self) -> bool {
        self.applied != self.position
    }

    /// The motion to apply for a frame sampled at `time_micros` (the frame's
    /// time minus [`SAMPLE_DELAY`]): the change since the previous frame.
    pub(super) fn take(&mut self, time_micros: u64) -> f64 {
        let target = self.position_at(time_micros);
        let delta = target - self.applied;
        self.applied = target;
        delta
    }

    /// The rest of the motion, when it ends.
    pub(super) fn finish(&mut self) -> f64 {
        let delta = self.position - self.applied;
        self.applied = self.position;
        delta
    }

    fn position_at(&self, time_micros: u64) -> f64 {
        let Some(last) = self.reports.back() else {
            return self.applied;
        };
        if time_micros >= last.time_micros {
            return last.position + self.extrapolation(time_micros - last.time_micros);
        }
        let Some(index) = self
            .reports
            .iter()
            .rposition(|report| report.time_micros <= time_micros)
        else {
            // Before the first report: the motion had not started.
            return self.reports.front().map_or(0.0, |first| first.position);
        };
        let before = self.reports[index];
        let after = self.reports[index + 1];
        let span = (after.time_micros - before.time_micros) as f64;
        let share = (time_micros - before.time_micros) as f64 / span;
        before.position + (after.position - before.position) * share
    }

    /// Where the motion's recent speed carries it `elapsed_micros` after its
    /// last report, for at most [`EXTRAPOLATION_LIMIT`]; never past a stop.
    fn extrapolation(&self, elapsed_micros: u64) -> f64 {
        let count = self.reports.len();
        if count < 2 {
            return 0.0;
        }
        let last = self.reports[count - 1];
        let previous = self.reports[count - 2];
        let span = last.time_micros.saturating_sub(previous.time_micros);
        // A pause longer than a late report is a stop, not motion to carry on.
        if span == 0 || span > EXTRAPOLATION_LIMIT.as_micros() as u64 * 2 {
            return 0.0;
        }
        let speed = (last.position - previous.position) / span as f64;
        let elapsed = elapsed_micros.min(EXTRAPOLATION_LIMIT.as_micros() as u64);
        speed * elapsed as f64
    }
}

/// What a touchpad swipe that follows the fingers moves.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum TouchpadMotionTarget {
    /// A scrolling strip, by each frame's share of the motion.
    Strip,
    /// The full-screen apps layout's overview or app windows, to the travel
    /// since the swipe started.
    Shell,
}

/// A touchpad swipe under way, resampled for the output's frames: started
/// by the swipe's begin, fed by its updates, sampled shortly before each
/// output frame and ended (with the rest of its motion) by its end.
#[derive(Debug)]
pub(super) struct TouchpadMotion {
    pub(super) target: TouchpadMotionTarget,
    pub(super) resampler: MotionResampler,
    /// The travel of the latest report and the one given to the shell (the
    /// swipe's units; [`TouchpadMotionTarget::Shell`] only).
    reported_travel: f64,
    pub(super) travel: f64,
    /// The swipe's latest speed, in its units per second.
    pub(super) velocity: f64,
    /// The output frame this motion was last sampled for.
    pub(super) sampled_frame: Option<Instant>,
}

impl TouchpadMotion {
    /// A strip that started moving at `time_micros`; the swipe's begin moved
    /// it already.
    pub(super) fn strip(time_micros: u64) -> Self {
        Self::new(TouchpadMotionTarget::Strip, time_micros, 0.0)
    }

    /// A shell gesture that began at `travel` at `time_micros`.
    pub(super) fn shell(time_micros: u64, travel: f64) -> Self {
        Self::new(TouchpadMotionTarget::Shell, time_micros, travel)
    }

    fn new(target: TouchpadMotionTarget, time_micros: u64, travel: f64) -> Self {
        Self {
            target,
            resampler: MotionResampler::begin(time_micros),
            reported_travel: travel,
            travel,
            velocity: 0.0,
            sampled_frame: None,
        }
    }

    /// A strip report: the fingers moved by `delta`.
    pub(super) fn report_delta(&mut self, time_micros: u64, delta: f64) {
        self.resampler.push(time_micros, delta);
    }

    /// A shell report: the fingers have travelled `travel` since the start.
    pub(super) fn report_travel(&mut self, time_micros: u64, travel: f64, velocity: f64) {
        self.resampler
            .push(time_micros, travel - self.reported_travel);
        self.reported_travel = travel;
        self.velocity = velocity;
    }

    /// The frame due at `frame`, sampled at `frame_micros` on the clock of
    /// the reports: the strip's motion for it, or the shell's new travel.
    /// None when it does not move or was sampled for that frame already.
    pub(super) fn sample(&mut self, frame: Instant, frame_micros: u64) -> Option<f64> {
        if self.sampled_frame == Some(frame) {
            return None;
        }
        self.sampled_frame = Some(frame);
        let delta = self
            .resampler
            .take(frame_micros.saturating_sub(SAMPLE_DELAY.as_micros() as u64));
        if delta == 0.0 {
            return None;
        }
        self.travel += delta;
        Some(match self.target {
            TouchpadMotionTarget::Strip => delta,
            TouchpadMotionTarget::Shell => self.travel,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SCAN: u64 = 8_430;
    const FRAME: u64 = 8_333;

    /// Reports (arrival time, motion) given to frames at 120 Hz, resampled
    /// and as they arrive: the motion of each frame, both ways.
    fn run(reports: &[(u64, f64)], frames: impl Iterator<Item = u64>) -> (Vec<f64>, Vec<f64>) {
        let mut resampler = MotionResampler::begin(0);
        let mut next = 0;
        let (mut resampled, mut arrived) = (Vec::new(), Vec::new());
        for frame in frames {
            let mut raw = 0.0;
            while next < reports.len() && reports[next].0 <= frame {
                resampler.push(reports[next].0, reports[next].1);
                raw += reports[next].1;
                next += 1;
            }
            resampled.push(resampler.take(frame - SAMPLE_DELAY.as_micros() as u64));
            arrived.push(raw);
        }
        (resampled, arrived)
    }

    #[test]
    fn every_frame_moves_while_reports_are_late_or_beat_with_the_display() {
        // Even 118.6 Hz scans, 10 units each, delivered with the cover's
        // pattern: every 14th report late by 6 ms, the next 2 ms after it.
        let mut reports = Vec::new();
        let mut late_until = 0;
        for index in 1..=60_u64 {
            let scan = index * SCAN;
            let mut arrival = scan;
            if index % 14 == 0 {
                arrival = scan + 6_000;
                late_until = arrival + 2_000;
            } else if arrival < late_until {
                arrival = late_until;
            }
            reports.push((arrival, 10.0));
        }
        let (resampled, arrived) = run(&reports, (1..58).map(|frame| frame * FRAME));
        // Applied as they arrive, some refreshes get no motion and others two
        // or three reports' worth.
        assert!(arrived[1..].iter().any(|delta| *delta == 0.0), "{arrived:?}");
        assert!(arrived[1..].iter().any(|delta| *delta >= 20.0), "{arrived:?}");
        // Resampled, every refresh moves, by about one report (10) a refresh.
        let steady = &resampled[1..];
        assert!(steady.iter().all(|delta| *delta > 4.0), "{resampled:?}");
        assert!(steady.iter().all(|delta| *delta < 19.0), "{resampled:?}");
    }

    #[test]
    fn interpolates_between_reports_around_the_sample() {
        let mut resampler = MotionResampler::begin(0);
        resampler.push(10_000, 10.0);
        resampler.push(20_000, 10.0);
        assert_eq!(resampler.take(15_000), 15.0);
        assert_eq!(resampler.take(20_000), 5.0);
        assert!(!resampler.pending());
    }

    #[test]
    fn a_late_report_is_carried_on_at_most_one_interval_and_corrected() {
        let mut resampler = MotionResampler::begin(0);
        resampler.push(8_000, 8.0);
        resampler.push(16_000, 8.0);
        // The next report is late: the sample goes on at 1 unit per ms...
        assert_eq!(resampler.take(20_000), 20.0);
        // ...no further than EXTRAPOLATION_LIMIT past the last report.
        let carried = resampler.take(60_000);
        assert!((carried - 4.5).abs() < 1e-9, "{carried}");
        // The late report says the fingers slowed down: the next frames
        // follow it, and the end gives the rest exactly.
        resampler.push(30_000, 2.0);
        let corrected = resampler.take(30_000);
        assert!(corrected < 0.0, "{corrected}");
        assert_eq!(resampler.finish(), 0.0);
        assert_eq!(resampler.applied, 18.0);
    }

    #[test]
    fn a_stop_is_not_extrapolated() {
        let mut resampler = MotionResampler::begin(0);
        resampler.push(8_000, 8.0);
        resampler.push(40_000, 0.5);
        assert_eq!(resampler.take(48_000), 8.5);
    }

    #[test]
    fn finish_gives_all_the_reported_motion() {
        let mut resampler = MotionResampler::begin(0);
        for index in 1..=10 {
            resampler.push(index * SCAN, 3.0);
        }
        let mut total = resampler.take(5 * SCAN);
        assert!(resampler.pending());
        total += resampler.finish();
        assert_eq!(total, 30.0);
        assert!(!resampler.pending());
    }

    #[test]
    fn out_of_order_reports_merge_into_the_last() {
        let mut resampler = MotionResampler::begin(0);
        resampler.push(10_000, 5.0);
        resampler.push(9_000, 5.0);
        assert_eq!(resampler.reports.len(), 2);
        assert_eq!(resampler.take(10_000), 10.0);
    }
}
