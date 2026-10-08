import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'departments_screen.dart';
import 'organization_members_screen.dart';

class OrganizationSettingsScreen extends StatefulWidget {
  const OrganizationSettingsScreen({super.key});

  @override
  State<OrganizationSettingsScreen> createState() =>
      _OrganizationSettingsScreenState();
}

class _OrganizationSettingsScreenState
    extends State<OrganizationSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  String? _organizationId;
  String _organizationName = 'Organization';
  String _organizationType = '';
  String _currentUserRole = 'member';

  String _uploadPermission = 'everyone';
  String _deletePermission = 'uploader_and_admin';
  String _editPermission = 'uploader_and_admin';

  bool _knowledgeEnabled = true;
  bool _aiEnabled = true;
  bool _onboardingAssistantEnabled = false;

  bool get _isAdmin =>
      _currentUserRole == 'owner' || _currentUserRole == 'admin';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _findOrganizationId(String userId) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    final DocumentSnapshot<Map<String, dynamic>> userSnapshot = await firestore
        .collection('users')
        .doc(userId)
        .get();

    final Map<String, dynamic>? userData = userSnapshot.data();

    final dynamic savedOrganizationId =
        userData?['organizationId'] ??
        userData?['organization_id'] ??
        userData?['currentOrganizationId'] ??
        userData?['current_organization_id'];

    final String organizationId = savedOrganizationId?.toString().trim() ?? '';

    if (organizationId.isNotEmpty) {
      return organizationId;
    }

    final QuerySnapshot<Map<String, dynamic>> ownedOrganization =
        await firestore
            .collection('organizations')
            .where('ownerId', isEqualTo: userId)
            .limit(1)
            .get();

    if (ownedOrganization.docs.isNotEmpty) {
      return ownedOrganization.docs.first.id;
    }

    final QuerySnapshot<Map<String, dynamic>> joinedOrganization =
        await firestore
            .collection('organizations')
            .where('memberIds', arrayContains: userId)
            .limit(1)
            .get();

    if (joinedOrganization.docs.isNotEmpty) {
      return joinedOrganization.docs.first.id;
    }

    return null;
  }

  Future<void> _loadSettings() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Please sign in again.');
      return;
    }

    try {
      final String? organizationId = await _findOrganizationId(user.uid);

      if (organizationId == null || organizationId.isEmpty) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });

        _showMessage('No organization is linked with this account.');
        return;
      }

      final DocumentSnapshot<Map<String, dynamic>> organizationDocument =
          await FirebaseFirestore.instance
              .collection('organizations')
              .doc(organizationId)
              .get();

      final Map<String, dynamic> data = organizationDocument.data() ?? {};

      final String ownerId = data['ownerId']?.toString() ?? '';

      final List<String> adminIds =
          (data['adminIds'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList();

      String role = 'member';

      if (ownerId == user.uid) {
        role = 'owner';
      } else if (adminIds.contains(user.uid)) {
        role = 'admin';
      } else {
        try {
          final DocumentSnapshot<Map<String, dynamic>> memberDocument =
              await FirebaseFirestore.instance
                  .collection('organizations')
                  .doc(organizationId)
                  .collection('members')
                  .doc(user.uid)
                  .get();

          role =
              memberDocument.data()?['role']?.toString().toLowerCase() ??
              'member';
        } catch (_) {
          role = 'member';
        }
      }

      if (!mounted) return;

      setState(() {
        _organizationId = organizationId;
        _organizationName = data['name']?.toString() ?? 'Organization';
        _organizationType = data['type']?.toString() ?? '';
        _currentUserRole = role;

        _uploadPermission = data['uploadPermission']?.toString() ?? 'everyone';

        _deletePermission =
            data['deletePermission']?.toString() ?? 'uploader_and_admin';

        _editPermission =
            data['editPermission']?.toString() ?? 'uploader_and_admin';

        _knowledgeEnabled = data['knowledgeEnabled'] as bool? ?? true;

        _aiEnabled = data['aiEnabled'] as bool? ?? true;

        _onboardingAssistantEnabled =
            data['onboardingAssistantEnabled'] as bool? ?? false;

        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to load organization settings.');
    }
  }

  Future<void> _saveSettings() async {
    if (!_isAdmin) {
      _showMessage('Only organization admins can change these settings.');
      return;
    }

    if (_organizationId == null || _organizationId!.isEmpty) {
      _showMessage('Organization is not available.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('organizations')
          .doc(_organizationId)
          .set({
            'uploadPermission': _uploadPermission,
            'deletePermission': _deletePermission,
            'editPermission': _editPermission,
            'knowledgeEnabled': _knowledgeEnabled,
            'aiEnabled': _aiEnabled,
            'onboardingAssistantEnabled': _onboardingAssistantEnabled,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      _showMessage('Organization settings saved.');
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        _showMessage('Permission denied. Check Firestore rules.');
      } else {
        _showMessage('Unable to save settings.');
      }
    } catch (_) {
      _showMessage('Unable to save settings.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildPermissionOption({
    required String value,
    required String groupValue,
    required IconData icon,
    required String title,
    required String subtitle,
    required ValueChanged<String> onChanged,
  }) {
    final bool selected = value == groupValue;

    return GestureDetector(
      onTap: !_isAdmin || _isSaving
          ? null
          : () {
              onChanged(value);
            },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: _isAdmin ? 1 : 0.65,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.all(15),
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

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF292F42)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF24205A),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: const Color(0xFFAAA4FF)),
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
            ),
          ),
          Switch(
            value: value,
            onChanged: !_isAdmin || _isSaving ? null : onChanged,
            activeThumbColor: const Color(0xFFAAA4FF),
            activeTrackColor: const Color(0xFF5147E5),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Future<void> _openMembers() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const OrganizationMembersScreen(),
      ),
    );
  }

  Future<void> _openDepartments() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DepartmentsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Organization Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            )
          : _organizationId == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No organization is linked with this account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF25205C), Color(0xFF151933)],
                        ),
                        borderRadius: BorderRadius.circular(21),
                        border: Border.all(color: const Color(0xFF393274)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFF312B70),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.apartment_rounded,
                              color: Color(0xFFB9B4FF),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _organizationName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _organizationType.isEmpty
                                      ? 'Organization'
                                      : _organizationType,
                                  style: const TextStyle(
                                    color: Color(0xFFB5B2C8),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Your role: ${_currentUserRole.toUpperCase()}',
                                  style: const TextStyle(
                                    color: Color(0xFFAAA4FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isAdmin) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF231C2B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF5E3344)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              color: Color(0xFFFF8CA1),
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You can view these settings, but only organization admins can change them.',
                                style: TextStyle(
                                  color: Color(0xFFFFC2CD),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    _buildSectionTitle('Document uploads'),
                    const SizedBox(height: 12),
                    _buildPermissionOption(
                      value: 'everyone',
                      groupValue: _uploadPermission,
                      icon: Icons.groups_rounded,
                      title: 'Admins and Members',
                      subtitle:
                          'All active organization members can upload documents.',
                      onChanged: (value) {
                        setState(() {
                          _uploadPermission = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildPermissionOption(
                      value: 'admin_only',
                      groupValue: _uploadPermission,
                      icon: Icons.admin_panel_settings_rounded,
                      title: 'Admin Only',
                      subtitle:
                          'Members can view, search and ask Keeper AI, but cannot upload.',
                      onChanged: (value) {
                        setState(() {
                          _uploadPermission = value;
                        });
                      },
                    ),
                    const SizedBox(height: 26),
                    _buildSectionTitle('Delete documents'),
                    const SizedBox(height: 12),
                    _buildPermissionOption(
                      value: 'uploader_and_admin',
                      groupValue: _deletePermission,
                      icon: Icons.person_pin_rounded,
                      title: 'Uploader and Admin',
                      subtitle:
                          'The uploader and organization admins can delete a document.',
                      onChanged: (value) {
                        setState(() {
                          _deletePermission = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildPermissionOption(
                      value: 'admin_only',
                      groupValue: _deletePermission,
                      icon: Icons.delete_sweep_rounded,
                      title: 'Admin Only',
                      subtitle:
                          'Only organization admins can delete shared documents.',
                      onChanged: (value) {
                        setState(() {
                          _deletePermission = value;
                        });
                      },
                    ),
                    const SizedBox(height: 26),
                    _buildSectionTitle('Edit document details'),
                    const SizedBox(height: 12),
                    _buildPermissionOption(
                      value: 'uploader_and_admin',
                      groupValue: _editPermission,
                      icon: Icons.edit_note_rounded,
                      title: 'Uploader and Admin',
                      subtitle:
                          'The uploader and admins can rename or recategorize documents.',
                      onChanged: (value) {
                        setState(() {
                          _editPermission = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildPermissionOption(
                      value: 'admin_only',
                      groupValue: _editPermission,
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Admin Only',
                      subtitle:
                          'Only admins can edit organization document details.',
                      onChanged: (value) {
                        setState(() {
                          _editPermission = value;
                        });
                      },
                    ),
                    const SizedBox(height: 26),
                    _buildSectionTitle('Keeper modules'),
                    const SizedBox(height: 12),
                    _buildSwitchTile(
                      icon: Icons.folder_copy_outlined,
                      title: 'Knowledge Base',
                      subtitle:
                          'Allow shared documents to be searched and organized.',
                      value: _knowledgeEnabled,
                      onChanged: (value) {
                        setState(() {
                          _knowledgeEnabled = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildSwitchTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Keeper AI',
                      subtitle:
                          'Allow members to ask questions about organization knowledge.',
                      value: _aiEnabled,
                      onChanged: (value) {
                        setState(() {
                          _aiEnabled = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildSwitchTile(
                      icon: Icons.school_outlined,
                      title: 'Onboarding Assistant',
                      subtitle:
                          'Foundation for organization onboarding and training.',
                      value: _onboardingAssistantEnabled,
                      onChanged: (value) {
                        setState(() {
                          _onboardingAssistantEnabled = value;
                        });
                      },
                    ),
                    const SizedBox(height: 26),
                    _buildSectionTitle('Organization structure'),
                    const SizedBox(height: 12),
                    Material(
                      color: const Color(0xFF121725),
                      borderRadius: BorderRadius.circular(17),
                      child: InkWell(
                        onTap: _openMembers,
                        borderRadius: BorderRadius.circular(17),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(color: const Color(0xFF292F42)),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 42,
                                height: 42,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xFF24205A),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(13),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.groups_rounded,
                                    color: Color(0xFFAAA4FF),
                                  ),
                                ),
                              ),
                              SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Members',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'View members, change roles and remove access.',
                                      style: TextStyle(
                                        color: Color(0xFF8E91A3),
                                        fontSize: 11,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF777D8E),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: const Color(0xFF121725),
                      borderRadius: BorderRadius.circular(17),
                      child: InkWell(
                        onTap: _openDepartments,
                        borderRadius: BorderRadius.circular(17),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(color: const Color(0xFF292F42)),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 42,
                                height: 42,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xFF24205A),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(13),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.account_tree_outlined,
                                    color: Color(0xFFAAA4FF),
                                  ),
                                ),
                              ),
                              SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Departments',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Create and manage organization departments.',
                                      style: TextStyle(
                                        color: Color(0xFF8E91A3),
                                        fontSize: 11,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF777D8E),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: !_isAdmin || _isSaving
                            ? null
                            : _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF766DFF),
                          disabledBackgroundColor: const Color(0xFF514B8A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        child: _isSaving
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 21,
                                    height: 21,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.3,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 11),
                                  Text(
                                    'Saving settings...',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'Save Settings',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
