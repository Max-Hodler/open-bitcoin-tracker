# Contributing to Open Bitcoin Tracker

Thanks for your interest in contributing. This document covers local setup, the development workflow, project structure, and a few non-obvious gotchas.

## Requirements

- **Android 7.0 or higher** (API 24+) for the target device or emulator
- **Dart 3.11.5 or higher**
- **Flutter 3.41.7 or higher**
- **Android SDK** (path configured in `android/local.properties`)

The build uses Flutter's default `minSdk`, `compileSdk`, and `targetSdk` — no pinned overrides in `android/app/build.gradle.kts`.

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Configure local development

Create `android/local.properties` and set:

```properties
sdk.dir=/path/to/android-sdk
flutter.sdk=/path/to/flutter
```

### 3. Verify Android emulator

```bash
flutter devices
```

You should see a running Android emulator (e.g. `emulator-5554`) in the list.

## Development

### Run on emulator

```bash
flutter run -d emulator-5554
```

### Hot reload / restart

In the terminal running `flutter run`, press:

- `r` — Hot reload (preserves state)
- `R` — Hot restart (resets state)
- `q` — Quit

### Static analysis

```bash
flutter analyze
```

### Tests

```bash
flutter test
```

## Build

### Debug APK

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### Release APK (ARM-only)

```bash
flutter build apk --release --target-platform android-arm,android-arm64
```

Targets ARM devices only. The resulting APK is what gets uploaded to GitHub Releases.

### Release AAB (Play Store, ARM-only)

```bash
flutter build appbundle --release --target-platform android-arm,android-arm64
```

The AAB must be ARM-only — building without `--target-platform` includes an x86_64 split that the Play Store rejects (intended for emulators / Chromebooks).

## Architecture

### Data layer

- **`lib/data/`** — State management, persistence, and encryption
  - `AppStateRepository` — Encrypted stack storage + settings cache
  - `BtcHistoryCache` — Local chart data (bundled + Kraken REST history)
  - `BtcRatesCache` — Live BTC prices (Kraken WS ticker)

### API layer

- **`lib/api/`** — External integrations
  - `KrakenStreamService` — Kraken WebSocket v2 real-time price feed
  - `KrakenOhlcClient` — Kraken REST OHLC chart history endpoint
  - `LivePriceController` — Reactive wrapper over the Kraken stream

### State management

- **`lib/state/`** — `ChangeNotifier`-based reactive state
  - `AppStateNotifier` — Root notifier for all app state
  - `StacksLockController` — Authentication + DEK management

### UI layer

- **`lib/screens/`** — Main screens and layouts
- **`lib/widgets/`** — Reusable components
- **`lib/theme/`** — Material Design 3 tokens and colors

### Security

- **Encryption at rest** — Stacks are encrypted under a Data Encryption Key (DEK)
- **PIN-derived KEK** — PIN hashed via PBKDF2 + AES-256-GCM wraps the DEK
- **Biometric binding** — Device biometric (fingerprint/face) gates DEK access via Keystore
- **Secure storage** — DEK cached only in memory; encryption metadata in `SharedPreferences`

## Project structure

```
.
├── android/           # Android native scaffolding (Kotlin, AndroidManifest.xml)
├── assets/            # Bundled data (Bitcoin history CSV, fonts, launcher icons)
├── lib/
│   ├── api/           # API clients (Kraken WS/REST)
│   ├── data/          # State, persistence, encryption
│   ├── format/        # Display formatters (fiat, etc.)
│   ├── l10n/          # Localization (10 languages — see Localization section)
│   ├── screens/       # Main UI screens
│   ├── services/      # Authentication, crypto, haptics
│   ├── state/         # State notifiers and controllers
│   ├── theme/         # Design tokens (colors, typography, spacing)
│   ├── widgets/       # Reusable UI components
│   └── main.dart      # App entry point
├── test/              # Unit and widget tests (mirrors lib/ layout)
└── pubspec.yaml       # Dart dependencies
```

## Dependencies

Key packages:

- **`provider`** — State management
- **`fl_chart`** — Chart rendering
- **`local_auth`** — Biometric authentication
- **`biometric_storage`** — Keystore-backed encryption
- **`flutter_secure_storage`** — Secure key/value storage
- **`cryptography`** — AES-GCM + PBKDF2 crypto primitives
- **`web_socket_channel`** — Kraken WS connection
- **`http`** — REST calls (Kraken OHLC)
- **`shared_preferences`** — Persistent settings
- **`path_provider`** — Filesystem paths for cached data
- **`url_launcher`** — Opening external links
- **`intl`** — Number / currency formatting

See `pubspec.yaml` for the full list and versions.

## Localization

User-facing strings live in `lib/l10n/`:

- `app_de.arb` — German
- `app_en.arb` — English
- `app_es.arb` — Spanish
- `app_fr.arb` — French
- `app_it.arb` — Italian
- `app_ja.arb` — Japanese
- `app_pt.arb` — Portuguese
- `app_ru.arb` — Russian
- `app_tr.arb` — Turkish
- `app_vi.arb` — Vietnamese

When adding or removing strings, update **every** `.arb` file. Generated Dart sources land in `lib/l10n/generated/` and are refreshed automatically by `flutter pub get` (or `flutter run`); to regenerate explicitly:

```bash
flutter gen-l10n
```

Don't leave orphaned keys behind when removing user-facing text.

## Gotchas

### Internet permission

`AndroidManifest.xml` must include:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Without it, the Kraken WebSocket silently fails and the price card freezes on cached data — there is no error UI on this path.

### Device-unlock mode on emulators

Device-unlock mode requires an **enrolled biometric**. On an emulator without one:

1. Open **Extended Controls** → **Fingerprint**
2. Tap "Touch the sensor"

Device-credential fallback (PIN/pattern) is intentionally disabled — see the Security section above.

### Chart fallback

The bundled `assets/btc_history.csv` is the offline fallback for chart ranges when the Kraken OHLC endpoint is unreachable. This is what keeps the "All" view working with no network.

## Issues and pull requests

- File bugs and feature requests at <https://github.com/Max-Hodler/open-bitcoin-tracker/issues>.
- Search existing issues before opening a new one.
- For non-trivial changes, open an issue first to discuss the approach.

Before opening a PR, please make sure:

- `flutter analyze` passes with no errors
- `flutter test` passes
- Changes follow the project's existing code style and patterns
- New user-facing strings are added to **every** `.arb` file in `lib/l10n/`

## License

By contributing, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
