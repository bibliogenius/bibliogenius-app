# BiblioGenius App - Flutter

Cross-platform mobile and desktop application for managing your library.

## Tech Stack

- **Framework**: Flutter/Dart
- **State Management**: Riverpod
- **Local Storage**: Hive
- **HTTP Client**: Dio

## Platforms

- Android
- iOS
- Windows
- macOS
- Linux
- Web (limited features)

## Features

- Connect to BiblioGenius Rust server
- Browse and search books
- Add/edit books
- Barcode scanning (ISBN lookup)
- Offline support with local cache
- Peer management UI
- Sync status and controls

## Getting Started

```bash
# Get dependencies
flutter pub get

# Run on desktop
flutter run -d macos

# Run on mobile
flutter run -d ios

# Build
flutter build apk
flutter build ios
flutter build macos
```

## 🗺️ Roadmap

| Version | Status | Focus |
|---------|--------|-------|
| **v1.0.0-beta** | ✅ Current | Personal library + LAN sync |
| v1.0.0 | Q1 2026 | Stable P2P on local network |
| v2.0.0 | Q2-Q3 2026 | Global P2P + Social Features |

## Repository

<https://github.com/bibliogenius/bibliogenius-app>
