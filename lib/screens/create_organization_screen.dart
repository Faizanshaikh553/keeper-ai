import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'dashboard_screen.dart';

class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  State<CreateOrganizationScreen> createState() =>
      _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _membersController = TextEditingController();

  final List<String> _organizationTypes = [
    'Company',
    'Startup',
    'College',
    'School',
    'Hospital',
    'Clinic',
    'Gym',
    'Agency',
    'NGO',
    'Manufacturing',
    'Retail Store',
    'Restaurant',
    'Institute',
    'Community',
    'Government Office',
    'Other',
  ];

  String? _selectedType;
  String _uploadPermission = 'everyone';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _membersController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _generateInviteCode() {
    final String uuid = const Uuid().v4();
    final String shortCode = uuid.replaceAll('-', '').substring(0, 8);

    return shortCode.toUpperCase();
  }

  Future<void> _createOrganization() async {
    FocusScope.of(context).unfocus();

    final String organizationName = _nameController.text.trim();
    final String membersText = _membersController.text.trim();
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (organizationName.isEmpty) {
      _showMessage('Please enter organization name.');
      return;
    }

    if (organizationName.length < 3) {
      _showMessage('Organization name must contain at least 3 characters.');
      return;
    }

    if (_selectedType == null) {
      _showMessage('Please select organization type.');
      return;
    }

    if (membersText.isEmpty) {
      _showMessage('Please enter number of members.');
      return;
    }

    final int? memberLimit = int.tryParse(membersText);

    if (memberLimit == null || memberLimit < 1) {
      _showMessage('Please enter a valid number of members.');
      return;
    }

    if (memberLimit > 100000) {
      _showMessage('Member limit is too large.');
      return;
    }

    if (currentUser == null) {
      _showMessage('Your login session has expired. Please sign in again.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      final String organizationId = const Uuid().v4();
      final String inviteCode = _generateInviteCode();

      final DocumentReference<Map<String, dynamic>> organizationReference =
          firestore.collection('organizations').doc(organizationId);

      final DocumentReference<Map<String, dynamic>> memberReference =
          organizationReference.collection('members').doc(currentUser.uid);

      final DocumentReference<Map<String, dynamic>> userReference = firestore
          .collection('users')
          .doc(currentUser.uid);

      final WriteBatch batch = firestore.batch();

      batch.set(organizationReference, {
        'organizationId': organizationId,
        'name': organizationName,
        'nameLowercase': organizationName.toLowerCase(),
        'type': _selectedType,
        'memberLimit': memberLimit,
        'currentMemberCount': 1,
        'ownerId': currentUser.uid,
        'ownerEmail': currentUser.email ?? '',
        'ownerName': currentUser.displayName ?? 'Keeper User',
        'inviteCode': inviteCode,
        'adminIds': [currentUser.uid],
        'memberIds': [currentUser.uid],
        'status': 'active',
        'subscriptionStatus': 'free',
        'uploadPermission': _uploadPermission,
        'deletePermission': 'uploader_and_admin',
        'editPermission': 'uploader_and_admin',
        'aiEnabled': true,
        'knowledgeEnabled': true,
        'onboardingAssistantEnabled': false,
        'modules': {
          'knowledgeBase': true,
          'chatAssistant': true,
          'documentSearch': true,
          'onboardingAssistant': false,
          'analytics': false,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(memberReference, {
        'uid': currentUser.uid,
        'email': currentUser.email ?? '',
        'displayName': currentUser.displayName ?? 'Keeper User',
        'role': 'owner',
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      batch.set(userReference, {
        'uid': currentUser.uid,
        'email': currentUser.email ?? '',
        'displayName': currentUser.displayName ?? 'Keeper User',
        'organizationId': organizationId,
        'organizationName': organizationName,
        'organizationRole': 'owner',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Organization created! Invite code: $inviteCode'),
          duration: const Duration(seconds: 3),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 700));

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
        (route) => false,
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;

      String message = 'Unable to create organization. Please try again.';

      if (error.code == 'permission-denied') {
        message = 'Firestore permission denied. Please check database rules.';
      } else if (error.code == 'unavailable') {
        message = 'Please check your internet connection.';
      } else if (error.code == 'already-exists') {
        message = 'This organization already exists.';
      }

      _showMessage(message);
    } catch (error) {
      if (!mounted) return;

      _showMessage('Something went wrong: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              const Text(
                'Create Your Organization',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Create your own AI powered knowledge workspace.',
                style: TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 36),

              _buildLabel('Organization Name'),

              const SizedBox(height: 10),

              TextField(
                controller: _nameController,
                enabled: !_isLoading,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  hint: 'Example: Keeper Technologies',
                  icon: Icons.business_rounded,
                ),
              ),

              const SizedBox(height: 24),

              _buildLabel('Organization Type'),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                dropdownColor: const Color(0xFF121725),
                style: const TextStyle(color: Colors.white, fontSize: 15),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF8E8C9C),
                ),
                decoration: _inputDecoration(
                  hint: 'Select organization type',
                  icon: Icons.category_outlined,
                ),
                items: _organizationTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: _isLoading
                    ? null
                    : (value) {
                        setState(() {
                          _selectedType = value;
                        });
                      },
              ),

              const SizedBox(height: 24),

              _buildLabel('Maximum Members'),

              const SizedBox(height: 10),

              TextField(
                controller: _membersController,
                enabled: !_isLoading,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isLoading) {
                    _createOrganization();
                  }
                },
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  hint: 'Example: 100',
                  icon: Icons.groups_outlined,
                ),
              ),

              const SizedBox(height: 28),

              _buildLabel('Who can upload documents?'),

              const SizedBox(height: 10),

              _PermissionOption(
                value: 'everyone',
                groupValue: _uploadPermission,
                icon: Icons.groups_rounded,
                title: 'Admins and Members',
                subtitle:
                    'All organization members can upload documents to the shared workspace.',
                enabled: !_isLoading,
                onChanged: (value) {
                  setState(() {
                    _uploadPermission = value;
                  });
                },
              ),

              const SizedBox(height: 10),

              _PermissionOption(
                value: 'admin_only',
                groupValue: _uploadPermission,
                icon: Icons.admin_panel_settings_rounded,
                title: 'Admin Only',
                subtitle:
                    'Members can view, search and ask Keeper AI, but only admins can upload.',
                enabled: !_isLoading,
                onChanged: (value) {
                  setState(() {
                    _uploadPermission = value;
                  });
                },
              ),

              const SizedBox(height: 28),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF121725),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF242938)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Color(0xFF938CFF),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You will become the Administrator of this workspace.',
                        style: TextStyle(
                          color: Color(0xFFB7B3FF),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createOrganization,
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
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Creating workspace...',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'Create Organization',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),
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
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF666A78)),
      prefixIcon: Icon(icon, color: const Color(0xFF8E8C9C)),
      filled: true,
      fillColor: const Color(0xFF121725),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF242938)),
      ),
      disabledBorder: OutlineInputBorder(
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

class _PermissionOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _PermissionOption({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;

    return GestureDetector(
      onTap: enabled ? () => onChanged(value) : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.6,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1B1B3E) : const Color(0xFF121725),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? const Color(0xFF766DFF)
                  : const Color(0xFF292F42),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF2A2758)
                      : const Color(0xFF1B2232),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? const Color(0xFFAAA4FF)
                      : const Color(0xFF7F8292),
                  size: 22,
                ),
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
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF8E91A3),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? const Color(0xFF938CFF)
                    : const Color(0xFF656879),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
