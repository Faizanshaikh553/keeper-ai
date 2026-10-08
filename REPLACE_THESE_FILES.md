# Keeper AI organization update

Copy this bundle over the root of the existing Keeper Flutter project. The
folders already match the final project paths.

## Existing files to replace

- `pubspec.yaml`
- `android/app/build.gradle.kts`
- `lib/main.dart`
- `lib/models/organization_chat_message_model.dart`
- `lib/services/organization_chat_service.dart`
- `lib/screens/create_organization_screen.dart`
- `lib/screens/dashboard_screen.dart`
- `lib/screens/documents_screen.dart`
- `lib/screens/organization_group_chat_screen.dart`
- `lib/screens/organization_members_screen.dart`
- `lib/screens/upload_screen.dart`

## New files to add

- `lib/services/organization_billing_service.dart`
- `lib/services/organization_subscription_service.dart`
- `lib/screens/organization_details_screen.dart`
- `lib/screens/organization_subscription_screen.dart`

## Firestore rules

`firestore.rules` is a production-oriented replacement draft. Do not publish
it until every Firestore collection used by the complete app has been checked
against it. The old temporary catch-all rule expires on 18 August 2026 and must
not be used for production.

## Required local checks

```powershell
flutter clean
flutter pub get
dart format lib
flutter analyze
flutter run
```

## Google Play subscription setup

The Android client uses subscription product ID:

`keeper_organization_monthly_499`

Purchases remain disabled by default. This prevents a user from being charged
before secure verification is deployed. After the Google Play subscription
and trusted backend verifier are ready, create Firestore document
`app_config/billing` with:

```text
organizationSubscriptionsEnabled: true
```

The backend must verify each document created under
`subscription_verification_requests`, update the request to `verified` or
`rejected`, and grant the organization entitlement by setting trusted
subscription fields. Never enable the flag before that backend is live.
