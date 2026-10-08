# Keeper AI — final Google Sign-In diagnostic fix

This pack uses app version `1.0.9` and Play version code `100`.

## 1. Replace these exact files

Copy the files from this pack into the Keeper project and overwrite the old files:

- `pubspec.yaml`
- `lib/screens/login_screen.dart`
- `android/app/google-services.json`
- `android/app/build.gradle.kts`

Do not keep names such as `login_screen(4).dart` or `google-services(4).json` in the project. The destination names must match the paths above exactly.

## 2. Required OAuth console check

Play Console testers and Google OAuth test users are separate lists.

Open Google Cloud Console using project `keeper-ai-4edcd` / project number `809938504753`, then open:

`Google Auth Platform > Audience`

- If Publishing status is **Testing**, add every Gmail account that will test Google Sign-In under **Test users**, then save.
- Alternatively, publish the OAuth app to **Production** after its Branding page is complete.

On `Google Auth Platform > Branding`, confirm:

- App name: `Keeper AI`
- User support email: `sfaijan57@gmail.com`
- Developer contact email: `sfaijan57@gmail.com`

In Firebase Console, confirm `Authentication > Sign-in method > Google` is enabled, then save it with:

- Public-facing name: `Keeper AI`
- Support email: `sfaijan57@gmail.com`

The supplied Firebase file already contains the correct package, Play signing SHA client, and web client. Do not create another Firebase Android app and do not delete existing SHA fingerprints.

## 3. Verify replacements and build

Run from `D:\KEEPER\project\keeper` in PowerShell:

```powershell
Select-String .\lib\screens\login_screen.dart -SimpleMatch "KGS-100"
Select-String .\pubspec.yaml -Pattern "^version:"
flutter clean
flutter pub get
flutter analyze
flutter build appbundle --release --build-name=1.0.9 --build-number=100
Copy-Item .\build\app\outputs\bundle\release\app-release.aab .\KeeperAI-1.0.9-code100.aab -Force
```

The first command must find `KGS-100`; the second must show `version: 1.0.9+100`; and analyze must show no issues.

## 4. Upload and test

Upload only `KeeperAI-1.0.9-code100.aab` to the closed testing release. Wait until Play Store shows version `1.0.9`, uninstall the old app, install from the tester Play link, and try Google Sign-In.

This build no longer forces `GoogleSignIn.signOut()` before opening the account chooser. If login still fails, the on-screen message contains marker `KGS-100` and the real native error (especially code 10 or 16), so the remaining console-side cause is identifiable without another blind rebuild.
