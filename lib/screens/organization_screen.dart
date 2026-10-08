import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dashboard_screen.dart';
import 'join_organization_screen.dart';
import 'create_organization_screen.dart';

class OrganizationScreen extends StatelessWidget {
  const OrganizationScreen({super.key});

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<void> _rememberChoice() async {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null || userId.isEmpty) return;

    await _storage.write(
      key: 'keeper_workspace_choice_seen_$userId',
      value: 'true',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 25),

              const Text(
                "Welcome to\nKeeper AI",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                "Choose how you want to use Keeper.",
                style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 15),
              ),

              const SizedBox(height: 40),

              GestureDetector(
                onTap: () async {
                  await _rememberChoice();
                  if (!context.mounted) return;

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const DashboardScreen()),
                  );
                },
                child: _buildCard(
                  icon: Icons.person,
                  title: "Personal Workspace",
                  subtitle:
                      "Use Keeper AI for your personal knowledge and documents.",
                ),
              ),
              const SizedBox(height: 20),

              GestureDetector(
                onTap: () async {
                  await _rememberChoice();
                  if (!context.mounted) return;

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const JoinOrganizationScreen(),
                    ),
                  );
                },
                child: _buildCard(
                  icon: Icons.groups,
                  title: "Join Organization",
                  subtitle: "Join your school, college, company or team.",
                ),
              ),

              const SizedBox(height: 20),

              GestureDetector(
                onTap: () async {
                  await _rememberChoice();
                  if (!context.mounted) return;

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateOrganizationScreen(),
                    ),
                  );
                },
                child: _buildCard(
                  icon: Icons.add_business,
                  title: "Create Organization",
                  subtitle: "Create your own AI powered workspace.",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B3040)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF766DFF), size: 35),

          const SizedBox(width: 18),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFAAAAAA),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
