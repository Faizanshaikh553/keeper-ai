import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../services/organization_subscription_service.dart';
import 'departments_screen.dart';
import 'documents_screen.dart';
import 'organization_group_chat_screen.dart';
import 'organization_members_screen.dart';
import 'organization_settings_screen.dart';
import 'organization_subscription_screen.dart';

class OrganizationDetailsScreen extends StatefulWidget {
  final String organizationId;

  const OrganizationDetailsScreen({super.key, required this.organizationId});

  @override
  State<OrganizationDetailsScreen> createState() =>
      _OrganizationDetailsScreenState();
}

class _OrganizationDetailsScreenState extends State<OrganizationDetailsScreen> {
  bool _isLoading = true;
  bool _isWorking = false;
  String _name = 'Organization';
  String _type = '';
  String _inviteCode = '';
  String _role = 'member';
  int _members = 0;
  int _departments = 0;
  int _documents = 0;
  OrganizationSubscriptionAccess? _subscription;

  bool get _isOwner => _role == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _load() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final DocumentSnapshot<Map<String, dynamic>> organization =
          await firestore
              .collection('organizations')
              .doc(widget.organizationId)
              .get();
      final Map<String, dynamic> data = organization.data() ?? const {};
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
        final DocumentSnapshot<Map<String, dynamic>> member = await firestore
            .collection('organizations')
            .doc(widget.organizationId)
            .collection('members')
            .doc(user.uid)
            .get();
        role = member.data()?['role']?.toString().toLowerCase() ?? 'member';
      }

      final results = await Future.wait<dynamic>([
        firestore
            .collection('organizations')
            .doc(widget.organizationId)
            .collection('members')
            .count()
            .get(),
        firestore
            .collection('organizations')
            .doc(widget.organizationId)
            .collection('departments')
            .count()
            .get(),
        supabase.Supabase.instance.client
            .from('documents')
            .select('id')
            .eq('organization_id', widget.organizationId)
            .eq('space', 'organization'),
        OrganizationSubscriptionService.load(widget.organizationId),
      ]);

      if (!mounted) return;
      setState(() {
        _name = data['name']?.toString() ?? 'Organization';
        _type = data['type']?.toString() ?? '';
        _inviteCode = data['inviteCode']?.toString() ?? '';
        _role = role;
        _members = (results[0] as AggregateQuerySnapshot).count ?? 0;
        _departments = (results[1] as AggregateQuerySnapshot).count ?? 0;
        _documents = (results[2] as List<dynamic>).length;
        _subscription = results[3] as OrganizationSubscriptionAccess;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _message('Unable to load organization details.');
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _load();
  }

  Future<void> _renameOrganization() async {
    if (!_isOwner || _isWorking) return;
    final TextEditingController controller = TextEditingController(text: _name);
    final String? updatedName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151B2A),
        title: const Text(
          'Rename organization',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Organization name',
            labelStyle: TextStyle(color: Color(0xFF9CA3AF)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updatedName == null || updatedName.length < 3 || updatedName == _name) {
      return;
    }

    setState(() => _isWorking = true);
    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      await firestore
          .collection('organizations')
          .doc(widget.organizationId)
          .update({
            'name': updatedName,
            'nameLowercase': updatedName.toLowerCase(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      final QuerySnapshot<Map<String, dynamic>> members = await firestore
          .collection('organizations')
          .doc(widget.organizationId)
          .collection('members')
          .get();
      for (int start = 0; start < members.docs.length; start += 200) {
        final WriteBatch batch = firestore.batch();
        final int end = start + 200 > members.docs.length
            ? members.docs.length
            : start + 200;
        for (final member in members.docs.sublist(start, end)) {
          batch.set(firestore.collection('users').doc(member.id), {
            'organizationName': updatedName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }
      if (!mounted) return;
      setState(() => _name = updatedName);
      _message('Organization renamed.');
    } catch (_) {
      _message('Unable to rename organization.');
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _deleteOrganization() async {
    if (!_isOwner || _isWorking) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF151B2A),
            title: const Text(
              'Delete organization?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Members will lose access. Personal files will not be affected. This action cannot be undone inside the app.',
              style: TextStyle(color: Color(0xFFB8BBC7), height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFFF7D92)),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _isWorking = true);
    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final QuerySnapshot<Map<String, dynamic>> members = await firestore
          .collection('organizations')
          .doc(widget.organizationId)
          .collection('members')
          .get();

      for (int start = 0; start < members.docs.length; start += 200) {
        final WriteBatch batch = firestore.batch();
        final int end = start + 200 > members.docs.length
            ? members.docs.length
            : start + 200;
        for (final member in members.docs.sublist(start, end)) {
          batch.delete(member.reference);
          batch.set(firestore.collection('users').doc(member.id), {
            'organizationId': null,
            'organizationName': null,
            'organizationRole': null,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }

      await firestore
          .collection('organizations')
          .doc(widget.organizationId)
          .update({
            'status': 'deleted',
            'memberIds': <String>[],
            'adminIds': <String>[],
            'currentMemberCount': 0,
            'deletedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _message('Unable to delete organization.');
      if (mounted) setState(() => _isWorking = false);
    }
  }

  String _subscriptionLabel() {
    if (!OrganizationSubscriptionService.subscriptionsEnabled) {
      return 'Free organization access';
    }
    final OrganizationSubscriptionAccess? access = _subscription;
    if (access == null) return 'Checking plan';
    if (access.isSubscriptionActive) return 'Active plan';
    if (access.isTrialActive) {
      return '${access.trialDaysRemaining} free day(s) remaining';
    }
    return _isOwner ? 'Trial ended · Subscribe ₹499' : 'Plan expired';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        title: const Text(
          'Organization',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF766DFF),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF25205C), Color(0xFF151933)],
                      ),
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(color: const Color(0xFF393274)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: Color(0xFF312B70),
                          child: Icon(
                            Icons.apartment_rounded,
                            color: Color(0xFFB9B4FF),
                            size: 29,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _type.isEmpty ? 'Organization' : _type,
                                style: const TextStyle(
                                  color: Color(0xFFB5B2C8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _RoleBadge(role: _role),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Material(
                    color: const Color(0xFF201B12),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap:
                          _isOwner &&
                              OrganizationSubscriptionService
                                  .subscriptionsEnabled
                          ? () => _open(
                              OrganizationSubscriptionScreen(
                                organizationId: widget.organizationId,
                                organizationName: _name,
                              ),
                            )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFFFC857),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _subscriptionLabel(),
                                style: const TextStyle(
                                  color: Color(0xFFFFE4A3),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (_isOwner &&
                                OrganizationSubscriptionService
                                    .subscriptionsEnabled)
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFFFFC857),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                    children: [
                      _DetailCard(
                        icon: Icons.groups_rounded,
                        value: '$_members',
                        label: 'Members',
                        onTap: () => _open(const OrganizationMembersScreen()),
                      ),
                      _DetailCard(
                        icon: Icons.account_tree_outlined,
                        value: '$_departments',
                        label: 'Departments',
                        onTap: () => _open(const DepartmentsScreen()),
                      ),
                      _DetailCard(
                        icon: Icons.description_outlined,
                        value: '$_documents',
                        label: 'Documents',
                        onTap: () =>
                            _open(const DocumentsScreen(initialTabIndex: 1)),
                      ),
                      _DetailCard(
                        icon: Icons.forum_outlined,
                        value: 'Open',
                        label: 'Group Chat',
                        onTap: () => _open(
                          OrganizationGroupChatScreen(
                            organizationId: widget.organizationId,
                            organizationName: _name,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _ActionTile(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Add Members',
                    subtitle: _inviteCode.isEmpty
                        ? 'Invite code unavailable'
                        : 'Invite code: $_inviteCode',
                    onTap: _inviteCode.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: _inviteCode),
                            );
                            _message('Invitation code copied.');
                          },
                  ),
                  _ActionTile(
                    icon: Icons.tune_rounded,
                    title: 'Organization Settings',
                    subtitle: 'Permissions and Keeper modules',
                    onTap: () => _open(const OrganizationSettingsScreen()),
                  ),
                  if (_isOwner) ...[
                    _ActionTile(
                      icon: Icons.drive_file_rename_outline_rounded,
                      title: 'Rename Organization',
                      subtitle: 'Change the organization display name',
                      onTap: _renameOrganization,
                    ),
                    _ActionTile(
                      icon: Icons.delete_outline_rounded,
                      title: 'Delete Organization',
                      subtitle: 'Remove access for all organization members',
                      danger: true,
                      onTap: _deleteOrganization,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final bool owner = role == 'owner';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: owner ? const Color(0xFF4A3710) : const Color(0xFF1B1B3E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: owner ? const Color(0xFFFFC857) : const Color(0xFF393274),
        ),
      ),
      child: Text(
        role.isEmpty
            ? 'Member'
            : '${role[0].toUpperCase()}${role.substring(1)}',
        style: TextStyle(
          color: owner ? const Color(0xFFFFD978) : const Color(0xFFB9B4FF),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  const _DetailCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF121725),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF292F42)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFAAA4FF)),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = danger
        ? const Color(0xFFFF7D92)
        : const Color(0xFFAAA4FF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Material(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFF292F42)),
            ),
            child: Row(
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: danger ? accent : Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF8E91A3),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF777D8E),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
