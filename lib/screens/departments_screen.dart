import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  bool _isLoading = true;
  bool _isCreating = false;

  String? _organizationId;
  String _organizationName = 'Organization';
  String _currentUserRole = 'member';

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
        _currentUserRole = role;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to load departments.');
    }
  }

  Future<void> _createDepartment() async {
    if (!_canManage) {
      _showMessage('Only organization admins can create departments.');
      return;
    }

    if (_organizationId == null) return;

    final TextEditingController nameController = TextEditingController();

    final TextEditingController descriptionController = TextEditingController();

    String departmentType = 'Academic';

    final Map<String, String>?
    result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
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
                padding: EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  22 + MediaQuery.viewInsetsOf(context).bottom,
                ),
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
                    const Text(
                      'Create Department',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Department name',
                        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFF1A2030),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: departmentType,
                      dropdownColor: const Color(0xFF1A2030),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Department type',
                        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFF1A2030),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Academic',
                          child: Text('Academic'),
                        ),
                        DropdownMenuItem(
                          value: 'Administrative',
                          child: Text('Administrative'),
                        ),
                        DropdownMenuItem(
                          value: 'Operations',
                          child: Text('Operations'),
                        ),
                        DropdownMenuItem(
                          value: 'Support',
                          child: Text('Support'),
                        ),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;

                        setSheetState(() {
                          departmentType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Description (optional)',
                        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFF1A2030),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          final String name = nameController.text.trim();

                          if (name.isEmpty) return;

                          Navigator.pop(sheetContext, {
                            'name': name,
                            'type': departmentType,
                            'description': descriptionController.text.trim(),
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF766DFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Create Department',
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

    nameController.dispose();
    descriptionController.dispose();

    if (result == null) return;

    setState(() {
      _isCreating = true;
    });

    try {
      final User user = FirebaseAuth.instance.currentUser!;

      await FirebaseFirestore.instance
          .collection('organizations')
          .doc(_organizationId)
          .collection('departments')
          .add({
            'name': result['name'],
            'type': result['type'],
            'description': result['description'],
            'createdBy': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'memberCount': 0,
            'documentCount': 0,
            'isActive': true,
          });

      _showMessage('Department created successfully.');
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        _showMessage('Permission denied. Check Firestore rules.');
      } else {
        _showMessage('Unable to create department.');
      }
    } catch (_) {
      _showMessage('Unable to create department.');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _deleteDepartment(
    String departmentId,
    String departmentName,
  ) async {
    if (!_canManage || _organizationId == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Delete department?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '"$departmentName" will be removed. Documents are not deleted.',
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
                'Delete',
                style: TextStyle(color: Color(0xFFFF7D92)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('organizations')
          .doc(_organizationId)
          .collection('departments')
          .doc(departmentId)
          .delete();

      _showMessage('Department deleted.');
    } catch (_) {
      _showMessage('Unable to delete department.');
    }
  }

  Widget _buildDepartmentCard(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data = document.data();

    final String name = data['name']?.toString() ?? 'Unnamed Department';

    final String type = data['type']?.toString() ?? 'Other';

    final String description = data['description']?.toString() ?? '';

    final int memberCount = data['memberCount'] as int? ?? 0;

    final int documentCount = data['documentCount'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF292F42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF24205A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_tree_outlined,
              color: Color(0xFFAAA4FF),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  type,
                  style: const TextStyle(
                    color: Color(0xFFAAA4FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9298A8),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Text(
                  '$memberCount members • $documentCount documents',
                  style: const TextStyle(
                    color: Color(0xFF777D8E),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (_canManage)
            PopupMenuButton<String>(
              color: const Color(0xFF1A2030),
              iconColor: const Color(0xFF9CA3AF),
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteDepartment(document.id, name);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete',
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
          'Departments',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: _canManage && _organizationId != null
          ? FloatingActionButton.extended(
              onPressed: _isCreating ? null : _createDepartment,
              backgroundColor: const Color(0xFF766DFF),
              foregroundColor: Colors.white,
              icon: _isCreating
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_isCreating ? 'Creating...' : 'New Department'),
            )
          : null,
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
                  style: TextStyle(color: Color(0xFF9CA3AF)),
                ),
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
                            Icons.apartment_rounded,
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
                                      ? 'You can manage departments.'
                                      : 'You can view organization departments.',
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
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('organizations')
                          .doc(_organizationId)
                          .collection('departments')
                          .orderBy('createdAt')
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
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Unable to load departments.',
                                style: TextStyle(color: Color(0xFF9CA3AF)),
                              ),
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.account_tree_outlined,
                                    color: Color(0xFF766DFF),
                                    size: 58,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No departments yet.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _canManage
                                        ? 'Create the first department for this organization.'
                                        : 'An admin has not created any departments yet.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF8E91A3),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 90),
                          itemCount: docs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 11),
                          itemBuilder: (context, index) {
                            return _buildDepartmentCard(docs[index]);
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
