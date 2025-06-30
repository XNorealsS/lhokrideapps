import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import '../../services/fcm_listener.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Custom OTP Input Widget
class OtpInputWidget extends StatefulWidget {
  final Function(String) onCompleted;
  final Function(String) onChanged;
  final int length;
  final bool hasError;

  const OtpInputWidget({
    super.key,
    required this.onCompleted,
    required this.onChanged,
    this.length = 6,
    this.hasError = false,
  });

  @override
  State<OtpInputWidget> createState() => _OtpInputWidgetState();
}

class _OtpInputWidgetState extends State<OtpInputWidget> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.length,
      (index) => TextEditingController(),
    );
    _focusNodes = List.generate(widget.length, (index) => FocusNode());
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }

    String otp = _controllers.map((controller) => controller.text).join();
    widget.onChanged(otp);

    if (otp.length == widget.length) {
      widget.onCompleted(otp);
    }
  }

  void _handleKeyEvent(RawKeyEvent event, int index) {
    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }
  }

  void clearOtp() {
    for (var controller in _controllers) {
      controller.clear();
    }
    if (_focusNodes.isNotEmpty) {
      _focusNodes[0].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(widget.length, (index) {
        return Focus(
          onKey: (FocusNode node, RawKeyEvent event) {
            _handleKeyEvent(event, index);
            return KeyEventResult.ignored;
          },
          child: Container(
            width: 45,
            height: 55,
            decoration: BoxDecoration(
              border: Border.all(
                color:
                    widget.hasError
                        ? Colors.red
                        : _focusNodes[index].hasFocus
                        ? const Color(0xFFFD9914)
                        : Colors.grey[300]!,
                width: _focusNodes[index].hasFocus ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: TextField(
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) => _onChanged(value, index),
              onTap: () {
                _controllers[index].selection = TextSelection.fromPosition(
                  TextPosition(offset: _controllers[index].text.length),
                );
              },
            ),
          ),
        );
      }),
    );
  }
}

// Terms and Conditions Modal
class TermsAndConditionsModal extends StatefulWidget {
  final VoidCallback onAccept;

  const TermsAndConditionsModal({super.key, required this.onAccept});

  @override
  State<TermsAndConditionsModal> createState() =>
      _TermsAndConditionsModalState();
}

class _TermsAndConditionsModalState extends State<TermsAndConditionsModal> {
  bool _isAccepted = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFD9914),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Syarat dan Ketentuan LhokRide+',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dengan menggunakan aplikasi LhokRide+, Kamu menyetujui syarat dan ketentuan berikut:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildTermsSection('1. Tentang Layanan', [
                      'LhokRide+ adalah aplikasi transportasi online yang menyediakan layanan ojek dan becak lokal di Lhokseumawe',
                      'Layanan tersedia 24/7 dengan driver yang telah terverifikasi',
                      'Kami menghubungkan penumpang dengan driver becak dan ojek tradisional setempat',
                    ]),

                    _buildTermsSection('2. Ketentuan Pengguna', [
                      'Pengguna harus berusia minimal 17 tahun atau memiliki izin dari orang tua/wali',
                      'Informasi yang diberikan harus akurat dan benar',
                      'Dilarang menggunakan aplikasi untuk kegiatan ilegal atau merugikan pihak lain',
                      'Pengguna bertanggung jawab atas keamanan akun dan kata sandi',
                    ]),

                    _buildTermsSection('3. Tarif dan Pembayaran', [
                      'Tarif dihitung berdasarkan jarak tempuh dan waktu perjalanan',
                      'Pembayaran dapat dilakukan secara tunai atau digital',
                      'Biaya tambahan dapat dikenakan untuk jam sibuk atau kondisi khusus',
                      'Pengguna wajib membayar sesuai tarif yang telah disepakati',
                    ]),

                    _buildTermsSection('4. Keselamatan dan Keamanan', [
                      'Pengguna wajib mematuhi protokol keselamatan yang berlaku',
                      'Dilarang membawa barang berbahaya atau illegal',
                      'Bersikap sopan dan menghormati driver',
                      'Laporkan segera jika terjadi masalah atau insiden',
                    ]),

                    _buildTermsSection('5. Privasi Data', [
                      'Data pribadi pengguna akan dijaga kerahasiaannya',
                      'Informasi lokasi hanya digunakan untuk keperluan layanan',
                      'Data tidak akan dibagikan kepada pihak ketiga tanpa persetujuan',
                      'Pengguna dapat menghapus akun dan data kapan saja',
                    ]),

                    _buildTermsSection('6. Pembatalan dan Pengembalian', [
                      'Pembatalan dapat dilakukan sebelum driver tiba di lokasi penjemputan',
                      'Biaya pembatalan dapat dikenakan sesuai kebijakan yang berlaku',
                      'Pengembalian dana akan diproses maksimal 3-7 hari kerja',
                      'Komplain dapat diajukan melalui layanan pelanggan',
                    ]),

                    _buildTermsSection('7. Tanggung Jawab', [
                      'LhokRide+ berperan sebagai penghubung antara pengguna dan driver',
                      'Tanggung jawab keselamatan selama perjalanan ada pada driver dan pengguna',
                      'Lapor segera jika terjadi kehilangan barang atau masalah lainnya',
                    ]),

                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        border: Border.all(color: Colors.orange[200]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Dengan melanjutkan pendaftaran, Kamu menyatakan telah membaca, memahami, dan menyetujui seluruh syarat dan ketentuan di atas. Syarat dan ketentuan dapat berubah sewaktu-waktu tanpa pemberitahuan sebelumnya.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer dengan checkbox
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _isAccepted,
                        onChanged: (value) {
                          setState(() {
                            _isAccepted = value ?? false;
                          });
                        },
                        activeColor: const Color(0xFFFD9914),
                      ),
                      const Expanded(
                        child: Text(
                          'Saya telah membaca dan menyetujui syarat dan ketentuan serta kebijakan privasi LhokRide+',
                          style: TextStyle(fontSize: 14, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey[400]!),
                            ),
                          ),
                          child: const Text(
                            'Batal',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              _isAccepted
                                  ? () {
                                    Navigator.of(context).pop();
                                    widget.onAccept();
                                  }
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFD9914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            disabledBackgroundColor: Colors.grey[300],
                          ),
                          child: const Text(
                            'Setuju & Lanjutkan',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        ...items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(
                        color: Color(0xFFFD9914),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        const SizedBox(height: 16),
      ],
    );
  }
}

// Register Page with Terms and Conditions
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _storage = const FlutterSecureStorage();

  final _nameController = TextEditingController();
  // Removed _emailController
  final _phoneController = TextEditingController();
  final GlobalKey<_OtpInputWidgetState> _otpKey =
      GlobalKey<_OtpInputWidgetState>();

  String _otpValue = '';
  bool _isLoading = false;
  bool _showOtpField = false;
  bool _termsAccepted = false; // State to track terms acceptance
  String? _errorMessage;
  String? _successMessage;

  Timer? _resendTimer;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    // Potentially show terms on initial load if not accepted
    // _showTermsAndConditions(); // Call this if you want it to pop up automatically
  }

  void _showTermsAndConditions() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => TermsAndConditionsModal(
            onAccept: () {
              setState(() {
                _termsAccepted = true;
              });
            },
          ),
    );
  }

  void _startResendTimer() {
    setState(() {
      _resendCountdown = 60;
    });

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _resendCountdown--;
        });

        if (_resendCountdown <= 0) {
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOTP() async {
    // Cek apakah sudah menyetujui syarat dan ketentuan
    if (!_termsAccepted) {
      _showTermsAndConditions(); // Prompt user to accept if not already
      return;
    }

    // Validasi input (keep existing validation)
    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Nama lengkap tidak boleh kosong';
      });
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Nomor HP tidak boleh kosong';
      });
      return;
    }

    if (!_isValidPhone(_phoneController.text.trim())) {
      setState(() {
        _errorMessage =
            'Format nomor HP tidak valid (gunakan format Indonesia)';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final url = Uri.parse('http://api.lhokride.com/api/auth/register');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameController.text.trim(),
          // Removed 'email' from body
          'phone': _phoneController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _showOtpField = true;
          _successMessage =
              'Kode OTP telah dikirim ke nomor HP Kamu'; // Updated message
        });
        _startResendTimer();
      } else {
        final error = jsonDecode(response.body);
        setState(() {
          _errorMessage = error['message'] ?? 'Gagal mengirim OTP';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Terjadi kesalahan. Coba lagi.';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _verifyOTP() async {
    if (_otpValue.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Masukkan kode OTP';
      });
      return;
    }

    if (_otpValue.trim().length != 6) {
      setState(() {
        _errorMessage = 'Kode OTP harus 6 digit';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse(
        'http://api.lhokride.com/api/auth/verify-registration',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': _phoneController.text.trim(),
          'otp': _otpValue.trim(),
        }),
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Decoded data: $data');

        final token = data['token'];
        final user = data['user'];

        await _storage.write(key: 'token', value: token);
        await _storage.write(key: 'user_id', value: user['user_id'].toString());
        await _storage.write(key: 'name', value: user['name']);
        await _storage.write(key: 'phone', value: user['phone']);
        await _storage.write(key: 'role', value: user['role']);
        await _storage.write(key: 'status', value: user['status'] ?? '');
        await _storage.write(key: 'user_created_at', value: user['created_at']);
        await _storage.write(key: 'user_updated_at', value: user['updated_at']);

        if (user['role'] == 'driver' && user['driver'] != null) {
          final driver = user['driver'];
          await _storage.write(
            key: 'driver_id',
            value: driver['driver_id'].toString(),
          );
          await _storage.write(key: 'vehicle', value: driver['vehicle']);
          await _storage.write(
            key: 'plate_number',
            value: driver['plate_number'],
          );
          await _storage.write(
            key: 'rating',
            value: driver['rating'].toString(),
          );
          await _storage.write(
            key: 'total_trips',
            value: driver['total_trips'].toString(),
          );
          await _storage.write(key: 'photo', value: driver['photo']);
          await _storage.write(
            key: 'driver_created_at',
            value: driver['created_at'],
          );
          await _storage.write(
            key: 'driver_updated_at',
            value: driver['updated_at'],
          );
        }

        // ✅ TAMBAH: Register FCM token setelah register berhasil
        try {
          await FCMService.instance.registerTokenAfterLogin();
          print('✅ FCM token registered successfully after registration');
        } catch (e) {
          print('❌ Failed to register FCM token after registration: $e');
        }

        if (mounted) {
          context.go('/');
        }
      } else {
        final error = jsonDecode(response.body);
        setState(() {
          _errorMessage = error['message'] ?? 'Verifikasi OTP gagal';
        });
        // Clear OTP on error
        _otpKey.currentState?.clearOtp();
        _otpValue = '';
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Terjadi kesalahan. Coba lagi.';
      });
      // Clear OTP on error
      _otpKey.currentState?.clearOtp();
      _otpValue = '';
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _resendOTP() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('http://api.lhokride.com/api/auth/resend-otp');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          // Removed 'email' from body
          'phone': _phoneController.text.trim(), // Added phone
          'type': 'register',
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _successMessage = 'Kode OTP baru telah dikirim';
        });
        _startResendTimer();
        // Clear current OTP
        _otpKey.currentState?.clearOtp();
        _otpValue = '';
      } else {
        final error = jsonDecode(response.body);
        setState(() {
          _errorMessage = error['message'] ?? 'Gagal mengirim ulang OTP';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Terjadi kesalahan. Coba lagi.';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  // Removed _isValidEmail method

  bool _isValidPhone(String phone) {
    // Updated regex to be more flexible for Indonesian numbers (e.g., allows starting with 0, +62, or 62)
    return RegExp(r'^(\+62|62|0)[0-9]{8,13}$').hasMatch(phone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    // Removed _emailController.dispose()
    _phoneController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => context.go('/auth'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: MediaQuery.of(context).size.height * 0.02,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Section
                _buildHeader(),

                SizedBox(height: MediaQuery.of(context).size.height * 0.04),

                // Success Message
                if (_successMessage != null) ...[
                  _buildSuccessMessage(),
                  const SizedBox(height: 20),
                ],

                // Main Content Area
                if (!_showOtpField) ...[
                  _buildRegistrationForm(),
                ] else ...[
                  _buildOtpForm(),
                ],

                // Error Message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _buildErrorMessage(),
                ],

                SizedBox(height: MediaQuery.of(context).size.height * 0.06),

                // Action Button
                _buildActionButton(),

                const SizedBox(height: 20),

                // Login Link
                _buildLoginLink(),

                // Bottom padding for smaller screens
                SizedBox(height: MediaQuery.of(context).size.height * 0.02),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _showOtpField
              ? 'Verifikasi Nomor HP'
              : 'Daftar Akun Baru', // Updated header
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            _showOtpField
                ? 'Masukkan kode OTP yang telah dikirim ke nomor HP Kamu untuk menyelesaikan pendaftaran.' // Concise OTP instruction
                : 'Buat akun LhokRide+ baru untuk akses mudah ke layanan kami.', // More concise registration instruction
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border.all(color: Colors.green[200]!),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle, color: Colors.green[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _successMessage!,
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationForm() {
    return Column(
      children: [
        _buildInputField(
          'Nama Lengkap',
          _nameController,
          'Masukkan nama lengkap Kamu', // Hint text provides instruction
          Icons.person_outline,
        ),
        const SizedBox(height: 24),
        // Removed Email Input Field
        // _buildInputField(
        //   'Email',
        //   _emailController,
        //   'contoh@email.com',
        //   Icons.email_outlined,
        //   keyboardType: TextInputType.emailAddress,
        // ),
        // const SizedBox(height: 24),
        _buildInputField(
          'Nomor HP',
          _phoneController,
          '08xxxxxxxxxx',
          Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 32),
        // Simplified Terms and Conditions section
        _buildTermsConsentSection(), // New widget for terms consent
      ],
    );
  }

  Widget _buildOtpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kode Verifikasi (OTP)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Masukkan 6 digit kode yang dikirim ke nomor HP Kamu.', // Updated instruction
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),

        // OTP Input Boxes
        Center(
          child: OtpInputWidget(
            key: _otpKey,
            hasError: _errorMessage != null,
            onChanged: (value) {
              setState(() {
                _otpValue = value;
                if (_errorMessage != null) {
                  _errorMessage = null;
                  _successMessage = null;
                }
              });
            },
            onCompleted: (value) {
              setState(() {
                _otpValue = value;
              });
              if (value.length == 6) {
                _verifyOTP();
              }
            },
          ),
        ),

        const SizedBox(height: 32),

        // Resend OTP Section
        _buildResendSection(),
      ],
    );
  }

  // --- UPDATED _buildResendSection() ---
  Widget _buildResendSection() {
    return Center(
      // Center the text within the column
      child:
          _resendCountdown > 0
              ? Text(
                'Kirim ulang kode dalam ${_resendCountdown}s',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              )
              : TextButton(
                onPressed: _isLoading ? null : _resendOTP,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero, // Remove default padding
                  alignment:
                      Alignment.center, // Center the text within the button
                ),
                child: Text(
                  'Kirim Ulang Kode',
                  style: TextStyle(
                    fontSize: 16, // Slightly larger for better tap target
                    fontWeight: FontWeight.w600,
                    color:
                        _isLoading
                            ? Colors.grey[500]
                            : const Color(0xFFFD9914), // Use your orange color
                  ),
                ),
              ),
    );
  }

  // NEW: Simplified Terms and Conditions Consent Section
  Widget _buildTermsConsentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: _termsAccepted,
              onChanged: (value) {
                setState(() {
                  _termsAccepted = value ?? false;
                });
              },
              activeColor: const Color(0xFFFD9914),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _showTermsAndConditions,
                child: RichText(
                  text: TextSpan(
                    text: 'Saya menyetujui ',
                    style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                    children: [
                      TextSpan(
                        text: 'Syarat dan Ketentuan',
                        style: const TextStyle(
                          color: Color(0xFFFD9914),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      TextSpan(
                        text: ' LhokRide+.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController controller,
    String hint,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 16),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(icon, color: Colors.grey[600], size: 22),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
            onChanged: (value) {
              if (_errorMessage != null) {
                setState(() {
                  _errorMessage = null;
                  _successMessage = null;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(color: Colors.red[200]!),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, color: Colors.red[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed:
            _isLoading
                ? null
                : (_showOtpField
                    ? _verifyOTP
                    : (_termsAccepted
                        ? _sendOTP
                        : null)), // Disable if terms not accepted
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFD9914),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          shadowColor: const Color(0xFFFD9914).withOpacity(0.3),
          disabledBackgroundColor: Colors.grey[300],
          disabledForegroundColor: Colors.grey[600],
        ),
        child:
            _isLoading
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                : Text(
                  _showOtpField ? 'Verifikasi OTP' : 'Kirim Kode OTP',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            text: 'Sudah punya akun? ',
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            children: [
              WidgetSpan(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text(
                    'Masuk di sini',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFFFD9914),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
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
