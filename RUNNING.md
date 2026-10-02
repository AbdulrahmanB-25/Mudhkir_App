# Running Mudhkir

> **On Windows with an Android phone?** Follow the short guide in **[docs/WINDOWS_SETUP.md](docs/WINDOWS_SETUP.md)**. A script installs everything for you.

## 1. Install the tools (once)

| Tool | Version | Notes |
|---|---|---|
| Flutter | **3.47.6** | Easiest with [FVM](https://fvm.app): `dart pub global activate fvm`, then `fvm install` in this folder. |
| Android Studio | latest | Install the Android SDK (API 36) and create an emulator, or plug in a phone with USB debugging on. |
| JDK | 17 or newer | The JDK bundled with Android Studio works. |
| Xcode + CocoaPods | Xcode 16+ (macOS only) | Needed only for iPhone / iOS Simulator. Run `sudo gem install cocoapods` or `brew install cocoapods`. |

Run `flutter doctor` and fix anything it marks in red.

## 2. Get the code and packages

```bash
git clone https://github.com/AbdulrahmanB-25/Mudhkir_App.git
cd Mudhkir_App
git checkout claude/keen-wright-nbm6cv   # until the PR is merged
fvm flutter pub get                       # or just `flutter pub get`
```

## 3. Choose how to run

### A. Normal run (cloud on)

```bash
flutter run
```

The app is already connected to the **mudhkir** Supabase project (`emvpjqtaylchpmaugipy`), because its URL and publishable key are built in (`lib/core/config/env.dart`). That key is meant to ship inside apps; row-level security protects the data. Any run button in Android Studio works, and you don't need `env.json`.

### B. Fully offline, or a different Supabase project

- Offline only (no sign-in, sync or companions): `flutter run --dart-define=SUPABASE_URL=`
- Another project: copy `env.example.json` to `env.json`, fill it in, and run `flutter run --dart-define-from-file=env.json`

### Picking a device

```bash
flutter devices                      # list emulators / phones / simulators
flutter run -d <device-id> --dart-define-from-file=env.json
```

- **Android emulator / phone**: works out of the box.
- **iOS Simulator**: `open -a Simulator`, then `flutter run`. The first run installs CocoaPods dependencies automatically.
- **Real iPhone**: open `ios/Runner.xcworkspace` in Xcode → Runner → Signing & Capabilities, and pick your Apple ID team. Then `flutter run`.
- **Release APK**: `flutter build apk --release --dart-define-from-file=env.json`. For the Play Store, set up a signing key and change `applicationId` from `com.example.mudhkir_app` first.

## 4. One-time Supabase dashboard steps

Open https://supabase.com/dashboard/project/emvpjqtaylchpmaugipy and do these:

1. **Enable account deletion.** Go to *SQL Editor*, paste the contents of `supabase/migrations/20261002150000_account_deletion.sql`, and run it. Until you do, "Delete account" in the app shows an error. The App Store requires this feature.
2. **Password reset by code.** Go to *Authentication → Emails → Reset password* and add the code to the template, for example:
   `<p>رمز إعادة التعيين / Your reset code: <b>{{ .Token }}</b></p>`
3. **For testing (optional).** In *Authentication → Sign In / Providers → Email*, turn off **Confirm email**. That lets you sign up and sign in straight away. Supabase's built-in email sender only sends a few emails per hour.

## 5. Things to know

- **Reminders on Android 12+.** Allow "Alarms & reminders" when the app asks; the Home screen shows a banner if it's off. Some brands (Xiaomi, Huawei, Samsung) also need battery optimisation turned off for Mudhkir.
- **iOS background checks.** On iOS the system decides when background refresh runs. Caregiver alerts are reliable when the app is opened, and only best-effort while it is closed.
- **Free Supabase plan.** A project pauses after **7 days without activity**. The app keeps working offline. Press **Restore** in the dashboard, and syncing continues.
- **Old secrets.** The old ImgBB key and Firebase keys are still in this repository's git history. Revoke the ImgBB key at imgbb.com, and delete the old `mudhkir-app` Firebase project if you no longer need it.

## 6. Checks

```bash
flutter analyze        # expected: No issues found
flutter test           # unit, repository, sync and widget tests
```

### Manual test checklist

- [ ] Airplane mode, guest: add a medicine with a photo. The reminder rings at the set time; Taken, Snooze and Skip all work from the notification. The data is still there after restarting the app.
- [ ] Sign up while online: the medicine appears in the Supabase *Table editor*.
- [ ] Second account invites the first by email → the first accepts it in *Companions* → the second sees the calendar. Missing a dose by more than 1 hour triggers an alert on the second phone when it opens the app.
- [ ] Sign out and sign in again: the data comes back from the cloud.
