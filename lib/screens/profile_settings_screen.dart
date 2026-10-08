import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _organizationController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  String _email = '';
  String _role = 'individual';
  String? _photoUrl;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _organizationController.dispose();
    _departmentController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadProfile() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Please sign in again.');
      return;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final Map<String, dynamic> data = snapshot.data() ?? {};

      if (!mounted) return;

      setState(() {
        _email = user.email ?? '';
        _nameController.text =
            data['name']?.toString() ??
            data['displayName']?.toString() ??
            user.displayName ??
            '';
        _phoneController.text = data['phone']?.toString() ?? '';
        _organizationController.text =
            data['organizationName']?.toString() ??
            data['organization']?.toString() ??
            data['institution']?.toString() ??
            data['college']?.toString() ??
            '';
        _departmentController.text =
            data['department']?.toString() ??
            data['team']?.toString() ??
            data['branch']?.toString() ??
            '';
        _titleController.text =
            data['jobTitle']?.toString() ??
            data['title']?.toString() ??
            data['semester']?.toString() ??
            '';
        _role = data['role']?.toString().toLowerCase() ?? 'individual';
        _photoUrl = data['photoUrl']?.toString() ?? user.photoURL;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to load profile.');
    }
  }

  Future<void> _changeProfilePhoto() async {
    if (_isUploadingPhoto) return;

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please sign in again.');
      return;
    }

    try {
      final XFile? pickedImage = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );

      if (pickedImage == null) return;

      setState(() {
        _isUploadingPhoto = true;
      });

      final File file = File(pickedImage.path);
      final String extension = pickedImage.name.contains('.')
          ? pickedImage.name.split('.').last.toLowerCase()
          : 'jpg';

      final String storagePath =
          'profile_photos/${user.uid}/profile_${DateTime.now().millisecondsSinceEpoch}.$extension';

      final supabase.SupabaseClient client = supabase.Supabase.instance.client;

      await client.storage
          .from('Keeper-documents')
          .upload(
            storagePath,
            file,
            fileOptions: const supabase.FileOptions(
              upsert: true,
              cacheControl: '3600',
            ),
          );

      final String publicUrl = client.storage
          .from('Keeper-documents')
          .getPublicUrl(storagePath);

      await user.updatePhotoURL(publicUrl);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': publicUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _photoUrl = publicUrl;
      });

      _showMessage('Profile photo updated.');
    } catch (_) {
      _showMessage('Unable to update profile photo.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please sign in again.');
      return;
    }

    final String name = _nameController.text.trim();

    if (name.isEmpty) {
      _showMessage('Please enter your name.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'displayName': name,
        'phone': _phoneController.text.trim(),
        'organizationName': _organizationController.text.trim(),
        'department': _departmentController.text.trim(),
        'jobTitle': _titleController.text.trim(),
        'role': _role,
        'photoUrl': _photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (user.displayName != name) {
        await user.updateDisplayName(name);
      }

      _showMessage('Profile updated successfully.');
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        _showMessage('Permission denied. Check Firestore rules.');
      } else {
        _showMessage('Unable to update profile.');
      }
    } catch (_) {
      _showMessage('Unable to update profile.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
        prefixIcon: Icon(icon, color: const Color(0xFFAAA4FF)),
        filled: true,
        fillColor: const Color(0xFF151B2A),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2B3142)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF766DFF), width: 1.4),
        ),
      ),
    );
  }

  Widget _buildRoleChip(String value, String label) {
    final bool selected = _role == value;

    return ChoiceChip(
      selected: selected,
      label: Text(label),
      selectedColor: const Color(0xFF766DFF),
      backgroundColor: const Color(0xFF151B2A),
      side: BorderSide(
        color: selected ? const Color(0xFF766DFF) : const Color(0xFF2B3142),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFFB4B8C5),
        fontWeight: FontWeight.w700,
      ),
      onSelected: (_) {
        setState(() {
          _role = value;
        });
      },
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
          'Profile Settings',
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
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: const Color(0xFF24205A),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF5147E5),
                                width: 2,
                              ),
                            ),
                            child: ClipOval(
                              child: _photoUrl != null && _photoUrl!.isNotEmpty
                                  ? Image.network(
                                      _photoUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.person_rounded,
                                        color: Color(0xFFAAA4FF),
                                        size: 48,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person_rounded,
                                      color: Color(0xFFAAA4FF),
                                      size: 48,
                                    ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Material(
                              color: const Color(0xFF766DFF),
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: _isUploadingPhoto
                                    ? null
                                    : _changeProfilePhoto,
                                customBorder: const CircleBorder(),
                                child: SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: _isUploadingPhoto
                                      ? const Padding(
                                          padding: EdgeInsets.all(8),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.edit_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        _email.isEmpty ? 'Signed in user' : _email,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _buildField(
                      controller: _nameController,
                      label: 'Full name',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _phoneController,
                      label: 'Phone number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _organizationController,
                      label: 'Organization / Workspace',
                      icon: Icons.apartment_rounded,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _departmentController,
                      label: 'Department / Team',
                      icon: Icons.groups_2_outlined,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _titleController,
                      label: 'Job title / Position',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Primary role',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        _buildRoleChip('individual', 'Individual'),
                        _buildRoleChip('member', 'Team Member'),
                        _buildRoleChip('manager', 'Manager'),
                        _buildRoleChip('admin', 'Administrator'),
                        _buildRoleChip('owner', 'Owner'),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF766DFF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF514B8A),
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
                                    'Saving...',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'Save Profile',
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
