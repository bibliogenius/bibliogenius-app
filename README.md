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

## Documentation

See [ARCHITECTURE.md](../docs/ARCHITECTURE.md) for ecosystem overview.

## Repository

https://github.com/bibliogenius/bibliogenius-app
