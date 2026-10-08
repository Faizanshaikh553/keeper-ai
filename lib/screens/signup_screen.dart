import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createAccount() async {
    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    final String confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showMessage("Please fill all fields.");
      return;
    }

    if (!email.contains('@')) {
      _showMessage("Please enter a valid email.");
      return;
    }

    if (password.length < 6) {
      _showMessage("Password must be at least 6 characters.");
      return;
    }

    if (password != confirmPassword) {
      _showMessage("Passwords do not match.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final UserCredential credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? createdUser = credential.user;

      if (createdUser != null && name.isNotEmpty) {
        await createdUser.updateDisplayName(name);
        await createdUser.reload();
      }

      if (!mounted) return;

      // Tell LoginScreen/AuthGate explicitly that authentication completed.
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      if (e.code == "email-already-in-use") {
        _showMessage(
          "This email is already registered. Sign in or use Forgot password.",
        );
      } else if (e.code == 'invalid-email') {
        _showMessage('Please enter a valid email address.');
      } else if (e.code == 'weak-password') {
        _showMessage('Please choose a stronger password.');
      } else if (e.code == 'network-request-failed') {
        _showMessage('Please check your internet connection.');
      } else {
        _showMessage(e.message ?? "Something went wrong.");
      }
    } catch (e) {
      _showMessage("Failed to create account.");
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildTextField({
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF121725),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        title: const Text("Create Account"),
        backgroundColor: const Color(0xFF090D18),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildTextField(hint: "Full Name", controller: _nameController),

            const SizedBox(height: 15),

            _buildTextField(
              hint: "Email Address",
              controller: _emailController,
            ),

            const SizedBox(height: 15),

            _buildTextField(
              hint: "Password",
              controller: _passwordController,
              obscureText: _hidePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _hidePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _hidePassword = !_hidePassword;
                  });
                },
              ),
            ),

            const SizedBox(height: 15),

            _buildTextField(
              hint: "Confirm Password",
              controller: _confirmPasswordController,
              obscureText: _hideConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _hideConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _hideConfirmPassword = !_hideConfirmPassword;
                  });
                },
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createAccount,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text("Create Account"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
