import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/organization_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
  );

  await supabase.Supabase.initialize(
    url: 'https://jvkrmofiuwufdbaababq.supabase.co',
    publishableKey: 'sb_publishable_g5hsCJhz6BYIWy_DvR_fkA_v9bieSo5',
  );

  runApp(const KeeperApp());
}

class KeeperApp extends StatelessWidget {
  const KeeperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Keeper AI',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      setState(() {
        _showSplash = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return const SplashScreen();
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Firebase updates currentUser before every auth stream event. Reading it
        // as a fallback also makes the UI move immediately when a successful
        // sign-in callback rebuilds this gate before the stream event arrives.
        final User? user = snapshot.data ?? FirebaseAuth.instance.currentUser;

        if (snapshot.connectionState == ConnectionState.waiting &&
            user == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF090D18),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            ),
          );
        }

        if (user != null) {
          return FirstLoginWorkspaceGate(
            key: ValueKey<String>(user.uid),
            userId: user.uid,
          );
        }

        return LoginScreen(
          onSignedIn: () {
            if (mounted) {
              setState(() {});
            }
          },
        );
      },
    );
  }
}

class FirstLoginWorkspaceGate extends StatefulWidget {
  final String userId;

  const FirstLoginWorkspaceGate({super.key, required this.userId});

  @override
  State<FirstLoginWorkspaceGate> createState() =>
      _FirstLoginWorkspaceGateState();
}

class _FirstLoginWorkspaceGateState extends State<FirstLoginWorkspaceGate> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  bool _isLoading = true;
  bool _showWorkspaceChoice = false;

  String get _storageKey => 'keeper_workspace_choice_seen_${widget.userId}';

  @override
  void initState() {
    super.initState();
    _resolveStartScreen();
  }

  Future<void> _resolveStartScreen() async {
    final String? seen = await _storage.read(key: _storageKey);

    if (!mounted) return;

    if (seen == 'true') {
      setState(() {
        _showWorkspaceChoice = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _showWorkspaceChoice = true;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF090D18),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF766DFF)),
        ),
      );
    }

    if (_showWorkspaceChoice) {
      return const OrganizationScreen();
    }

    return const DashboardScreen();
  }
}
