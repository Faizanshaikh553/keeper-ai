# Keeper AI — Play Store readiness handoff

Package ID: `com.faizan.keeperai`

Organization subscriptions are intentionally disabled for this release. Personal and organization uploads remain free until billing is enabled in a later version.

## 1. Mandatory Firebase package migration

The old `android/app/google-services.json` belongs to `com.example.keeper` and must not be used for the new release.

1. Open Firebase Console → project `keeper-ai-4edcd` → Project settings.
2. Add an Android app with package name `com.faizan.keeperai`.
3. Add the upload/release SHA-1 and SHA-256 fingerprints.
4. Download the new `google-services.json` and replace `android/app/google-services.json`.
5. From the project root run:

   ```powershell
   dart pub global activate flutterfire_cli
   flutterfire configure --project=keeper-ai-4edcd --platforms=android --android-package-name=com.faizan.keeperai
   ```

6. In Firebase Authentication, verify Google sign-in is enabled.
7. In Firebase App Check, register the new Android app with Play Integrity and its SHA-256. Do not enforce App Check until a Play-distributed closed-test build has passed login, upload and AI tests.

## 2. Replace Firestore testing rules

Review and publish `firestore.rules` in Firebase Console. The temporary date-based catch-all rule must not return.

The supplied rules add access for Keeper memories, organization chat, AI/content reports, feedback and account-deletion requests. Test create/join organization, member management, chat, memory and deletion requests before production.

Important architecture note: the current client-side invitation-code join design is suitable only for trusted closed testing. Before public launch, move invitation redemption to a trusted backend/Cloud Function so invite codes and membership changes cannot be abused by a modified client.

## 3. Supabase

Run `supabase_indexes.sql` once in the Supabase SQL editor.

The current app uses Firebase Authentication but a public Supabase storage path. Indexes improve speed; they do not make files private. Before a public production launch, protect document metadata and storage with a trusted backend that verifies Firebase identity, signed URLs and strict Supabase RLS/storage policies.

## 4. Public legal pages

The public support email is `sfaijan57@gmail.com`. Deploy the supplied legal site:

```powershell
firebase login
firebase use keeper-ai-4edcd
firebase deploy --only hosting
```

Expected URLs:

- `https://keeper-ai-4edcd.web.app/privacy`
- `https://keeper-ai-4edcd.web.app/terms`
- `https://keeper-ai-4edcd.web.app/account-deletion`

Add the privacy URL and account-deletion URL in Play Console. Deletion requests written to `account_deletion_requests` still require an owner/admin process that actually deletes Firebase, Supabase and authentication data within the stated period.

## 5. Generate assets and verify

After replacing Firebase config:

```powershell
flutter clean
flutter pub get
dart format lib
flutter pub run flutter_launcher_icons
flutter analyze
flutter test
flutter run
```

Do not regenerate the native splash for this build. The supplied Android 12 theme intentionally uses a transparent native icon, so the clean Keeper AI Flutter splash is the first branded screen.

`flutter analyze` must finish with 0 issues. Test on a physical Android phone:

- email and Google login/logout/session persistence
- create and join organization
- personal and organization upload
- PDF/image/TXT extraction and OCR
- search, AI answers and sources
- AI answer Report button
- memory remember/forget/list
- organization members, roles, rename/delete and group chat
- owner gold chat badge and member message Report button
- account-deletion request
- privacy/terms links

## 6. Build and closed test

Confirm `android/key.properties` points to the upload keystore, then run:

```powershell
flutter build appbundle --release
```

Upload `build/app/outputs/bundle/release/app-release.aab` to Internal testing first, then Closed testing. Complete Play Console identity/contact verification, app content, Data safety, content rating, store listing, privacy/deletion URLs and the required personal-account testing period before production access.

Never upload `.jks`, `.keystore`, `key.properties`, `.env` or private server keys to chat or source control.
