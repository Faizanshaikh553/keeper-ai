import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrganizationAccess {
  final String? organizationId;
  final String role;
  final String uploadPermission;
  final String editPermission;
  final String deletePermission;

  const OrganizationAccess({
    required this.organizationId,
    required this.role,
    required this.uploadPermission,
    required this.editPermission,
    required this.deletePermission,
  });

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'owner' || role == 'admin';

  bool get canUpload {
    if (organizationId == null || organizationId!.isEmpty) return false;
    if (isAdmin) return true;
    return uploadPermission == 'everyone';
  }

  bool canEditDocument(String uploaderId, String currentUserId) {
    if (isAdmin) return true;

    if (editPermission == 'uploader_and_admin') {
      return uploaderId.isNotEmpty && uploaderId == currentUserId;
    }

    return false;
  }

  bool canDeleteDocument(String uploaderId, String currentUserId) {
    if (isAdmin) return true;

    if (deletePermission == 'uploader_and_admin') {
      return uploaderId.isNotEmpty && uploaderId == currentUserId;
    }

    return false;
  }
}

class OrganizationPermissionService {
  OrganizationPermissionService._();

  static Future<OrganizationAccess> loadCurrentUserAccess() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const OrganizationAccess(
        organizationId: null,
        role: 'member',
        uploadPermission: 'everyone',
        editPermission: 'uploader_and_admin',
        deletePermission: 'uploader_and_admin',
      );
    }

    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    final DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore
        .collection('users')
        .doc(user.uid)
        .get();

    final Map<String, dynamic> userData = userDocument.data() ?? {};

    final dynamic organizationValue =
        userData['organizationId'] ??
        userData['organization_id'] ??
        userData['currentOrganizationId'] ??
        userData['current_organization_id'];

    String? organizationId = organizationValue?.toString().trim();

    if (organizationId == null || organizationId.isEmpty) {
      final QuerySnapshot<Map<String, dynamic>> ownedOrganization =
          await firestore
              .collection('organizations')
              .where('ownerId', isEqualTo: user.uid)
              .limit(1)
              .get();

      if (ownedOrganization.docs.isNotEmpty) {
        organizationId = ownedOrganization.docs.first.id;
      }
    }

    if (organizationId == null || organizationId.isEmpty) {
      final QuerySnapshot<Map<String, dynamic>> joinedOrganization =
          await firestore
              .collection('organizations')
              .where('memberIds', arrayContains: user.uid)
              .limit(1)
              .get();

      if (joinedOrganization.docs.isNotEmpty) {
        organizationId = joinedOrganization.docs.first.id;
      }
    }

    if (organizationId == null || organizationId.isEmpty) {
      return const OrganizationAccess(
        organizationId: null,
        role: 'member',
        uploadPermission: 'everyone',
        editPermission: 'uploader_and_admin',
        deletePermission: 'uploader_and_admin',
      );
    }

    final DocumentSnapshot<Map<String, dynamic>> organizationDocument =
        await firestore.collection('organizations').doc(organizationId).get();

    final Map<String, dynamic> organizationData =
        organizationDocument.data() ?? {};

    final String ownerId = organizationData['ownerId']?.toString() ?? '';

    final List<String> adminIds =
        (organizationData['adminIds'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList();

    String role = 'member';

    if (ownerId == user.uid) {
      role = 'owner';
    } else if (adminIds.contains(user.uid)) {
      role = 'admin';
    } else {
      final DocumentSnapshot<Map<String, dynamic>> memberDocument =
          await firestore
              .collection('organizations')
              .doc(organizationId)
              .collection('members')
              .doc(user.uid)
              .get();

      role =
          memberDocument.data()?['role']?.toString().toLowerCase() ??
          userData['organizationRole']?.toString().toLowerCase() ??
          'member';
    }

    return OrganizationAccess(
      organizationId: organizationId,
      role: role,
      uploadPermission:
          organizationData['uploadPermission']?.toString() ?? 'everyone',
      editPermission:
          organizationData['editPermission']?.toString() ??
          'uploader_and_admin',
      deletePermission:
          organizationData['deletePermission']?.toString() ??
          'uploader_and_admin',
    );
  }
}
