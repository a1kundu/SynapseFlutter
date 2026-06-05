# Office Aschi

A cross-platform Flutter application for managing team office seat bookings with TOTP-based authentication.

## Features

- **Seat Booking** — Browse available seats by date, book for team members, manage waitlists
- **Team Management** — Create teams, add/remove seats, invite and manage members
- **Role-based Access** — Managers (team owners) and Reportees (members) with distinct permissions
- **TOTP Authentication** — Two-factor authentication using 6-digit one-time passwords for sensitive operations, compatible with Google Authenticator and Microsoft Authenticator
- **Real-time Health Monitoring** — Reactive backend health checks with connectivity detection and a global status banner
- **Auto-updates** — Automatic update checks via GitHub Releases with resilient download and resume (Android only)
- **Theming** — Material 3 with System/Light/Dark themes, persisted across sessions

## Screens

| Screen | Description |
|--------|-------------|
| **Team Search** | Search and browse teams, create new teams, pull-to-refresh |
| **Team Detail** | Two-tab view (Team Info & Bookings), calendar date navigation, seat booking, member & seat management |
| **Settings** | Theme switching, auto-update toggle, manual update check, about & GitHub links |

## Architecture

- **State Management** — `ValueNotifier` and `StreamController` for reactive state; `SharedPreferences` for persistence
- **API Layer** — Singleton `ApiService` with health polling (30s normal / 10s when degraded), lifecycle-aware
- **TOTP Service** — Local secret generation (Base32, SHA1, 30s window), QR code generation, clipboard auto-detection
- **Update Service** — Channel-aware (debug/release) build-number comparison, HTTP Range resume, exponential backoff retries
- **Background Updates** — `workmanager` for periodic checks every 6 hours with local notifications (Android)

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Android | Full | Auto-updates, background tasks, local notifications |
| Web | Full | QR download via browser blob, Material Design UI |
| iOS | Partial | Core features only, no auto-update |
| Desktop | Limited | Basic functionality |

## Tech Stack

| Category | Package |
|----------|---------|
| Networking | `http` |
| TOTP | `otp`, `base32` |
| QR Codes | `qr_flutter` |
| Persistence | `shared_preferences` |
| Notifications | `flutter_local_notifications` |
| Background Tasks | `workmanager` |
| File Handling | `open_filex` |
| URLs | `url_launcher` |
| i18n | `intl` |

## Getting Started

### Prerequisites

- Flutter SDK `>=3.10.0`
- Dart SDK `>=3.8.0-0`

### Run

```bash
flutter pub get
flutter run
```

### Build

```bash
# Android APK
flutter build apk

# Web
flutter build web
```

## API

Backend: `https://officeaschi.azurewebsites.net/api`

Authentication uses a custom header format:

```
Authorization: TOTP {entityType}:{entityId}:{code}
```

Where `entityType` is `manager` or `reportee`.

### Key Endpoints

- `GET /teams` — Search teams
- `GET /teams/{id}` — Team details
- `POST /teams` — Create team
- `GET /bookings/availability/{teamId}?date={date}` — Seat availability
- `POST /bookings` — Book a seat
- `POST /totp/verify` — Verify TOTP code
- `GET /health` — Health check

## License

See repository for license details.
