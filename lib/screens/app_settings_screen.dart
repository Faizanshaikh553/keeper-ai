import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'organization_settings_screen.dart';
import 'profile_settings_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  static final Uri _privacyPolicyUrl = Uri.parse(
    'https://keeper-ai-4edcd.web.app/privacy',
  );
  static final Uri _termsUrl = Uri.parse(
    'https://keeper-ai-4edcd.web.app/terms',
  );
  bool _notificationsEnabled = true;
  bool _knowledgeSuggestionsEnabled = true;
  final bool _isLoading = false;
  bool _isRequestingDeletion = false;

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openLegalPage(Uri url) async {
    final bool opened = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open this page.')),
      );
    }
  }

  void _showInfoPage({required String title, required String content}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsInfoScreen(title: title, content: content),
      ),
    );
  }

  Future<void> _sendFeedback() async {
    final TextEditingController controller = TextEditingController();

    final String? feedback = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Send Feedback',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            maxLines: 5,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Tell us what should be improved...',
              hintStyle: const TextStyle(color: Color(0xFF777D8E)),
              filled: true,
              fillColor: const Color(0xFF101522),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.pop(dialogContext, value);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (feedback == null || !mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('app_feedback').add({
        'userId': user.uid,
        'email': user.email ?? '',
        'message': feedback,
        'status': 'new',
        'platform': 'android',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback sent. Thank you!')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send feedback. Try again.')),
      );
    }
  }

  Future<void> _confirmAccountDeletion() async {
    if (_isRequestingDeletion) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Request account deletion?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Keeper will permanently delete your account and associated personal '
            'data after reviewing this request. This cannot be undone. Requests '
            'are processed within 30 days.',
            style: TextStyle(color: Color(0xFFB8BBC7), height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Request deletion',
                style: TextStyle(color: Color(0xFFFF7D92)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isRequestingDeletion = true);

    try {
      await FirebaseFirestore.instance
          .collection('account_deletion_requests')
          .doc(user.uid)
          .set({
            'userId': user.uid,
            'email': user.email ?? '',
            'status': 'pending',
            'source': 'android_app',
            'requestedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRequestingDeletion = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to submit the deletion request. Please try again.',
          ),
        ),
      );
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    Color iconColor = const Color(0xFFAAA4FF),
  }) {
    return Material(
      color: const Color(0xFF121725),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFF292F42)),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: const Color(0xFF24205A),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF8E91A3),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF777D8E),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Account'),
                    _settingsTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Profile Settings',
                      subtitle: user?.email ?? 'Manage your personal profile',
                      onTap: () => _openScreen(const ProfileSettingsScreen()),
                    ),
                    const SizedBox(height: 10),
                    _settingsTile(
                      icon: Icons.apartment_rounded,
                      title: 'Organization Settings',
                      subtitle: 'Members, departments and permissions',
                      onTap: () =>
                          _openScreen(const OrganizationSettingsScreen()),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Keeper experience'),
                    _settingsTile(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notifications',
                      subtitle: 'Upload, organization and reminder updates',
                      trailing: Switch(
                        value: _notificationsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _notificationsEnabled = value;
                          });
                        },
                        activeThumbColor: const Color(0xFFAAA4FF),
                        activeTrackColor: const Color(0xFF5147E5),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _settingsTile(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Knowledge Suggestions',
                      subtitle: 'Show related documents and study suggestions',
                      trailing: Switch(
                        value: _knowledgeSuggestionsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _knowledgeSuggestionsEnabled = value;
                          });
                        },
                        activeThumbColor: const Color(0xFFAAA4FF),
                        activeTrackColor: const Color(0xFF5147E5),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Help and legal'),
                    _settingsTile(
                      icon: Icons.help_outline_rounded,
                      title: 'Help & Support',
                      subtitle: 'Learn how to use Keeper',
                      onTap: () => _showInfoPage(
                        title: 'Help & Support',
                        content:
                            'Keeper stores your notes, documents, voice notes and important chats in one place.\n\n'
                            'Upload your material, organize it in Personal or Organization knowledge, search it later and ask Keeper AI questions from it.\n\n'
                            'For technical issues, include the exact error message and the action you performed.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _settingsTile(
                      icon: Icons.feedback_outlined,
                      title: 'Send Feedback',
                      subtitle: 'Report bugs or suggest improvements',
                      onTap: _sendFeedback,
                    ),
                    const SizedBox(height: 10),
                    _settingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      subtitle: 'How Keeper handles your information',
                      onTap: () => _openLegalPage(_privacyPolicyUrl),
                    ),
                    const SizedBox(height: 10),
                    _settingsTile(
                      icon: Icons.description_outlined,
                      title: 'Terms of Use',
                      subtitle: 'Rules for using Keeper',
                      onTap: () => _openLegalPage(_termsUrl),
                    ),
                    const SizedBox(height: 10),
                    _settingsTile(
                      icon: Icons.info_outline_rounded,
                      title: 'About Keeper',
                      subtitle: 'Your second brain for everything you learn',
                      onTap: () => _showInfoPage(
                        title: 'About Keeper',
                        content:
                            'Keeper AI is a universal AI-powered knowledge assistant for personal users, schools, colleges, companies, hospitals, offices and other organizations.\n\n'
                            'Documents, notes, images, saved memories and important chats can stay organized, searchable and useful in one place.\n\n'
                            'Version 1.0.2',
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Danger zone'),
                    _settingsTile(
                      icon: Icons.delete_forever_outlined,
                      title: 'Delete Account',
                      subtitle: _isRequestingDeletion
                          ? 'Submitting deletion request...'
                          : 'Request permanent account and data deletion',
                      iconColor: const Color(0xFFFF7D92),
                      onTap: _isRequestingDeletion
                          ? null
                          : _confirmAccountDeletion,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SettingsInfoScreen extends StatelessWidget {
  final String title;
  final String content;

  const _SettingsInfoScreen({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          child: Text(
            content,
            style: const TextStyle(
              color: Color(0xFFB7BAC6),
              fontSize: 14,
              height: 1.7,
            ),
          ),
        ),
      ),
    );
  }
}
