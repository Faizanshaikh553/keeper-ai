# Keeper Tools v2 — safe APK test patch

This patch changes only the isolated Keeper Tools modules and dashboard access.
Existing Firebase authentication, App Check, Keeper AI chat, document upload,
document reading, Personal/Organization, history, vault and signing settings are
not refactored. The version remains `1.0.10+1001` for local debug-APK testing.

## What changed

- **Navigation:** Keeper Tools moved from the dashboard cards to its own compact
  bottom-navigation item. Personal Vault and Upload remain the two large quick
  actions; the remaining actions use a smaller horizontal scroll row.
- **Keeper Lens:** the slow duplicate OCR/search UI was removed. The Lens tab now
  launches the real Google Lens app, where camera, gallery, search, translation
  and text copy are handled properly.
- **Keeper Live:** replaced the in-app placeholder with Android MediaProjection
  and a floating Keeper control that works above websites and other apps.
  Capture happens only after the user taps **Read screen**. Keeper analyses the
  captured screen and shows the answer in the floating panel.
- **Reminders:** faster date presets, clearer alarm/reminder labels, optional-note
  visibility and improved responsive layout. Notifications still avoid a Play
  Console exact-alarm declaration.

## Apply on Windows

1. Back up `D:\KEEPER\project\keeper`.
2. Copy the supplied patch folders over the project root and replace matching
   files only.
3. Do not replace `google-services.json`, `key.properties`, signing keys,
   `local.properties` or personal assets.
4. Run:

```powershell
cd D:\KEEPER\project\keeper
flutter clean
flutter pub get
flutter analyze
flutter build apk --debug
```

Install the local test APK:

```powershell
$adb="$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r ".\build\app\outputs\flutter-apk\app-debug.apk"
```

If Android reports a signature mismatch, do not uninstall immediately if local
files matter. Back them up first; uninstalling removes that phone's local app
data. Never upload `app-debug.apk` to Play Console.

## Test checklist

### Dashboard

1. Confirm the old Keeper Tools cards are gone from Home.
2. Confirm bottom navigation has **Tools** and all six items fit without pixel
   overflow.
3. Confirm Personal Vault and Upload work unchanged.
4. Horizontally scroll Create Organization, Join Organization, Knowledge,
   Documents, Memory and Group Chat.

### Google Lens

1. Open **Tools → Lens → Open Google Lens**.
2. Confirm the Google Lens camera/gallery screen opens directly.
3. Test Search, Translate and Copy text inside Google Lens.

### Keeper Live

1. Open **Tools → Live → Start Live over other apps**.
2. Allow **Display over other apps** and Android screen-sharing permission.
3. Open Chrome or another ordinary app.
4. Tap floating **K**, optionally type a question, then tap **Read screen**.
5. Confirm the floating panel shows Keeper's answer without opening Lens.
6. Drag the K bubble, test Copy answer, Hide, Open Keeper and Stop.

Banking, password-manager, DRM-video and other protected screens may return a
black image because Android/the other app blocks capture. Keeper does not bypass
those protections.

### Reminder

1. Create a reminder 3–5 minutes ahead and allow notification permission.
2. Test quick presets: 10 minutes, 1 hour and tomorrow 9 AM.
3. Close Keeper, lock the phone and confirm the notification appears.

## Debug App Check note

The debug APK uses Firebase's debug App Check provider. If Keeper AI says the
request was rejected by Firebase, register that phone's debug token in Firebase
App Check. The Play release continues to use Play Integrity and is not changed
by the debug-token setup.
