# مُذكِّر · Mudhkir

An Arabic-first medication reminder app for older adults and the family members who look after them. Mudhkir began as a 2024–25 graduation project and was rebuilt in 2026 as an **offline-first** Flutter app for **Android and iOS**.

- **Works without internet or an account.** Everything is stored on the phone in SQLite.
- **On-time reminders.** Reminders ring with a clear alarm and have **Taken / Snooze 10 min / Skip** buttons, which work even when the app is closed.
- **Optional free cloud account (Supabase).** It gives you a backup, sync between devices, and **companions**: a family member you approve can follow your doses and is alerted when you miss one.
- **Arabic RTL interface** with English as a second language, large touch targets, and the Tajawal font.

> To set up and run the app, see **[RUNNING.md](RUNNING.md)**.

## Features

| Area | What you can do |
|---|---|
| Medications | 3-step wizard: name (autocomplete from ~5,000 trade names), photo, dose and unit, daily (1–6 times, auto-spaced) or weekly schedule, start/end date, notes. Edit, stop, resume or delete. |
| Doses | Home shows the next dose and today's list. Mark a dose taken, skip it, reschedule it, or undo. The history shows an adherence %. |
| Calendar | Month or week view with coloured dots (all taken / planned / missed) and the doses for the selected day. |
| Reminders | Exact alarms with a custom sound. A rolling 7-day window is rescheduled whenever data changes. Reminders follow the device's time zone. |
| Account | Guest mode, sign up, sign in, password reset by emailed code, change email or password, delete account. |
| Companions | Invite someone by email. They accept the request, and you can then see their calendar, record doses for them, and add or edit their medications. You get an alert when they miss a dose. |
| Settings | Language (Arabic / English), notification permissions, test reminder, sync status, privacy note. |

## Architecture

```
lib/
  app/        App widget, go_router routes, theme, dependency wiring (provider)
  core/       config (env), notifications (reminders + action handler), time zone, utils
  data/
    local/        drift (SQLite) tables + generated code: the source of truth
    repositories/ medications, dose logs, profile, companions, settings, auth
    remote/       Supabase access (tables, storage, RPC) behind RemoteStore
    sync/         SyncService: push dirty rows, pull by checkpoint, newest edit wins
    services/     on-device photo store, medicine-name catalog
  domain/     plain models + DoseCalculator (pure, unit-tested schedule logic)
  services/   ReminderCoordinator, CompanionMonitor, background tasks (workmanager)
  features/   one folder per screen: view + ChangeNotifier view model
  l10n/       app_ar.arb (template), app_en.arb
supabase/     SQL migrations: schema, row-level security, triggers, storage
test/         unit, repository, sync (fake server) and widget tests
```

**How a change flows.** The UI calls a repository, which writes to SQLite and marks the row `dirty`. Drift streams update every screen at once, and the `ReminderCoordinator` reschedules notifications. When the user is signed in and online, `SyncService` uploads dirty rows and pulls changes from other devices and from caregivers. If the same row was edited in both places, the newer `updated_at` wins; the server enforces this with a trigger.

**Security.** Supabase row-level security lets each user see only their own rows. A caregiver sees a patient's medications and dose logs only after the patient accepts the link, and only the patient can accept it. Photos are kept in a private bucket under `{owner}/…`.

## Development

```bash
fvm install && fvm use           # Flutter 3.47.6 (see .fvmrc)
flutter pub get
flutter analyze && flutter test
dart run build_runner build      # only after changing lib/data/local/tables.dart
```

## History

The 2024–25 version used Firebase Auth/Firestore, ImgBB for photos, and Android-only background checks. The 2026 rewrite replaced those with an on-device database and optional Supabase sync. It also fixed a crash on first launch, removed API keys that had been committed to the repo, and added iOS support.
