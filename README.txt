Keeper AI document loader emergency fix

What changed:
- Chatbot now uses .select() exactly like the working Documents screen.
- Removed explicit optional-column list that can fail when the Supabase schema
  does not contain one of those columns.
- Personal document loading is now independent from Organization loading.
- Personal timeout increased to 20 seconds.

Replace ONLY:
1. lib/screens/chatbot_screen.dart
2. pubspec.yaml

Then:
flutter clean
flutter pub get
flutter analyze
flutter build appbundle --release

Version: 1.0.13+1006
