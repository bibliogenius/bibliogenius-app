fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload

```sh
[bundle exec] fastlane ios upload
```

Build iOS IPA and upload to TestFlight

----


## Mac

### mac upload

```sh
[bundle exec] fastlane mac upload
```

Build macOS .app, sign inside-out, package PKG and upload to TestFlight.

Pass skip_rust:true to reuse already-built Rust backend binaries.

----


## Android

### android upload

```sh
[bundle exec] fastlane android upload
```

Build Android AAB and upload to Play Console internal track (draft).

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
