import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'signup_screen.dart';

// Use the stable pre-Credential-Manager Google Sign-In flow on Android.
// The web OAuth client is the backend client used to mint the Firebase ID token.
const String _googleWebClientId =
    '809938504753-n2rffk1q9kqqillqlh9elk1edk7meu7f.apps.googleusercontent.com';

final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: const <String>['email'],
  serverClientId: _googleWebClientId,
);

class LoginScreen extends StatefulWidget {
  final VoidCallback? onSignedIn;

  const LoginScreen({super.key, this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _hidePassword = true;
  bool _isLoading = false;
  bool _isResettingPassword = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signIn() async {
    final String email = _emailController.text.trim();
    // Never trim passwords. Leading/trailing spaces can be part of a valid
    // password and trimming them produces a misleading "incorrect" result.
    final String password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter email and password.');
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      _showMessage('Please enter a valid email address.');
      return;
    }

    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final UserCredential credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;
      await credential.user?.getIdToken();
      widget.onSignedIn?.call();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      String message = 'Unable to sign in. Please try again.';

      if (error.code == 'invalid-email') {
        message = 'Please enter a valid email address.';
      } else if (error.code == 'invalid-credential' ||
          error.code == 'wrong-password' ||
          error.code == 'user-not-found') {
        message = 'Email or password is incorrect.';
      } else if (error.code == 'user-disabled') {
        message = 'This account has been disabled.';
      } else if (error.code == 'network-request-failed') {
        message = 'Please check your internet connection.';
      } else if (error.code == 'operation-not-allowed') {
        message = 'Email login is not enabled in Firebase.';
      }

      _showMessage(message);
    } catch (error, stackTrace) {
      developer.log(
        'Email sign-in failed: $error',
        name: 'KEEPER_AUTH',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;

      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      // A null account means that the user closed the account chooser.
      if (googleUser == null) {
        _showMessage('Google Sign-In was cancelled.');
        return;
      }

      final GoogleSignInAuthentication googleAuthentication =
          await googleUser.authentication;

      if (googleAuthentication.idToken == null) {
        _showMessage('Google did not return a valid sign-in token.');
        return;
      }

      final OAuthCredential firebaseCredential = GoogleAuthProvider.credential(
        idToken: googleAuthentication.idToken,
      );

      final UserCredential credential = await FirebaseAuth.instance
          .signInWithCredential(firebaseCredential);

      if (!mounted) return;
      await credential.user?.getIdToken();
      widget.onSignedIn?.call();
    } on PlatformException catch (error) {
      developer.log(
        'Google PlatformException: code=${error.code}, '
        'message=${error.message}, details=${error.details}',
        name: 'KEEPER_GOOGLE_AUTH',
        error: error,
      );

      if (!mounted) return;

      if (error.code == 'sign_in_canceled') {
        _showMessage('Google Sign-In was cancelled.');
      } else if (error.code == 'network_error') {
        _showMessage('Please check your internet connection.');
      } else if (error.code == 'sign_in_failed') {
        _showMessage(
          'Google Sign-In configuration could not be verified. '
          'This is not an email-account problem.',
        );
      } else {
        _showMessage('Google Sign-In failed. Error: ${error.code}.');
      }
    } on FirebaseAuthException catch (error) {
      developer.log(
        'Google FirebaseAuthException: code=${error.code}, '
        'message=${error.message}',
        name: 'KEEPER_GOOGLE_AUTH',
        error: error,
      );

      if (!mounted) return;

      String message = 'Firebase Google login failed.';

      if (error.code == 'account-exists-with-different-credential') {
        message =
            'This email already uses password sign-in. Sign in with your '
            'password first, then connect Google from your profile.';
      } else if (error.code == 'invalid-credential') {
        message = 'Google login credential is invalid.';
      } else if (error.code == 'operation-not-allowed') {
        message = 'Google login is not enabled in Firebase.';
      } else if (error.code == 'network-request-failed') {
        message = 'Please check your internet connection.';
      } else if (error.message != null) {
        message = error.message!;
      }

      _showMessage(message);
    } catch (error, stackTrace) {
      developer.log(
        'Unexpected Google sign-in failure: $error',
        name: 'KEEPER_GOOGLE_AUTH',
        error: error,
        stackTrace: stackTrace,
      );

      if (!mounted) return;

      _showMessage('Google Sign-In could not be completed. Please retry once.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    final TextEditingController resetEmailController = TextEditingController(
      text: _emailController.text.trim(),
    );

    final String? enteredEmail = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121725),
          title: const Text('Reset password'),
          content: TextField(
            controller: resetEmailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Registered email address',
            ),
            onSubmitted: (value) {
              Navigator.of(dialogContext).pop(value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  resetEmailController.text.trim(),
                );
              },
              child: const Text('Send link'),
            ),
          ],
        );
      },
    );

    resetEmailController.dispose();

    if (enteredEmail == null) return;

    final String email = enteredEmail.trim();

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _showMessage('Please enter a valid registered email address.');
      return;
    }

    setState(() {
      _isResettingPassword = true;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      _showMessage(
        'If a password account exists for this email, a reset link has been sent.',
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      if (error.code == 'user-not-found') {
        _showMessage('No account found with this email.');
      } else if (error.code == 'network-request-failed') {
        _showMessage('Please check your internet connection.');
      } else {
        _showMessage('Unable to send password reset email.');
      }
    } catch (error, stackTrace) {
      developer.log(
        'Password reset failed: $error',
        name: 'KEEPER_AUTH',
        error: error,
        stackTrace: stackTrace,
      );
      _showMessage('Unable to send password reset email. Please retry.');
    } finally {
      if (mounted) {
        setState(() {
          _isResettingPassword = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),

              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF766DFF), Color(0xFF5147E5)],
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x55766DFF), blurRadius: 25),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'K',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 38),

              const Text(
                'Welcome back',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                'Unlock your knowledge. Anywhere. Anytime.',
                style: TextStyle(
                  color: Color(0xFFAAA8B8),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 34),

              _buildLabel('Email address'),

              const SizedBox(height: 10),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  hint: 'user123@example.com',
                  icon: Icons.mail_outline_rounded,
                ),
              ),

              const SizedBox(height: 22),

              _buildLabel('Password'),

              const SizedBox(height: 10),

              TextField(
                controller: _passwordController,
                obscureText: _hidePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isLoading) {
                    _signIn();
                  }
                },
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  hint: 'Enter your password',
                  icon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _hidePassword = !_hidePassword;
                      });
                    },
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF8E8C9C),
                    ),
                  ),
                ),
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: (_isLoading || _isResettingPassword)
                      ? null
                      : _forgotPassword,
                  child: Text(
                    _isResettingPassword
                        ? 'Sending reset link...'
                        : 'Forgot password?',
                    style: const TextStyle(
                      color: Color(0xFF938CFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF766DFF),
                    disabledBackgroundColor: const Color(0xFF514B8A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 23,
                          height: 23,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              const Row(
                children: [
                  Expanded(child: Divider(color: Color(0xFF292D3B))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'or continue with',
                      style: TextStyle(color: Color(0xFF777A89), fontSize: 13),
                    ),
                  ),
                  Expanded(child: Divider(color: Color(0xFF292D3B))),
                ],
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: const Text(
                    'G',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  label: const Text(
                    'Continue with Google',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2B3040)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Color(0xFFAAA8B8)),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SignUpScreen(),
                        ),
                      ).then((created) {
                        if (created == true && mounted) {
                          widget.onSignedIn?.call();
                        }
                      });
                    },
                    child: const Text(
                      'Create account',
                      style: TextStyle(
                        color: Color(0xFF938CFF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF666A78)),
      prefixIcon: Icon(icon, color: const Color(0xFF8E8C9C)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF121725),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF242938)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF766DFF), width: 1.4),
      ),
    );
  }
}
