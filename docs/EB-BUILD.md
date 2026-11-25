# Building Denial 0.6.8 parts for the tablet (EvilBorsch fork)

This fork changes Denial's Flutter shell (`dart_shell`, `plugins/*`,
`packages/*`), the compositor `deniald` and its portal `denial-portal`; the
fork [EvilBorsch/denial-apps](https://github.com/EvilBorsch/denial-apps)
changes Settings. The Flutter engine package (`denial-flutter-engine`
0.6.8-1, ABI `3.47.5.denial1`), `denialctl`, the polkit agent and Settings'
Wi-Fi country helper stay the signed v0.6.8 release builds. A change is
installed as a `denial` package made from the release's, in which only these
differ:

- `/usr/lib/denial/flutter/lib/libapp.so`, the AOT-compiled shell;
- `/usr/lib/denial/flutter/data/flutter_assets/`, its assets;
- `/usr/bin/deniald`, when the change touches the compositor;
- `/usr/bin/denial-portal`, with a `deniald` that speaks portal protocol 3
  (`eb/mode-follow` and later);
- `/usr/lib/denial-apps/settings`, when the change touches Settings.

## Why no engine build is needed

The AOT shell must fit the installed engine exactly: the same Dart VM
(snapshot version `0451907c2eaa8467e848c0067bfe8ed4`, features
`product … arm64 linux no-compressed-pointers`) and the same `dart:ui`, which
Denial's Flutter fork extends (glass filters, window surfaces). Denial ships
both in its signed release: the plugin build kit inside
`denial-plugin-manager_0.6.8-1_arm64.deb` carries the fork's
`flutter_patched_sdk` (product `dart:ui`) and the arm64 `gen_snapshot`,
`impellerc` and `font-subset` of the very engine build in
`denial-flutter-engine_0.6.8-1`.

`tools/eb-build-shell` puts those tools behind a Flutter local-engine view,
runs the arm64 ones under qemu-user, and assembles the shell with the fork's
`flutter` tool at the revision in `prebuilt/flutter-engine/SOURCE_LOCK.json`
and the same defines as `tools/denial-pc build_bundle`. It fails unless the
result carries the 0.6.8 engine's snapshot identity.

Verified on 22.11.2026: built from the untouched `v0.6.8` tag, the bundle is
bit-identical to the release's (`libapp.so` SHA-256
`c09d7b6b4b399e23c27969d3e8675b323c043734cc9aa3b08d7b9e99d8d8d168`, and all
33 files of `flutter_assets`).

`deniald` loads the engine with `dlopen` and talks to it through the
embedder API of the same ABI, so a rebuilt `deniald` runs with the release's
engine package as long as `FLUTTER_ENGINE_ABI` stays `3.47.5.denial1`.

## Prerequisites

An x86-64 Linux host (here WSL Ubuntu 26.04) with network access and:

```sh
sudo apt install git curl dpkg qemu-user libc6-arm64-cross python3 rsync unzip \
    mmdebstrap gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu pkg-config
```

For `deniald`, rustup with the toolchain that `rust-toolchain.toml` pins
(1.98.0) and the target `aarch64-unknown-linux-gnu`.

Caches go to `$EB_WORK` (default `~/work-denial-shell`, about 2 GB): the
Flutter fork checkout with its downloaded artifacts and Dart 3.13.4, and the
extracted build kit. Downloads are pinned by SHA-256 or Git revision.

## Build the shell bundle

```sh
git clone https://github.com/EvilBorsch/denial ~/androidlinux/components/denial
cd ~/androidlinux/components/denial
git checkout eb/compositor-inhibit-keyboard   # or the branch to build
EB_JOBS=4 tools/eb-build-shell ~/work-denial-shell/out
```

The first run takes about 15 minutes (most of it the AOT compiler under
qemu), later runs about 4 to 10. The output directory has the layout of
`/usr/lib/denial/flutter/`:

```
lib/libapp.so
data/flutter_assets/...
```

The bundle keeps the release's `.denial-ui-source.json` on the device: plugin
bundles built with the 0.6.8 kit keep loading.

## Build deniald

`deniald` is cross-built on the x86-64 host against an Ubuntu 26.04 arm64
root, the libraries the tablet runs (glibc 2.43). Upstream's tools expect an
Arch Linux ARM root; `denial_cross_configure_rust` in
`tools/lib/denial-architecture.sh` also takes a Debian or Ubuntu root, whose
libraries and pkg-config files are in `/usr/lib/aarch64-linux-gnu`.

Make the root once, as root (about 4 minutes, 376 MB):

```sh
sudo tools/eb-arm64-sysroot ~/work-denial-sysroot
```

It extracts the `-dev` packages `deniald` builds against, with their
dependencies, from `ports.ubuntu.com` (`resolute`, `-updates`, `-security`)
with mmdebstrap's extract variant: no maintainer scripts run, so no
emulator is needed. `EB-SYSROOT-PACKAGES.txt` in the root lists the exact
packages (on 22.11.2026: `libc6 2.43-2ubuntu2.7`, `libinput10
1.31.1-1ubuntu1.2`, `libseat1 0.9.2-2`, `libgbm1 26.0.8-1ubuntu0.3`,
`libudev1 259.9-0ubuntu0.1`, `libxkbcommon0 1.13.1-1`, 190 in all).

Build, as the release does (`cargo build --locked --release --features
flutter --bin deniald`, default features):

```sh
EB_JOBS=8 tools/eb-build-deniald build ~/work-denial-sysroot ~/work-denial-deniald/out
```

About 8 minutes with 8 jobs. The Cargo target directory is
`~/work-denial-deniald/target` (`EB_WORK`). The binary names the fork's
commit as its build (`deniald --version`: `deniald 0.6.8 (build
eb.g<commit>; …)` once installed); `out/deniald.txt` lists its SHA-256, the
libraries it links and the glibc symbol versions it needs.

The same command builds `denial-portal` (`cargo build --locked --release -p
denial-portal`, as the release does) into `out/denial-portal`, with
`out/denial-portal.txt`. `deniald` and the portal speak one private protocol
(`src/portal_protocol.rs`); since protocol version 3 (the shell's state for
apps, docs/APPS_FOLLOW_MODE.md) a `deniald` of this fork needs its own
portal, and the release's portal refuses it.

### Checked against the release

Built the same way from the untouched `v0.6.8` tag
(`EB_BUILD_IDENTITY=main.g01b588ec50831bce9e57aed623901f49846ec791`), the
binary is not byte-identical to the release's (another root and linker), but
on 22.11.2026:

- it links the same eight libraries as the release's `deniald`
  (`libgbm.so.1 libseat.so.1 libudev.so.1 libinput.so.10 libxkbcommon.so.0
  libgcc_s.so.1 libm.so.6 libc.so.6`) with the same interpreter
  `/lib/ld-linux-aarch64.so.1`;
- it imports exactly the same 376 versioned dynamic symbols
  (`objdump -T`), the newest glibc one `GLIBC_2.39`, which is what the
  package's `libc6 (>= 2.39)` says;
- under `qemu-aarch64 -L ~/work-denial-sysroot` its `--help` output is
  identical to the release binary's, and `--version` reports the same build
  identity and engine ABI.

`deniald` 0.6.8-1+eb3 (commit `a0943dd`) differs from it by one import,
`libinput_device_keyboard_has_key@LIBINPUT_0.15.0`, which the keyboard
report uses.

### deniald's tests

```sh
EB_JOBS=8 tools/eb-build-deniald test ~/work-denial-sysroot
EB_JOBS=8 tools/eb-build-deniald test ~/work-denial-sysroot -- idle_policy system_controls
```

The tests run under qemu-aarch64 with the root. On
`eb/compositor-inhibit-keyboard` 692 of 697 pass, 1 is ignored and 4 fail
that need what qemu-user in WSL does not give; they fail the same way on
untouched v0.6.8: the three `cpu_scheduling` kernel tests (utilization clamp
`EOPNOTSUPP` in the WSL kernel; a test re-executing its own binary, which
qemu-user cannot) and the timing-sensitive
`frame_deadline_source_tests::acquire_callback_removes_queued_deadline_source`.
On `eb/mode-follow` 709 of 714 pass with the same 4 failing. On `eb/power-tiles`
735 of 740 pass with the same 4 failing, on `eb/sleep-after-screen-off` 745 of
750. `eb/main` at `8dc3da5` passes 751 of 756 and `eb/pointer-gestures` 764 of
769, the same 4 failing; there
`gpu_transfer::tests::source_wait_accepts_readiness_and_rejects_hangup`, whose
5 ms deadline a busy qemu-user thread can miss, also failed in 2 of 5 full
runs and passes alone. `eb/screens-layout` (eb17) passes 796 of 801 against
764 of 769 on its base `ccadf12`, the same 4 failing; at `2faae0b` (eb18)
888 of 893, the same 4 failing; at `6807c15` (eb19) 922 of 927, the same 4 failing. `eb/window-corners` (eb20,
square windows) passes 925 of 930, the same 4 failing.

The portal's tests and the protocol's run the same way, the D-Bus ones on a
private session bus:

```sh
EB_JOBS=8 tools/eb-build-deniald test-portal ~/work-denial-sysroot
```

On `eb/mode-follow` all pass but
`access::tests::asks_through_the_dialog_and_reports_its_choices`, which
re-executes its own binary as the dialog and fails the same way on `eb/main`.

## Build Settings

Settings and Welcome are one program, `/usr/lib/denial-apps/settings`: the
GPUI application `apps/settings` of
[denial-apps](https://github.com/denialwm/denial-apps), built against
[gpui-touch](https://github.com/denialwm/gpui-touch). `settings/SOURCE_LOCK.json`
names the commits the release built: denial-apps `17c3912`, gpui-touch
`c6d8562`. In the fork `EvilBorsch/denial-apps`, `eb/main` is that
denial-apps commit and changes are on `eb/<topic>` branches; gpui-touch is
not changed and is built at the locked commit.

denial-apps finds gpui-touch beside itself (`../../../gpui-touch` from
`apps/settings`), so the two checkouts sit side by side:

```sh
cd ~/androidlinux/components
git clone https://github.com/EvilBorsch/denial-apps
git -C denial-apps remote add upstream https://github.com/denialwm/denial-apps
git -C denial-apps switch eb/wifi-join          # or the branch to build
git clone https://github.com/denialwm/gpui-touch
git -C gpui-touch checkout --detach c6d856299c3206311045e5135abb4dc0455e97d2
```

Build as the release does (`tools/denial-settings build`: `cargo build
--release --locked` of `apps/settings` with the toolchain of
`rust-toolchain.toml`), cross for aarch64 against the root `deniald` uses;
the one library Settings links, `libxkbcommon`, is in it:

```sh
cd ~/androidlinux/components/denial    # this fork, any branch with the tool
EB_JOBS=4 tools/eb-build-settings build ~/work-denial-sysroot \
    ~/androidlinux/components ~/work-denial-settings/out
```

About 8 minutes the first time with 4 jobs, 4 to 5 after a change to
Settings alone. The Cargo target directory is `~/work-denial-settings/target`
(`EB_WORK`). `out/` gets `settings`, `wifi-country` and `settings.txt`: the
commits built, the hashes, the libraries each links and the GLIBC versions
each needs.

### Checked against the release

Built from the untouched release commit (`eb/main`) on 22.11.2026, `settings`
is not byte-identical to the release's (another root, compiler and build
paths), but:

- it has the release's size, 30 615 784 bytes, and its strings differ only in
  build paths (`/srv/denial-builder/cache/…` there, `~/.cargo/…` here) and in
  the order of merged string data;
- it links the release's libraries (`libxkbcommon.so.0 libgcc_s.so.1
  libm.so.6 libc.so.6`) and needs the same GLIBC versions, the newest
  `GLIBC_2.39`, which the package's `libc6 (>= 2.39)` covers;
- of its 225 versioned imports 222 are the release's. The other three,
  `__stack_chk_fail`, `__stack_chk_guard` and `__vsnprintf_chk` (for
  `vsnprintf`), come from the C parts of `ring` and `wayland-backend`, which
  Ubuntu's `aarch64-linux-gnu-gcc` compiles with its defaults
  `-fstack-protector-strong` and `_FORTIFY_SOURCE=3`; Arch Linux ARM's
  compiler, the release's, has neither by default. The aarch64 dynamic linker
  exports `__stack_chk_guard`, so the binary also names
  `ld-linux-aarch64.so.1`.

### Settings' tests

```sh
EB_JOBS=4 tools/eb-build-settings test ~/work-denial-sysroot \
    ~/androidlinux/components --bin settings
```

They run under qemu-aarch64 with the root; `--release` shares the build's
dependencies. On the release's commit 42 pass, 14 are ignored (they need a
phone or the network) and one fails here,
`cursor_theme::tests::cursor_zip_converts_to_denial_manifest`, whose fixture
runs `bsdtar`, under qemu-user. denial-apps' `eb/wifi-join` adds nine
(`wifi::nm::join_tests`, `words_ru::tests`): 51 pass, the same one fails.
denial-apps' `eb/integration` at `4c5d2bf` (eb12 and eb13) passes 59 and at
`f1735eb` (with `eb/sleep-after-screen-off`, eb14) 63, the same one failing;
`c1d0137` (eb12 to eb16) and `eb/screens-layout` at `97f2875` (eb17) 63, the
same one failing; at `4f8304a` (eb18) 66, the same one failing; at `d68ddf5` (eb19) 72, the same one failing; `eb/window-corners` at `34c4be7` (eb20) 74, none failing.
`denial-look`, the apps' shared look and words, is plain Rust; its tests run
on the host:

```sh
cd ~/androidlinux/components/denial-apps/apps/settings
CARGO_TARGET_DIR=~/work-denial-settings/target-host cargo test --locked -p denial-look
```

## The wire protocol

`protocol/denial.fbs` is compiled into `protocol/generated/{dart,rust}` with
flatc 25.9.23 (`protocol/FLATBUFFERS_VERSION`). Its release binary
(`Linux.flatc.binary.g++-13.zip`, SHA-256
`de0c6ad114a5a686ecf64322528c602c7d4512446a93f290f54f00ee5abea487`)
reproduces the committed code:

```sh
mkdir -p ~/work-denial-flatc/bin && cd ~/work-denial-flatc
curl -fLo flatc.zip https://github.com/google/flatbuffers/releases/download/v25.9.23/Linux.flatc.binary.g++-13.zip
echo "de0c6ad114a5a686ecf64322528c602c7d4512446a93f290f54f00ee5abea487  flatc.zip" | sha256sum -c
python3 -c "import zipfile; zipfile.ZipFile('flatc.zip').extractall('bin')" && chmod +x bin/flatc
cd ~/androidlinux/components/denial
FLATC=~/work-denial-flatc/bin/flatc tools/generate-denial-wire --check   # or without --check to regenerate
```

Add fields only at the end of a table: then a new `deniald` and the
release's shell, or the release's `deniald` and a new shell, still read each
other.

## A complete `denial` package

```sh
EB_PORTAL=~/work-denial-deniald/out/denial-portal \
  tools/eb-repack-deb ~/work-denial-shell/out 0.6.8-1+eb3 ~/debs ~/work-denial-deniald/out/deniald
```

It takes the signed `denial_0.6.8-1_arm64.deb`, replaces the two shell paths
and, with the fourth argument, `/usr/bin/deniald` (with `EB_PORTAL` also
`/usr/bin/denial-portal`, which needs the `deniald` built with it), and sets
the version and maintainer. If the new `deniald` needs a newer glibc than the package's
`libc6 (>= 2.39)`, the tool raises that dependency; likewise the release's
bare `libinput10` becomes `libinput10 (>= X)` for the newest `LIBINPUT_X`
symbol version a new binary imports (`deniald` since `eb/touchpad`: 1.26). Every other file, the
conffiles (`/etc/denial/session.conf` stays as packaged) and the maintainer
scripts are the release's, except that the postinst gives `deniald`
`cap_sys_nice` (the package depends on `libcap2-bin` for `setcap`). It
installs over 0.6.8-1 and earlier `+ebN` builds with the release's engine
package, `denial-flutter-engine (= 0.6.8-1)`.

A fifth argument, a `settings` from `tools/eb-build-settings`, replaces
`/usr/lib/denial-apps/settings` and nothing else of Settings: the Wi-Fi
country helper, the polkit action, the launcher entries and
`/usr/share/denial/settings/SOURCE_LOCK.json` (which still names the release's
commits) stay the release's. `''` as the fourth argument keeps the release's
`deniald`:

```sh
tools/eb-repack-deb ~/work-denial-shell/out 0.6.8-1+eb11 ~/debs \
    ~/work-denial-deniald/out/deniald ~/work-denial-settings/out/settings
```

The tool reads the denial-apps commit from `settings.txt` beside the binary,
refuses one built with uncommitted changes or not the binary `settings.txt`
describes, and names the commit in the package description. Its glibc check
covers Settings as it does `deniald`.

## Shell tests

Denial runs its widget tests on its own engine's `flutter_tester`
(`tools/denial-flutter-engine test`), which needs the engine build. Without
it, upstream Flutter 3.47.5's `flutter_tester` with the fork's `dart:ui`
kernel from the kit runs everything that does not draw with Denial's engine
additions:

```sh
W=~/work-denial-shell; F=$W/flutter
K=$W/kit/usr/lib/denial/plugin-build-kit/engine/out/denial_linux_arm64_release
T=$W/test-view/out/denial_host_debug
mkdir -p $T
ln -sfn $F/bin/cache/artifacts/engine/linux-x64/flutter_tester $T/flutter_tester
ln -sfn $F/bin/cache/artifacts/engine/linux-x64/icudtl.dat $T/icudtl.dat
ln -sfn $F/bin/cache/dart-sdk $T/dart-sdk
ln -sfn $K/flutter_patched_sdk $T/flutter_patched_sdk
cd dart_shell
$F/bin/flutter test --local-engine-src-path=$W/test-view \
  --local-engine=denial_host_debug --local-engine-host=denial_host_debug test
```

On v0.6.8 this passes 188 tests and fails 12 that need Denial's engine
(`left_app_test`, `session_power_test`, one of `phone_desk_test`, two of
`mobile_connectivity_marks_test`); `eb/lockscreen-keyboard` passes 193 and
`eb/compositor-inhibit-keyboard` 196, with the same 12 failing; `eb/mode-follow`
223 with the same 12 failing, and `packages/denial_flutter_sdk` all 111;
`eb/integration` at `d2baa59` 244, `eb/power-tiles` 256 and
`eb/sleep-after-screen-off` 261, with the same 12 failing, and the SDK all
111. `eb/main` at `ccadf12` passes 261 and `eb/screens-layout` (eb17) 278,
with the same 12 failing, and the SDK all 111; `eb/screens-layout` at
`2faae0b` (eb18) 413 with the same 12 failing, and the SDK all 135; at `6807c15` (eb19) 501 with the same 12 failing, and the SDK all 144;
`eb/window-corners` (eb20) 510 with the same 12 failing, and the SDK all 144.

## Build the Flutter engine

Only an engine change (Impeller, Skia) needs this; the shell and `deniald`
build against the release engine as above. The engine sources are the forks
[EvilBorsch/flutter](https://github.com/EvilBorsch/flutter) and
[EvilBorsch/skia](https://github.com/EvilBorsch/skia) of Denial's, whose
`eb/main` starts at the commits `prebuilt/flutter-engine/SOURCE_LOCK.json`
names. Besides the prerequisites above, `sudo apt install jq ninja-build`.

`tools/eb-engine-sources` makes the source trees `tools/denial-flutter-engine`
takes as external sources: shallow clones of both forks in
`~/androidlinux/components/{flutter,skia}`, the Flutter tree synchronized by
gclient with Skia linked in from its own fork. About 30 minutes and 27 GB,
plus 2.7 GB of depot_tools and Python in `~/.cache/denial/flutter-engine`.
Then the release engine, with the release's GN arguments:

```sh
DENIAL_TARGET_ARCH=aarch64 \
DENIAL_FLUTTER_SOURCE_ROOT=$HOME/androidlinux/components/flutter \
DENIAL_SKIA_SOURCE_ROOT=$HOME/androidlinux/components/skia \
DENIAL_FLUTTER_ENGINE_JOBS=8 \
    tools/denial-flutter-engine build
```

It refuses trees that are not clean at the locked commits and an engine that
differs from `linux-arm64-release/libflutter_engine.so.sha256`. The output is
`~/.cache/denial/flutter-engine/build/out/denial_linux_arm64_release` (370 MB).
Eight jobs keep the 20 GB WSL machine clear of the memory limit.

Verified on 25.11.2026: 19 minutes, and `libflutter_engine.so` is
bit-identical to the one in `denial-flutter-engine_0.6.8-1_arm64.deb`
(SHA-256 `af2435ed14ce971fc249eaf2aa7bd2e5a0ef963069794db69396cb3c88a0fcff`).

`build` makes the engine library only. A changed engine is built from the
trees as they are on disk by `prepare-app-build` with the same environment
(Denial's development path; not run here yet), which also builds the arm64
`gen_snapshot`, `impellerc`, `font-subset` and `flutter_patched_sdk` and the
build machine's Dart SDK. A change to Impeller or Skia leaves the Dart VM and
`dart:ui` alone, so the shell from `tools/eb-build-shell` stays valid for it:
the snapshot identity `0451907c2eaa8467e848c0067bfe8ed4` is in the engine as
in `libapp.so`.

Denial renders with Impeller GLES only: the engine is built with
`shell_enable_vulkan = false`, and `deniald` hands the engine an OpenGL
renderer configuration (`FlutterRendererType_kOpenGL` in
`compositor/flutter-engine/src/host.rs`); no setting or environment variable
selects another. Impeller Vulkan would need both an engine and a `deniald`
change. The engine without the three Vulkan-off arguments does not compile
in a Slimpeller build: the embedder still compiles its Skia Vulkan surface
(`embedder_surface_vulkan.{h,cc}`), whose `ContextType` Slimpeller leaves
out; everything else compiles (`ninja -k 0`). It needs the `!slimpeller`
gate the GL Skia surface has. `deniald` would have to supply a `FlutterVulkanRendererConfig` and
Vulkan backing stores, and the embedder API has no Vulkan external textures,
through which Denial shows client windows today.

## Another Denial release

The pins in `tools/eb-build-shell` and `tools/eb-repack-deb` (kit and package
SHA-256, snapshot identity) belong to v0.6.8. For another release, take that
release's `denial-plugin-manager_*_arm64.deb` and `denial_*_arm64.deb`, check
them against its signed `SHA256SUMS`, read the snapshot identity of its
`libapp.so`, update the pins, and first rebuild the untouched release tag to
confirm a bit-identical shell and a `deniald` with the release's libraries
and symbol imports.
