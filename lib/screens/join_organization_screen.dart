import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dashboard_screen.dart';

class JoinOrganizationScreen extends StatefulWidget {
  const JoinOrganizationScreen({super.key});

  @override
  State<JoinOrganizationScreen> createState() => _JoinOrganizationScreenState();
}

class _JoinOrganizationScreenState extends State<JoinOrganizationScreen> {
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _joinOrganization() async {
    FocusScope.of(context).unfocus();

    final String inviteCode = _codeController.text.trim().toUpperCase();

    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (inviteCode.isEmpty) {
      _showMessage('Please enter an organization code.');
      return;
    }

    if (inviteCode.length < 4) {
      _showMessage('Please enter a valid organization code.');
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

      final QuerySnapshot<Map<String, dynamic>> result = await firestore
          .collection('organizations')
          .where('inviteCode', isEqualTo: inviteCode)
          .limit(1)
          .get();

      if (result.docs.isEmpty) {
        _showMessage('No organization found with this invite code.');
        return;
      }

      final DocumentReference<Map<String, dynamic>> organizationReference =
          result.docs.first.reference;

      final DocumentReference<Map<String, dynamic>> memberReference =
          organizationReference.collection('members').doc(currentUser.uid);

      final DocumentReference<Map<String, dynamic>> userReference = firestore
          .collection('users')
          .doc(currentUser.uid);

      String organizationName = '';
      String organizationId = organizationReference.id;
      bool wasAlreadyMember = false;

      await firestore.runTransaction((transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> organizationSnapshot =
            await transaction.get(organizationReference);

        final DocumentSnapshot<Map<String, dynamic>> memberSnapshot =
            await transaction.get(memberReference);

        if (!organizationSnapshot.exists) {
          throw Exception('organization-not-found');
        }

        final Map<String, dynamic> organizationData =
            organizationSnapshot.data() ?? {};

        organizationName =
            organizationData['name']?.toString() ?? 'Organization';

        final int currentMemberCount =
            (organizationData['currentMemberCount'] as num?)?.toInt() ?? 0;

        final int memberLimit =
            (organizationData['memberLimit'] as num?)?.toInt() ?? 1;

        final String status =
            organizationData['status']?.toString() ?? 'active';

        if (status != 'active') {
          throw Exception('organization-inactive');
        }

        if (memberSnapshot.exists) {
          wasAlreadyMember = true;

          transaction.set(userReference, {
            'uid': currentUser.uid,
            'email': currentUser.email ?? '',
            'displayName': currentUser.displayName ?? 'Keeper User',
            'organizationId': organizationId,
            'organizationName': organizationName,
            'organizationRole': 'member',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          return;
        }

        if (currentMemberCount >= memberLimit) {
          throw Exception('member-limit-reached');
        }

        transaction.set(memberReference, {
          'uid': currentUser.uid,
          'email': currentUser.email ?? '',
          'displayName': currentUser.displayName ?? 'Keeper User',
          'role': 'member',
          'status': 'active',
          'joinedAt': FieldValue.serverTimestamp(),
        });

        transaction.update(organizationReference, {
          'memberIds': FieldValue.arrayUnion([currentUser.uid]),
          'currentMemberCount': currentMemberCount + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(userReference, {
          'uid': currentUser.uid,
          'email': currentUser.email ?? '',
          'displayName': currentUser.displayName ?? 'Keeper User',
          'organizationId': organizationId,
          'organizationName': organizationName,
          'organizationRole': 'member',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasAlreadyMember
                ? 'You are already a member of $organizationName.'
                : 'Successfully joined $organizationName.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
        (route) => false,
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;

      String message = 'Unable to join organization. Please try again.';

      if (error.code == 'permission-denied') {
        message = 'Firestore permission denied. Please check database rules.';
      } else if (error.code == 'unavailable') {
        message = 'Please check your internet connection.';
      }

      _showMessage(message);
    } catch (error) {
      if (!mounted) return;

      final String errorText = error.toString();

      if (errorText.contains('member-limit-reached')) {
        _showMessage('This organization has reached its member limit.');
      } else if (errorText.contains('organization-inactive')) {
        _showMessage('This organization is currently inactive.');
      } else if (errorText.contains('organization-not-found')) {
        _showMessage('Organization no longer exists.');
      } else {
        _showMessage('Something went wrong. Please try again.');
      }
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),

              IconButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        Navigator.pop(context);
                      },
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),

              const SizedBox(height: 24),

              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x552563EB), blurRadius: 28),
                  ],
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),

              const SizedBox(height: 30),

              const Text(
                'Join an organization',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Enter the invite code shared by your organization administrator.',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 36),

              const Text(
                'Organization code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: _codeController,
                enabled: !_isLoading,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isLoading) {
                    _joinOrganization();
                  }
                },
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  hintText: 'Example: 6FFE61C8',
                  hintStyle: const TextStyle(
                    color: Color(0xFF667085),
                    letterSpacing: 0,
                  ),
                  prefixIcon: const Icon(
                    Icons.key_rounded,
                    color: Color(0xFF60A5FA),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF111827),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFF25324A)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFF25324A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: Color(0xFF3B82F6),
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _joinOrganization,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    disabledBackgroundColor: const Color(0xFF1E3A6D),
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
                              'Joining...',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'Join Organization',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              const Center(
                child: Text(
                  'Ask your administrator for the invitation code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
