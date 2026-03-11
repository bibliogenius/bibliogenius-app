# BiblioGenius App - Flutter

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/bibliogenius/bibliogenius-app/actions)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Platform](https://img.shields.io/badge/platform-iOS%20|%20Android%20|%20macOS%20|%20Windows%20|%20Linux-blue)](https://flutter.dev)

**Cross-platform mobile and desktop application for managing your personal library.**

The official frontend for BiblioGenius, built with Flutter. It embeds the Rust backend for high-performance offline capabilities.

## 🚀 Features

- **Universal App**: Works on phones, tablets, and desktops.
- **Offline First**: Manage your library without internet.
- **Scanner**: Barcode scanning for quick book entry.
- **Beautiful UI**: Modern, responsive design.

## 📋 Prerequisites

- **Flutter SDK**: Stable channel ([Install Guide](https://docs.flutter.dev/get-started/install))
- **Rust**: For compiling the backend (`rustup update stable`)
- **Xcode / Android Studio**: For mobile development

## ⚡ Quick Start

```bash
# Clone repository
git clone https://github.com/bibliogenius/bibliogenius-app.git
cd bibliogenius-app

# Get dependencies
flutter pub get

# Run on connected device or emulator
flutter run
```

> **Note**: The first build may take longer as it compiles the Rust backend.

## 🏗️ Architecture

- **Frontend**: Flutter (Dart)
- **Backend**: Rust (via [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge))
- **State Management**: Provider
- **Networking**: Dio (for external APIs) & Rust FFI (for local DB)

## 🛠️ Development Setup

### Code Generation

If you modify the Rust API or Dart models, run:

```bash
# Generate Freezed models & JSON serialization
flutter pub run build_runner build --delete-conflicting-outputs
```

### Platform Specifics

<details>
<summary>macOS / iOS</summary>

Ensure you have CocoaPods installed if deploying to iOS:

```bash
sudo gem install cocoapods
```

</details>

<details>
<summary>Linux</summary>

Install build dependencies:

```bash
sudo apt-get install clang cmake pkg-config libgtk-3-dev
```

</details>

## 🔗 Related Repositories

- [**bibliogenius**](https://github.com/bibliogenius/bibliogenius): The embedded Rust backend.
- [**bibliogenius-env**](https://github.com/bibliogenius/bibliogenius-env): Development environment orchestrator — clones repos, configures AI tools, and sets up Docker services via `make setup P=<profile>`.

## 📄 License

This project is licensed under the GNU Affero General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
