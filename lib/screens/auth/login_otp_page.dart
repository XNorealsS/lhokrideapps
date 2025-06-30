import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:shared_preferences/shared_preferences.dart';
// ✅ TAMBAH: Import FCM Service
import '../../services/fcm_listener.dart';

class LoginOTPPage extends StatefulWidget {
  final String phone; // Changed from email to phone

  const LoginOTPPage({
    super.key,
    required this.phone,
  }); // Changed from email to phone

  @override
  State<LoginOTPPage> createState() => _LoginOTPPageState();
}

class _LoginOTPPageState extends State<LoginOTPPage> {
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );
  final _storage = const FlutterSecureStorage();

  bool _isLoading = false;
  String? _errorMessage;
  int _countdown = 60;
  Timer? _timer;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _canResend = false;
    _countdown = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      }
    });
  }

  Future<void> _verifyOTP() async {
    final otp = _otpControllers.map((c) => c.text).join();

    if (otp.length != 6) {
      setState(() {
        _errorMessage = 'Masukkan kode OTP lengkap';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('http://api.lhokride.com/api/auth/verify-login');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': widget.phone,
          'otp': otp,
        }), // Changed from email to phone
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Decoded data: $data');

        final token = data['token'];
        final user = data['user'];

        await _storage.write(key: 'token', value: token);
        await Future.delayed(Duration(milliseconds: 300));
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

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_first_time', false); // <-- Tambahkan ini

        // ✅ TAMBAH: Register FCM token setelah login berhasil
        try {
          await FCMService.instance.registerTokenAfterLogin();
          print('✅ FCM token registered successfully after login');
        } catch (e) {
          print('❌ Failed to register FCM token after login: $e');
          // Jangan stop proses login meski FCM gagal
        }

        if (mounted) {
          context.go('/');
        }
      } else {
        final error = jsonDecode(response.body);
        setState(() {
          _errorMessage = error['message'] ?? 'Kode OTP tidak valid';
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

  Future<void> _resendOTP() async {
    if (!_canResend) return;

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
          'phone': widget.phone,
          'type': 'login',
        }), // Changed from email to phone
      );

      if (response.statusCode == 200) {
        _startCountdown();
        // Clear OTP fields
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _otpFocusNodes[0].requestFocus();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kode OTP baru telah dikirim'),
            backgroundColor: Color(0xFFFD9914),
          ),
        );
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

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
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
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Header
              const Text(
                'Masukkan kode OTP',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Kode telah dikirim ke ${widget.phone}', // Changed from email to phone
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 40),

              // OTP Input Fields
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 45,
                    height: 55,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              _errorMessage != null
                                  ? Colors.red
                                  : Colors.grey[300]!,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _otpControllers[index],
                        focusNode: _otpFocusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) {
                          if (_errorMessage != null) {
                            setState(() {
                              _errorMessage = null;
                            });
                          }

                          if (value.isNotEmpty && index < 5) {
                            _otpFocusNodes[index + 1].requestFocus();
                          } else if (value.isEmpty && index > 0) {
                            _otpFocusNodes[index - 1].requestFocus();
                          }

                          // Auto verify when all fields are filled
                          if (index == 5 && value.isNotEmpty) {
                            final otp =
                                _otpControllers.map((c) => c.text).join();
                            if (otp.length == 6) {
                              _verifyOTP();
                            }
                          }
                        },
                      ),
                    ),
                  );
                }),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Verify Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFD9914),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child:
                      _isLoading
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                          : const Text(
                            'Verifikasi',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ),

              const SizedBox(height: 24),

              // Resend OTP
              Center(
                child:
                    _canResend
                        ? GestureDetector(
                          onTap: _resendOTP,
                          child: const Text(
                            'Kirim ulang kode',
                            style: TextStyle(
                              color: Color(0xFFFD9914),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                        : Text(
                          'Kirim ulang dalam $_countdown detik',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
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
