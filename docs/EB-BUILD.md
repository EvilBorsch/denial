# Building the shell for an installed Denial 0.6.8 (EvilBorsch fork)

This fork changes only Denial's Flutter shell (`dart_shell`, `plugins/*`,
`packages/*`). The compositor (`deniald`), the Flutter engine package
(`denial-flutter-engine` 0.6.8-1, ABI `3.47.5.denial1`) and Settings stay the
signed v0.6.8 release builds. A change is installed by replacing the shell's
two files in `/usr/lib/denial/flutter/`:

- `lib/libapp.so`, the AOT-compiled shell;
- `data/flutter_assets/`, its assets.

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

## Prerequisites

An x86-64 Linux host (here WSL Ubuntu 26.04) with network access and:

```sh
sudo apt install git curl dpkg qemu-user libc6-arm64-cross python3 rsync unzip
```

Caches go to `$EB_WORK` (default `~/work-denial-shell`, about 2 GB): the
Flutter fork checkout with its downloaded artifacts and Dart 3.13.4, and the
extracted build kit. Downloads are pinned by SHA-256 or Git revision.

## Build the shell bundle

```sh
git clone https://github.com/EvilBorsch/denial ~/androidlinux/components/denial
cd ~/androidlinux/components/denial
git checkout eb/lockscreen-keyboard        # or the branch to build
EB_JOBS=4 tools/eb-build-shell ~/work-denial-shell/out
```

The first run takes about 15 minutes (most of it the AOT compiler under
qemu), later runs about 4 to 10. The output directory has the layout of
`/usr/lib/denial/flutter/`:

```
lib/libapp.so
data/flutter_assets/...
```

Pack it for the tablet:

```sh
tar -C ~/work-denial-shell/out -czf denial-shell-0.6.8-eb1-lockscreen.tar.gz lib data
sha256sum denial-shell-0.6.8-eb1-lockscreen.tar.gz > denial-shell-0.6.8-eb1-lockscreen.tar.gz.sha256
```

The bundle keeps the release's `.denial-ui-source.json` on the device: plugin
bundles built with the 0.6.8 kit keep loading.

## A complete `denial` package

```sh
tools/eb-repack-deb ~/work-denial-shell/out 0.6.8-1+eb1 ~/debs
```

It takes the signed `denial_0.6.8-1_arm64.deb`, replaces only the two shell
paths, and sets the version and maintainer. Every other file, the conffiles
(`/etc/denial/session.conf` stays as packaged) and the maintainer scripts are
the release's. It installs over 0.6.8-1 with the release's engine package.

Building `deniald`, the engine or Settings from source is a separate,
much larger job (`CROSS_BUILDING.md`, `tools/denial-flutter-engine`) and is
not needed for shell changes.

## Tests

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
`mobile_connectivity_marks_test`); `eb/lockscreen-keyboard` passes 193 with
the same 12 failing.

## Another Denial release

The pins in `tools/eb-build-shell` and `tools/eb-repack-deb` (kit and package
SHA-256, snapshot identity) belong to v0.6.8. For another release, take that
release's `denial-plugin-manager_*_arm64.deb` and `denial_*_arm64.deb`, check
them against its signed `SHA256SUMS`, read the snapshot identity of its
`libapp.so`, update the pins, and first rebuild the untouched release tag to
confirm a bit-identical result.
