import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'profile_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  bool _isLoggingOut = false;

  String _organizationName = 'No organization';
  String _organizationRole = 'Personal user';

  int _personalDocuments = 0;
  int _organizationDocuments = 0;
  int _totalDocuments = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadProfileData() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? organizationId;

      final DocumentSnapshot<Map<String, dynamic>> userDocument =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (userDocument.exists) {
        final Map<String, dynamic> userData = userDocument.data() ?? {};

        organizationId = userData['organizationId']?.toString();

        _organizationName =
            userData['organizationName']?.toString() ?? 'No organization';

        final String savedRole = userData['organizationRole']?.toString() ?? '';

        if (savedRole.isNotEmpty) {
          _organizationRole = _formatRole(savedRole);
        }
      }

      if (organizationId != null && organizationId.isNotEmpty) {
        final DocumentSnapshot<Map<String, dynamic>> organizationDocument =
            await FirebaseFirestore.instance
                .collection('organizations')
                .doc(organizationId)
                .get();

        if (organizationDocument.exists) {
          final Map<String, dynamic> organizationData =
              organizationDocument.data() ?? {};

          _organizationName =
              organizationData['name']?.toString() ?? _organizationName;
        }
      }

      final supabase.SupabaseClient client = supabase.Supabase.instance.client;

      final List<dynamic> personalResponse = await client
          .from('documents')
          .select('id')
          .eq('user_id', user.uid)
          .eq('space', 'personal');

      List<dynamic> organizationResponse = [];

      if (organizationId != null && organizationId.isNotEmpty) {
        organizationResponse = await client
            .from('documents')
            .select('id')
            .eq('organization_id', organizationId)
            .eq('space', 'organization');
      }

      if (!mounted) return;

      setState(() {
        _personalDocuments = personalResponse.length;
        _organizationDocuments = organizationResponse.length;

        _totalDocuments = _personalDocuments + _organizationDocuments;

        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to load complete profile information.');
    }
  }

  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Administrator';

      case 'member':
        return 'Organization Member';

      case 'student':
        return 'Student';

      default:
        return role;
    }
  }

  Future<void> _openEditProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProfileSettingsScreen()),
    );

    if (mounted) {
      await FirebaseAuth.instance.currentUser?.reload();
      await _loadProfileData();
      setState(() {});
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121725),
          title: const Text(
            'Logout?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Are you sure you want to logout from Keeper AI?',
            style: TextStyle(color: Color(0xFFB0B3C0), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Keep the root AuthGate alive. Replacing it with a standalone LoginScreen
      // makes a later successful login appear stuck until the app is restarted.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoggingOut = false;
      });

      _showMessage('Unable to logout. Please try again.');
    }
  }

  String _firstLetter(String name, String email) {
    if (name.trim().isNotEmpty && name != 'Keeper User') {
      return name.trim()[0].toUpperCase();
    }

    if (email.trim().isNotEmpty) {
      return email.trim()[0].toUpperCase();
    }

    return 'K';
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    final String displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'Keeper User';

    final String email = user?.email ?? 'No email available';

    final String? photoUrl = user?.photoURL;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF090D18),
          appBar: AppBar(
            backgroundColor: const Color(0xFF090D18),
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Profile',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                onPressed: _isLoading ? null : _loadProfileData,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF766DFF)),
                )
              : RefreshIndicator(
                  color: const Color(0xFF766DFF),
                  backgroundColor: const Color(0xFF121725),
                  onRefresh: _loadProfileData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 35),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF25205C), Color(0xFF151933)],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF393274)),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 92,
                                height: 92,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF766DFF),
                                  border: Border.all(
                                    color: const Color(0xFFAAA4FF),
                                    width: 2,
                                  ),
                                ),
                                child: photoUrl != null && photoUrl.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          photoUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Center(
                                                  child: Text(
                                                    _firstLetter(
                                                      displayName,
                                                      email,
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 38,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                );
                                              },
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          _firstLetter(displayName, email),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 38,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                displayName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                email,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFAAA8B8),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF181A3C),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF47417D),
                                  ),
                                ),
                                child: Text(
                                  _organizationRole,
                                  style: const TextStyle(
                                    color: Color(0xFFB9B4FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _openEditProfile,
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text(
                              'Edit Profile',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFAAA4FF),
                              side: const BorderSide(color: Color(0xFF5147E5)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Keeper stats',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                icon: Icons.description_outlined,
                                number: _totalDocuments.toString(),
                                label: 'Total',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                icon: Icons.person_outline_rounded,
                                number: _personalDocuments.toString(),
                                label: 'Personal',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                icon: Icons.apartment_rounded,
                                number: _organizationDocuments.toString(),
                                label: 'Organization',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Account information',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ProfileInformationTile(
                          icon: Icons.apartment_rounded,
                          title: 'Organization',
                          value: _organizationName,
                        ),
                        const SizedBox(height: 11),
                        _ProfileInformationTile(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Role',
                          value: _organizationRole,
                        ),
                        const SizedBox(height: 11),
                        _ProfileInformationTile(
                          icon: Icons.verified_user_outlined,
                          title: 'Authentication',
                          value:
                              user?.providerData.any(
                                    (provider) =>
                                        provider.providerId == 'google.com',
                                  ) ==
                                  true
                              ? 'Google Account'
                              : 'Email Account',
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _isLoggingOut ? null : _logout,
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB4232C),
                              disabledBackgroundColor: const Color(0xFF5A2429),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Keeper AI • Version 1.0.0',
                          style: TextStyle(
                            color: Color(0xFF666A78),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        if (_isLoggingOut)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF766DFF)),
                  SizedBox(height: 14),
                  Text(
                    'Logging out...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String number;
  final String label;

  const _StatCard({
    required this.icon,
    required this.number,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF292F42)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF938CFF), size: 25),
          const SizedBox(height: 10),
          Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8E91A3), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _ProfileInformationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _ProfileInformationTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF292F42)),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: const Color(0xFF24205A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFAAA4FF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF8E91A3),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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
