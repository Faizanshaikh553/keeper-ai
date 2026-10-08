import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'chatbot_screen.dart';
import 'create_organization_screen.dart';
import 'documents_screen.dart';
import 'join_organization_screen.dart';
import 'knowledge_screen.dart';
import 'memory_screen.dart';
import 'organization_group_chat_screen.dart';
import 'notifications_screen.dart';
import 'organization_settings_screen.dart';
import 'personal_vault_screen.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';
import 'universal_search_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String organizationName = 'No organization selected';
  String organizationType = '';
  String inviteCode = '';
  bool isLoadingOrganization = true;
  bool isLoadingAnalytics = false;
  String? organizationId;
  String currentOrganizationRole = 'member';
  int totalMembers = 0;
  int totalDepartments = 0;
  int organizationDocuments = 0;
  int personalDocuments = 0;

  @override
  void initState() {
    super.initState();
    _loadOrganization();
  }

  Future<void> _loadOrganization() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          isLoadingOrganization = false;
        });
        return;
      }

      final DocumentSnapshot<Map<String, dynamic>> userDocument =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      String? linkedOrganizationId;

      if (userDocument.exists) {
        final Map<String, dynamic> userData = userDocument.data() ?? const {};
        linkedOrganizationId =
            (userData['organizationId'] ??
                    userData['organization_id'] ??
                    userData['currentOrganizationId'] ??
                    userData['current_organization_id'])
                ?.toString();
      }

      if (linkedOrganizationId != null && linkedOrganizationId.isNotEmpty) {
        final DocumentSnapshot<Map<String, dynamic>> organizationDocument =
            await FirebaseFirestore.instance
                .collection('organizations')
                .doc(linkedOrganizationId)
                .get();

        if (organizationDocument.exists) {
          final Map<String, dynamic> data = organizationDocument.data() ?? {};

          if (!mounted) return;

          setState(() {
            organizationName =
                data['name']?.toString() ?? 'No organization selected';
            organizationType = data['type']?.toString() ?? '';
            inviteCode = data['inviteCode']?.toString() ?? '';
            this.organizationId = organizationDocument.id;
            isLoadingOrganization = false;
          });

          await _loadAnalytics(user.uid);
          return;
        }
      }

      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('organizations')
              .where('memberIds', arrayContains: user.uid)
              .limit(1)
              .get();

      if (!mounted) return;

      if (snapshot.docs.isNotEmpty) {
        final Map<String, dynamic> data = snapshot.docs.first.data();

        setState(() {
          organizationName =
              data['name']?.toString() ?? 'No organization selected';
          organizationType = data['type']?.toString() ?? '';
          inviteCode = data['inviteCode']?.toString() ?? '';
          this.organizationId = snapshot.docs.first.id;
          isLoadingOrganization = false;
        });
        await _loadAnalytics(user.uid);
      } else {
        setState(() {
          isLoadingOrganization = false;
        });
        await _loadAnalytics(user.uid);
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoadingOrganization = false;
      });
    }
  }


  Future<void> _loadAnalytics(String userId) async {
    if (mounted) {
      setState(() {
        isLoadingAnalytics = true;
      });
    }

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final supabase.SupabaseClient client =
          supabase.Supabase.instance.client;

      int members = 0;
      int departments = 0;
      int orgDocuments = 0;
      int personal = 0;
      String role = 'member';

      final String? linkedOrganizationId = organizationId;

      if (linkedOrganizationId != null &&
          linkedOrganizationId.isNotEmpty) {
        final DocumentSnapshot<Map<String, dynamic>> organizationDocument =
            await firestore
                .collection('organizations')
                .doc(linkedOrganizationId)
                .get();

        final Map<String, dynamic> organizationData =
            organizationDocument.data() ?? {};

        final String ownerId =
            organizationData['ownerId']?.toString() ?? '';

        final List<String> adminIds =
            (organizationData['adminIds'] as List<dynamic>? ?? const [])
                .map((item) => item.toString())
                .toList();

        if (ownerId == userId) {
          role = 'owner';
        } else if (adminIds.contains(userId)) {
          role = 'admin';
        } else {
          final DocumentSnapshot<Map<String, dynamic>> memberDocument =
              await firestore
                  .collection('organizations')
                  .doc(linkedOrganizationId)
                  .collection('members')
                  .doc(userId)
                  .get();

          role =
              memberDocument.data()?['role']?.toString().toLowerCase() ??
              'member';
        }

        final AggregateQuerySnapshot memberCount = await firestore
            .collection('organizations')
            .doc(linkedOrganizationId)
            .collection('members')
            .count()
            .get();

        final AggregateQuerySnapshot departmentCount = await firestore
            .collection('organizations')
            .doc(linkedOrganizationId)
            .collection('departments')
            .count()
            .get();

        members = memberCount.count ?? 0;
        departments = departmentCount.count ?? 0;

        final List<dynamic> organizationResponse = await client
            .from('documents')
            .select('id')
            .eq('organization_id', linkedOrganizationId)
            .eq('space', 'organization');

        orgDocuments = organizationResponse.length;
      }

      final List<dynamic> personalResponse = await client
          .from('documents')
          .select('id')
          .eq('user_id', userId)
          .eq('space', 'personal');

      personal = personalResponse.length;

      if (!mounted) return;

      setState(() {
        totalMembers = members;
        totalDepartments = departments;
        organizationDocuments = orgDocuments;
        personalDocuments = personal;
        currentOrganizationRole = role;
        isLoadingAnalytics = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingAnalytics = false;
      });
    }
  }

  String _formatOrganizationRole(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Manager';
      case 'viewer':
        return 'Viewer';
      default:
        return 'Member';
    }
  }

  Future<void> _openScreen(BuildContext context, Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    if (mounted) {
      await _loadOrganization();
    }
  }

  void _showOrganizationOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121725),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Organization',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Create a new workspace or join an existing one.',
                  style: TextStyle(color: Color(0xFF8E91A3), fontSize: 14),
                ),
                const SizedBox(height: 22),
                _OrganizationOption(
                  icon: Icons.add_business_rounded,
                  title: 'Create Organization',
                  subtitle: 'Start a new workspace',
                  onTap: () {
                    Navigator.pop(bottomSheetContext);

                    _openScreen(context, const CreateOrganizationScreen());
                  },
                ),
                const SizedBox(height: 12),
                _OrganizationOption(
                  icon: Icons.group_add_rounded,
                  title: 'Join Organization',
                  subtitle: 'Join using an invitation code',
                  onTap: () {
                    Navigator.pop(bottomSheetContext);

                    _openScreen(context, const JoinOrganizationScreen());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOrganizationDetails() {
    if (organizationName == 'No organization selected') {
      _showOrganizationOptions(context);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121725),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Organization',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                _buildOrganizationDetail(
                  icon: Icons.apartment_rounded,
                  title: organizationName,
                  subtitle: organizationType.isEmpty
                      ? 'Organization'
                      : organizationType,
                ),
                if (inviteCode.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildOrganizationDetail(
                    icon: Icons.key_rounded,
                    title: inviteCode,
                    subtitle: 'Invitation code',
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(bottomSheetContext);
                      _openScreen(
                        context,
                        const OrganizationSettingsScreen(),
                      );
                    },
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Organization Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF766DFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(bottomSheetContext);
                      _showOrganizationOptions(context);
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Organization Options'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF343A4D)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrganizationDetail({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1421),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF292F42)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
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
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8E91A3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    final String displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim().split(' ').first
        : 'Faizan';

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF766DFF),
          backgroundColor: const Color(0xFF121725),
          onRefresh: _loadOrganization,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF766DFF), Color(0xFF5147E5)],
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'K',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Good evening',
                            style: TextStyle(
                              color: Color(0xFF8E91A3),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _openScreen(context, const NotificationsScreen());
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF141927),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: const Color(0xFF242938)),
                        ),
                        child: const Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Text(
                  'What can Keeper\nhelp you with?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: () {
                    _openScreen(context, const ChatbotScreen());
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF25205C), Color(0xFF151933)],
                      ),
                      border: Border.all(color: const Color(0xFF393274)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33766DFF),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: Color(0xFFB9B4FF),
                            ),
                            SizedBox(width: 9),
                            Text(
                              'Keeper AI Assistant',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        const Text(
                          'Ask questions, find information and understand your personal and organization knowledge.',
                          style: TextStyle(
                            color: Color(0xFFC3C0D5),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 19),
                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1320),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF34305E)),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                color: Color(0xFF938CFF),
                              ),
                              SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  'Ask Keeper AI anything...',
                                  style: TextStyle(
                                    color: Color(0xFF7E8192),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: Color(0xFF938CFF),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Quick access',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 15),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 13,
                  crossAxisSpacing: 13,
                  childAspectRatio: 1.35,
                  children: [
                    _QuickActionCard(
                      icon: Icons.lock_person_rounded,
                      title: 'Personal Vault',
                      subtitle: 'Private encrypted files',
                      onTap: () {
                        _openScreen(
                          context,
                          const PersonalVaultScreen(),
                        );
                      },
                    ),
                    _QuickActionCard(
                      icon: Icons.upload_file_rounded,
                      title: 'Upload Files',
                      subtitle: 'Add cloud documents',
                      onTap: () {
                        _openScreen(context, const UploadScreen());
                      },
                    ),
                    _QuickActionCard(
                      icon: Icons.add_business_rounded,
                      title: 'Create Organization',
                      subtitle: 'Start a workspace',
                      onTap: () {
                        _openScreen(
                          context,
                          const CreateOrganizationScreen(),
                        );
                      },
                    ),
                    _QuickActionCard(
                      icon: Icons.group_add_rounded,
                      title: 'Join Organization',
                      subtitle: 'Join with invite code',
                      onTap: () {
                        _openScreen(
                          context,
                          const JoinOrganizationScreen(),
                        );
                      },
                    ),
                    _QuickActionCard(
                      icon: Icons.folder_copy_outlined,
                      title: 'Knowledge',
                      subtitle: 'Browse resources',
                      onTap: () {
                        _openScreen(context, const KnowledgeScreen());
                      },
                    ),
                    _QuickActionCard(
                      icon: Icons.description_outlined,
                      title: 'Documents',
                      subtitle: 'Files and PDFs',
                      onTap: () {
                        _openScreen(context, const DocumentsScreen());
                      },
                    ),
                    _QuickActionCard(
                      icon: Icons.psychology_alt_outlined,
                      title: 'Keeper Memory',
                      subtitle: 'View saved memories',
                      onTap: () {
                        _openScreen(context, const MemoryScreen());
                      },
                    ),
                    _QuickActionCard(
                      icon: Icons.forum_outlined,
                      title: 'Group Chat',
                      subtitle: 'Organization messages',
                      onTap: () {
                        final String linkedId = organizationId?.trim() ?? '';
                        if (linkedId.isEmpty) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Join or create an organization first.',
                                ),
                              ),
                            );
                          return;
                        }

                        _openScreen(
                          context,
                          OrganizationGroupChatScreen(
                            organizationId: linkedId,
                            organizationName: organizationName,
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                const Text(
                  'Your organization',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 14),

                GestureDetector(
                  onTap: _showOrganizationDetails,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121725),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF252A39)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.apartment_rounded,
                          color: Color(0xFF938CFF),
                          size: 30,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLoadingOrganization
                                    ? 'Loading organization...'
                                    : organizationName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                isLoadingOrganization
                                    ? 'Please wait...'
                                    : organizationType.isEmpty
                                    ? 'Join or create a workspace.'
                                    : organizationType,
                                style: const TextStyle(
                                  color: Color(0xFF8E91A3),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF777A8A),
                        ),
                      ],
                    ),
                  ),
                ),

                if (organizationId != null &&
                    organizationId!.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Organization overview',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1B3E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF393274),
                          ),
                        ),
                        child: Text(
                          _formatOrganizationRole(
                            currentOrganizationRole,
                          ),
                          style: const TextStyle(
                            color: Color(0xFFB9B4FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (isLoadingAnalytics)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          color: Color(0xFF766DFF),
                        ),
                      ),
                    )
                  else
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics:
                          const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.45,
                      children: [
                        _AnalyticsCard(
                          icon: Icons.groups_rounded,
                          value: totalMembers.toString(),
                          label: 'Members',
                        ),
                        _AnalyticsCard(
                          icon: Icons.account_tree_outlined,
                          value: totalDepartments.toString(),
                          label: 'Departments',
                        ),
                        _AnalyticsCard(
                          icon: Icons.apartment_rounded,
                          value: organizationDocuments.toString(),
                          label: 'Org Documents',
                        ),
                        _AnalyticsCard(
                          icon: Icons.person_outline_rounded,
                          value: personalDocuments.toString(),
                          label: 'Personal Docs',
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),

      bottomNavigationBar: _KeeperBottomNavigation(
        onVaultTap: () {
          _openScreen(context, const PersonalVaultScreen());
        },
        onSearchTap: () {
          _openScreen(context, const UniversalSearchScreen());
        },
        onUpdatesTap: () {
          _openScreen(context, const NotificationsScreen());
        },
        onProfileTap: () {
          _openScreen(context, const ProfileScreen());
        },
      ),
    );
  }
}


class _AnalyticsCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _AnalyticsCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF292F42),
        ),
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
            child: Icon(
              icon,
              color: const Color(0xFFAAA4FF),
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8E91A3),
                    fontSize: 10.5,
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

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF121725),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF252A39)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: const Color(0xFF938CFF), size: 27),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF7F8292),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrganizationOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OrganizationOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1421),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFF292F42)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
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
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8E91A3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF777A8A)),
          ],
        ),
      ),
    );
  }
}

class _KeeperBottomNavigation extends StatelessWidget {
  final VoidCallback onVaultTap;
  final VoidCallback onSearchTap;
  final VoidCallback onUpdatesTap;
  final VoidCallback onProfileTap;

  const _KeeperBottomNavigation({
    required this.onVaultTap,
    required this.onSearchTap,
    required this.onUpdatesTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1421),
        border: Border(top: BorderSide(color: Color(0xFF222735))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const _NavigationItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: true,
              ),
              _NavigationItem(
                icon: Icons.lock_person_rounded,
                label: 'Vault',
                onTap: onVaultTap,
              ),
              _NavigationItem(
                icon: Icons.search_rounded,
                label: 'Search',
                onTap: onSearchTap,
              ),
              _NavigationItem(
                icon: Icons.notifications_none_rounded,
                label: 'Updates',
                onTap: onUpdatesTap,
              ),
              _NavigationItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                onTap: onProfileTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _NavigationItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = selected
        ? const Color(0xFF938CFF)
        : const Color(0xFF6F7282);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
