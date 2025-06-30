import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../widgets/bottom_navigation.dart'; // Ensure this path is correct
import 'package:intl/intl.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _userId;
  String? _userRole;
  String? _userName;
  String? _userPhone;
  String? _userPhoto;
  double? _userBalance;

  final formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isEditMode = false;
  bool _isLoading = false;
  bool _isPhotoUploading = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchWalletBalance(); // New: Fetch wallet balance on init
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final userId = await _storage.read(key: 'user_id');
      final role = await _storage.read(key: 'role');
      final name = await _storage.read(key: 'name');
      final phone = await _storage.read(key: 'phone');
      final photo = await _storage.read(key: 'photo');

      setState(() {
        _userId =
            userId ?? 'LHK${DateTime.now().millisecondsSinceEpoch % 10000}';
        _userRole = role?.toUpperCase() ?? 'PELANGGAN';
        _userName = name ?? 'Pengguna LHOKRIDE+';
        _userPhone = phone ?? '+62 xxx xxxx xxxx';
        _userPhoto = photo;

        // Set controller values
        _nameController.text = _userName!;
        _phoneController.text = _userPhone!;
      });
    } catch (e) {
      _showErrorSnackBar('Error loading user data: ${e.toString()}');
      print('Error loading user data: $e'); // For debugging
    }
  }

  // New: Simulate fetching wallet balance
  Future<void> _fetchWalletBalance() async {
    setState(() {
      _isLoading = true; // Indicate loading for balance
    });
    try {
      final storedBalance = await _storage.read(key: 'saldo');
      setState(() {
        _userBalance = double.tryParse(storedBalance ?? '0.0') ?? 0.0;
      });
    } catch (e) {
      _showErrorSnackBar('Error fetching wallet balance: ${e.toString()}');
      print('Error fetching wallet balance: $e'); // For debugging
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder:
            (context) => Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Pilih Sumber Foto',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            Navigator.pop(context);
                            await _pickImageFromSource(ImageSource.camera);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  size: 40,
                                  color: Colors.orange[600],
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Kamera',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            Navigator.pop(context);
                            await _pickImageFromSource(ImageSource.gallery);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.photo_library,
                                  size: 40,
                                  color: Colors.orange[600],
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Galeri',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
      );
    } catch (e) {
      _showErrorSnackBar('Error membuka pilihan foto: ${e.toString()}');
    }
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);

        // Check file size (max 5MB)
        final fileSize = await file.length();
        if (fileSize > 5 * 1024 * 1024) {
          _showErrorSnackBar('File terlalu besar. Maksimal 5MB');
          return;
        }

        setState(() {
          _selectedImage = file;
        });

        // Show preview dialog
        _showImagePreviewDialog(file);
      }
    } catch (e) {
      _showErrorSnackBar('Error memilih gambar: ${e.toString()}');
    }
  }

  void _showImagePreviewDialog(File imageFile) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Preview Foto Profil'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: FileImage(imageFile),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Apakah Kamu ingin menggunakan foto ini?',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                  });
                },
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _uploadProfilePhoto(imageFile);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[600],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Gunakan Foto'),
              ),
            ],
          ),
    );
  }

  Future<void> _uploadProfilePhoto(File imageFile) async {
    setState(() {
      _isPhotoUploading = true;
    });

    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        throw Exception('Token tidak ditemukan, silakan login ulang');
      }

      // Check if file exists
      if (!await imageFile.exists()) {
        throw Exception('File tidak ditemukan');
      }

      final uri = Uri.parse(
        'http://api.lhokride.com/api/auth/upload-profile-photo',
      );

      // Read file as bytes first to ensure it's valid
      final bytes = await imageFile.readAsBytes();
      final fileName = path.basename(imageFile.path);

      print('📤 Uploading to $uri');
      print('🔑 Token: $token');
      print('📷 File: $fileName (${bytes.length} bytes)');

      final request = http.MultipartRequest('POST', uri);

      // Set headers
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      // Add file from bytes (more reliable than fromPath)
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo', // This must match the field name in your backend
          bytes,
          filename: fileName,
          contentType: MediaType('image', _getImageType(fileName)),
        ),
      );

      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      print('📥 Status code: ${response.statusCode}');
      print('📨 Body: $respStr');

      if (response.statusCode == 200) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo', // This must match the field name in your backend
            bytes,
            filename: fileName,
            contentType: MediaType('image', _getImageType(fileName)),
          ),
        );

        final data = json.decode(respStr);
        final photoUrl = data['photoUrl'];

        await _storage.write(key: 'photo', value: photoUrl);

        setState(() {
          _userPhoto = photoUrl;
          _selectedImage = null;
        });

        print('✅ Foto berhasil diunggah. URL: $photoUrl');
        _showSuccessSnackBar('Foto profil berhasil diunggah!');
      } else {
        String errorMessage = 'Gagal upload';

        try {
          final data = json.decode(respStr);
          errorMessage = data['message'] ?? data['error'] ?? errorMessage;
        } catch (e) {
          errorMessage = 'Server error: ${response.statusCode}';
        }

        switch (response.statusCode) {
          case 400:
            errorMessage = 'File tidak valid atau terlalu besar';
            break;
          case 401:
            errorMessage = 'Sesi habis, silakan login ulang';
            await _handleSessionExpired();
            return;
          case 413:
            errorMessage = 'File terlalu besar (maks 5MB)';
            break;
          case 500:
            errorMessage = 'Server error, coba lagi nanti';
            break;
        }

        print('❌ Upload gagal: $errorMessage');
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('🛑 Error saat upload foto: $e');
      _showErrorSnackBar('Gagal upload foto: ${e.toString()}');
    } finally {
      setState(() {
        _isPhotoUploading = false;
      });
      print('🔚 Selesai upload');
    }
  }

  // Helper method to get image type from filename
  String _getImageType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'jpeg';
      case 'png':
        return 'png';
      case 'gif':
        return 'gif';
      case 'webp':
        return 'webp';
      default:
        return 'jpeg';
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        throw Exception('Token tidak ditemukan, silakan login ulang');
      }

      final response = await http.put(
        Uri.parse('http://api.lhokride.com/api/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'name': _nameController.text.trim(),
          'phone': _userPhone,
          'userId': _userId,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // Update local storage
        await _storage.write(key: 'name', value: _nameController.text.trim());

        // Update local state
        setState(() {
          _userName = _nameController.text.trim();
          _userPhone = _phoneController.text.trim();
          _isEditMode = false;
        });

        _showSuccessSnackBar('Profil berhasil diperbarui!');
      } else if (response.statusCode == 401) {
        await _handleSessionExpired();
      } else {
        throw Exception(data['message'] ?? 'Gagal memperbarui profil');
      }
    } catch (e) {
      _showErrorSnackBar('Error update profil: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSessionExpired() async {
    await _storage.deleteAll();
    if (mounted) {
      _showErrorSnackBar('Sesi telah berakhir, silakan login ulang');
      context.push('/');
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (_isEditMode) {
        // Reset controllers to current values
        _nameController.text = _userName!;
        _phoneController.text = _userPhone!;
      } else {
        _selectedImage = null; // Clear selected image if cancelling edit
      }
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditMode = false;
      // Reset controllers to original values
      _nameController.text = _userName!;
      _phoneController.text = _userPhone!;
      _selectedImage = null; // Clear selected image if cancelling edit
    });
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const Center(
            child: CircularProgressIndicator(color: Colors.orange),
          ),
    );

    await Future.delayed(const Duration(milliseconds: 1000));
    await _storage.deleteAll();

    if (mounted) {
      Navigator.pop(context);
      context.push('/');
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.logout, color: Colors.red),
                SizedBox(width: 10),
                Text('Konfirmasi Keluar'),
              ],
            ),
            content: const Text(
              'Apakah Kamu yakin ingin keluar dari aplikasi?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _logout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Keluar'),
              ),
            ],
          ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange[600]!, Colors.orange[400]!],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          30,
          MediaQuery.of(context).padding.top + 30,
          30,
          30,
        ),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Hero(
                  tag: 'profile_avatar',
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange[900]!.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      image:
                          _selectedImage != null
                              ? DecorationImage(
                                image: FileImage(_selectedImage!),
                                fit: BoxFit.cover,
                              )
                              : _userPhoto != null && _userPhoto!.isNotEmpty
                              ? DecorationImage(
                                image: NetworkImage('$_userPhoto'),
                                fit: BoxFit.cover,
                              )
                              : null,
                    ),
                    child:
                        (_selectedImage == null &&
                                (_userPhoto == null || _userPhoto!.isEmpty))
                            ? Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.orange[600],
                            )
                            : null,
                  ),
                ),
                // Loading overlay for photo upload
                if (_isPhotoUploading)
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                // Camera button
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _isPhotoUploading ? null : _pickImage,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.orange[600]!,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 20,
                        color:
                            _isPhotoUploading
                                ? Colors.grey
                                : Colors.orange[600],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _userName ?? 'Loading...',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _userRole == 'DRIVER' ? 'DRIVER' : 'PELANGGAN',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    Widget? trailingWidget, // Optional widget for the end of the row
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          if (trailingWidget != null) trailingWidget,
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Profil',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _cancelEdit,
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Name field with enhanced validation
            TextFormField(
              controller: _nameController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Nama Lengkap',
                hintText: 'Masukkan nama lengkap Kamu',
                prefixIcon: Icon(Icons.person, color: Colors.orange[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.orange[600]!),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Nama lengkap tidak boleh kosong';
                }
                if (value.trim().length < 2) {
                  return 'Nama minimal 2 karakter';
                }
                if (value.trim().length > 50) {
                  return 'Nama maksimal 50 karakter';
                }
                if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value.trim())) {
                  return 'Nama hanya boleh berisi huruf dan spasi';
                }
                return null;
              },
              maxLength: 50,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _cancelEdit,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text(
                      'Batal',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Text(
                              'Simpan',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  DateTime? _lastBackPressTime;

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tekan sekali lagi untuk keluar')),
      );
      return false; // Don't exit yet
    }
    return true; // Exit the app
  }

  // New: Function to handle XPay Top Up
  void _onXPayTopUp() {
    // _showSuccessSnackBar('Fitur Top Up XPay akan segera tersedia!');
    // In a real app, navigate to a top-up page or show a dialog
    context.push('/xpaytopup');
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: PageWithBottomNav(
        activeTab: 'profile',
        userRole: _userRole?.toLowerCase() ?? 'guest',
        child: Scaffold(
          backgroundColor: Colors.grey[50],
          body: RefreshIndicator(
            onRefresh: () async {
              await _loadUserData();
              await _fetchWalletBalance(); // Refresh balance on pull-to-refresh
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildProfileHeader()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Edit form (only shown in edit mode)
                        if (_isEditMode) _buildEditForm(),

                        // Regular profile info (hidden in edit mode)
                        if (!_isEditMode)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Profil Pengguna',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      if (!_isPhotoUploading) {
                                        _toggleEditMode();
                                      }
                                    },
                                    icon: Icon(
                                      Icons.edit,
                                      color: Colors.orange[600],
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _buildInfoCard(
                                'XPay Wallet',
                                formatter.format(_userBalance ?? 0),
                                Icons.account_balance_wallet,
                                Colors.deepOrange,
                                trailingWidget: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : _onXPayTopUp,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Top Up'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepOrange[400],
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _buildInfoCard(
                                'Nama Lengkap',
                                _userName ?? '-',
                                Icons.person,
                                Colors.orange,
                              ),
                              _buildInfoCard(
                                'Nomor Telepon',
                                _userPhone ?? '-',
                                Icons.phone,
                                Colors.green,
                              ),
                              const SizedBox(
                                height: 20,
                              ), // Spacer before wallet
                              // New: XPay Wallet Card
                            ],
                          ),

                        const SizedBox(height: 10),

                        _buildActionCard(
                          'Riwayat Pesanan',
                          'Lihat riwayat perjalanan atau transaksi',
                          Icons.history,
                          Colors.indigo,
                          () {
                            context.push('/history');
                          },
                        ),
                        _buildActionCard(
                          'Bantuan & Dukungan',
                          'Hubungi tim dukungan kami',
                          Icons.help_outline,
                          Colors.teal,
                          () {
                            context.push('/terms');
                          },
                        ),
                        const SizedBox(height: 40),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: _showLogoutConfirmation,
                            icon: const Icon(Icons.logout),
                            label: const Text('Keluar dari Akun'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
