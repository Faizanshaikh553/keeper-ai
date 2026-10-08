import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OrganizationMembersScreen extends StatefulWidget {
  const OrganizationMembersScreen({super.key});

  @override
  State<OrganizationMembersScreen> createState() =>
      _OrganizationMembersScreenState();
}

class _OrganizationMembersScreenState extends State<OrganizationMembersScreen> {
  bool _isLoading = true;
  String? _organizationId;
  String _currentUserRole = 'member';
  String _organizationName = 'Organization';
  String _inviteCode = '';

  bool get _canManage =>
      _currentUserRole == 'owner' || _currentUserRole == 'admin';

  @override
  void initState() {
    super.initState();
    _loadOrganization();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _findOrganizationId(String userId) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    final DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore
        .collection('users')
        .doc(userId)
        .get();

    final Map<String, dynamic>? userData = userDocument.data();

    final dynamic savedOrganizationId =
        userData?['organizationId'] ??
        userData?['organization_id'] ??
        userData?['currentOrganizationId'] ??
        userData?['current_organization_id'];

    final String savedId = savedOrganizationId?.toString().trim() ?? '';

    if (savedId.isNotEmpty) {
      return savedId;
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

  Future<void> _loadOrganization() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => _isLoading = false);
      _showMessage('Please sign in again.');
      return;
    }

    try {
      final String? organizationId = await _findOrganizationId(user.uid);

      if (organizationId == null || organizationId.isEmpty) {
        if (!mounted) return;

        setState(() => _isLoading = false);
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
      }

      if (!mounted) return;

      setState(() {
        _organizationId = organizationId;
        _organizationName = data['name']?.toString() ?? 'Organization';
        _inviteCode = data['inviteCode']?.toString() ?? '';
        _currentUserRole = role;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      _showMessage('Unable to load organization members.');
    }
  }

  Future<void> _changeRole({
    required String memberId,
    required String currentRole,
    required String memberName,
  }) async {
    if (!_canManage || _organizationId == null) {
      _showMessage('Only organization admins can change roles.');
      return;
    }

    if (currentRole == 'owner') {
      _showMessage('Owner role cannot be changed here.');
      return;
    }

    String selectedRole = currentRole;

    final String? newRole = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF121725),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A4052),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Change role for $memberName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...[
                      ('admin', 'Admin'),
                      ('manager', 'Manager / Teacher'),
                      ('member', 'Member / Student'),
                      ('viewer', 'Viewer'),
                    ].map((item) {
                      final bool selected = selectedRole == item.$1;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: selected
                              ? const Color(0xFF1B1B3E)
                              : const Color(0xFF1A2030),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () {
                              setSheetState(() {
                                selectedRole = item.$1;
                              });
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF766DFF)
                                      : const Color(0xFF2B3142),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: selected
                                        ? const Color(0xFFAAA4FF)
                                        : const Color(0xFF777D8E),
                                  ),
                                  const SizedBox(width: 11),
                                  Text(
                                    item.$2,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, selectedRole),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF766DFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Save Role',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (newRole == null || newRole == currentRole) return;

    try {
      final WriteBatch batch = FirebaseFirestore.instance.batch();

      final DocumentReference<Map<String, dynamic>> memberReference =
          FirebaseFirestore.instance
              .collection('organizations')
              .doc(_organizationId)
              .collection('members')
              .doc(memberId);

      batch.set(memberReference, {
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final DocumentReference<Map<String, dynamic>> organizationReference =
          FirebaseFirestore.instance
              .collection('organizations')
              .doc(_organizationId);

      if (newRole == 'admin') {
        batch.update(organizationReference, {
          'adminIds': FieldValue.arrayUnion([memberId]),
        });
      } else {
        batch.update(organizationReference, {
          'adminIds': FieldValue.arrayRemove([memberId]),
        });
      }

      batch.set(
        FirebaseFirestore.instance.collection('users').doc(memberId),
        {
          'organizationRole': newRole,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      _showMessage('Member role updated.');
    } catch (_) {
      _showMessage('Unable to update member role.');
    }
  }

  Future<void> _removeMember({
    required String memberId,
    required String role,
    required String memberName,
  }) async {
    if (!_canManage || _organizationId == null) return;

    if (role == 'owner') {
      _showMessage('Organization owner cannot be removed.');
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Remove member?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '$memberName will lose access to this organization.',
            style: const TextStyle(color: Color(0xFFB8BBC7)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Remove',
                style: TextStyle(color: Color(0xFFFF7D92)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final WriteBatch batch = FirebaseFirestore.instance.batch();

      batch.delete(
        FirebaseFirestore.instance
            .collection('organizations')
            .doc(_organizationId)
            .collection('members')
            .doc(memberId),
      );

      batch.update(
        FirebaseFirestore.instance
            .collection('organizations')
            .doc(_organizationId),
        {
          'memberIds': FieldValue.arrayRemove([memberId]),
          'adminIds': FieldValue.arrayRemove([memberId]),
          'currentMemberCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      batch.set(
        FirebaseFirestore.instance.collection('users').doc(memberId),
        {
          'organizationId': null,
          'organizationName': null,
          'organizationRole': null,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      _showMessage('Member removed.');
    } catch (_) {
      _showMessage('Unable to remove member.');
    }
  }

  Widget _buildMemberCard(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data = document.data();

    final String name =
        data['name']?.toString() ??
        data['displayName']?.toString() ??
        'Organization Member';

    final String email = data['email']?.toString() ?? '';

    final String role = data['role']?.toString().toLowerCase() ?? 'member';

    final bool isCurrentUser =
        document.id == FirebaseAuth.instance.currentUser?.uid;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF292F42)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF24205A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'M',
                style: const TextStyle(
                  color: Color(0xFFAAA4FF),
                  fontSize: 18,
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
                Text(
                  isCurrentUser ? '$name (You)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8E91A3),
                      fontSize: 11.5,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  role.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFAAA4FF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (_canManage && !isCurrentUser)
            PopupMenuButton<String>(
              color: const Color(0xFF1A2030),
              iconColor: const Color(0xFF9CA3AF),
              onSelected: (value) {
                if (value == 'role') {
                  _changeRole(
                    memberId: document.id,
                    currentRole: role,
                    memberName: name,
                  );
                } else if (value == 'remove') {
                  _removeMember(
                    memberId: document.id,
                    role: role,
                    memberName: name,
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'role',
                  child: Text(
                    'Change Role',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove Member',
                    style: TextStyle(color: Color(0xFFFF7D92)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
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
          'Members',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            )
          : _organizationId == null
          ? const Center(
              child: Text(
                'No organization linked.',
                style: TextStyle(color: Color(0xFF9CA3AF)),
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151B2A),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: const Color(0xFF2B3142)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.groups_rounded,
                            color: Color(0xFFAAA4FF),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _organizationName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _canManage
                                      ? 'You can manage member roles and access.'
                                      : 'You can view organization members.',
                                  style: const TextStyle(
                                    color: Color(0xFF8E91A3),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_canManage && _inviteCode.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _inviteCode),
                          );
                          _showMessage(
                            'Invitation code copied. Share it to add a member.',
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: const Color(0xFFB9B4FF),
                          side: const BorderSide(color: Color(0xFF393274)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text('Add Member · Code $_inviteCode'),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('organizations')
                          .doc(_organizationId)
                          .collection('members')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF766DFF),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Unable to load members.',
                              style: TextStyle(color: Color(0xFF9CA3AF)),
                            ),
                          );
                        }

                        final docs =
                            List<
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >.from(snapshot.data?.docs ?? const [])
                              ..sort((a, b) {
                                final String aName =
                                    (a.data()['displayName'] ??
                                            a.data()['name'] ??
                                            '')
                                        .toString()
                                        .toLowerCase();
                                final String bName =
                                    (b.data()['displayName'] ??
                                            b.data()['name'] ??
                                            '')
                                        .toString()
                                        .toLowerCase();
                                return aName.compareTo(bName);
                              });

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No members found.',
                              style: TextStyle(color: Color(0xFF9CA3AF)),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                          itemCount: docs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _buildMemberCard(docs[index]);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
