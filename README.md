# BiblioGenius App - Flutter

> **Canonical repository: [Codeberg](https://codeberg.org/bibliogenius/bibliogenius-app).** The GitHub copy is a read-only mirror, automatically synced from Codeberg. Please open issues and pull requests on Codeberg.

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/bibliogenius/bibliogenius-app/actions)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Platform](https://img.shields.io/badge/platform-iOS%20|%20Android%20|%20macOS%20|%20Windows%20|%20Linux-blue)](https://flutter.dev)

**Cross-platform mobile and desktop application for managing and sharing your personal library.**

The official frontend for BiblioGenius, built with Flutter. It embeds the Rust backend for high-performance offline capabilities, and lets you share your catalog and lend books across all your devices — whether they are on the same Wi-Fi or on the other side of the world.

## 🚀 Features

- **Universal App**: iOS, Android, macOS, Windows, and Linux from a single codebase.
- **Offline First**: Your library lives on-device; every feature works without internet.
- **Scanner**: Barcode scanning for quick book entry, with metadata fetched from open bibliographic sources.
- **Catalog management**: Books, authors, series, loans, reading status, covers, and personal notes.
- **Multi-device sync**:
  - **Local network (Wi-Fi / LAN)**: Zero-config peer discovery via mDNS — your devices find each other automatically when connected to the same network.
  - **Off-network (cellular, different Wi-Fi, travel)**: End-to-end encrypted relay through a BiblioGenius hub, so your devices stay in sync and your peers stay reachable even when you are not on the same LAN. The hub only sees ciphertext.
- **Peer-to-peer lending**: Browse a friend's catalog, request loans, and track returns — over LAN or over the hub relay.
- **Real-time notifications**: WebSocket-based push for loan requests, status changes, and catalog updates from your peers.
- **E2EE by design**: Forward-secret messaging between devices and peers (ephemeral DH per message, HKDF-derived keys, replay protection).
- **Beautiful UI**: Modern, responsive, fully accessible design (RGAA 4.1 / WCAG 2.1 AA).

## 📋 Prerequisites

- **Flutter SDK**: Stable channel ([Install Guide](https://docs.flutter.dev/get-started/install))
- **Rust**: For compiling the backend (`rustup update stable`)
- **Xcode / Android Studio**: For mobile development

## ⚡ Quick Start

```bash
# Clone repository (--recursive fetches the Rust backend)
git clone --recursive https://github.com/bibliogenius/bibliogenius-app.git
cd bibliogenius-app

# If you already cloned without --recursive:
git submodule update --init

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
