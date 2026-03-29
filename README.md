# worka

A new Flutter project.

## Getting Started

### Run with explicit Firebase environment

- Dev (default, requires non-prod firebase options):  
  `flutter run --dart-define=APP_ENV=dev`
- Prod (worka-416c0, only when you really need it):  
  `flutter run --dart-define=APP_ENV=prod`

If dev Firebase options are not configured yet, the app will fail fast with a
clear error rather than silently pointing to production.

To configure dev:
- Fill the dev block in `lib/firebase_options.dart` with your non-prod project values.
- Add matching dev `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.
- Set your dev project id in `.firebaserc` (replace `set-your-dev-project-id`).

### VS Code launch configs

- Dev: `.vscode/launch.json` → “Flutter Dev (APP_ENV=dev)”
- Prod: `.vscode/launch.json` → “Flutter Prod (APP_ENV=prod)”

### Firebase CLI safety

- .firebaserc now uses a placeholder default (`set-your-dev-project-id`) and a `prod` alias for `worka-416c0`. Set a real dev/stage project and keep prod explicit (`--project prod`).

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

Проект собирается на Flutter версии 3.38.7, поэтому используем MaterialState* и withOpacity, не WidgetState* и withValues.

## Firestore Indexes (responses)

Create these composite indexes for stable `responses` lists:

1. Collection: `responses`
   Fields:
   - `candidateOwnerId` Ascending
   - `type` Ascending
   - `createdAt` Descending

2. Collection: `responses`
   Fields:
   - `employerOwnerId` Ascending
   - `type` Ascending
   - `createdAt` Descending

3. Collection: `responses`
   Fields:
   - `jobId` Ascending
   - `candidateOwnerId` Ascending
   - `type` Ascending

To deploy indexes safely, use an explicit project flag:
`firebase deploy --only firestore:indexes --project prod`
or point to a non-prod project (`--project your-dev-alias`). Avoid running without `--project`.
