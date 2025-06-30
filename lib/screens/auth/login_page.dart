import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for input formatters
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';

// Login Page with Phone Number Input
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _sendOTP() async {
    if (_phoneController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Masukkan nomor HP Kamu';
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
    });

    try {
      final url = Uri.parse('http://api.lhokride.com/api/auth/login');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': _phoneController.text.trim()}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          // Navigate to OTP verification page, passing the phone number
          context.push('/login-otp', extra: _phoneController.text.trim());
        }
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

  bool _isValidPhone(String phone) {
    // Regex for Indonesian phone numbers (starts with 0, +62, or 62, followed by 8-13 digits)
    return RegExp(r'^(\+62|62|0)[0-9]{8,13}$').hasMatch(phone);
  }

  @override
  void dispose() {
    _phoneController.dispose();
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
          onPressed: () => context.go('/auth'), // Adjust as per your routing
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
                'Masuk ke Akun Kamu',
                style: TextStyle(
                  fontSize: 28, // Larger and bolder
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Masukkan nomor HP Kamu yang terdaftar untuk melanjutkan.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 40),

              // Phone Input
              Text(
                'Nomor HP',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),

              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50], // Light grey background
                  borderRadius: BorderRadius.circular(
                    16,
                  ), // More rounded corners
                  border: Border.all(
                    color:
                        _errorMessage != null ? Colors.red : Colors.grey[300]!,
                    width: 1.5, // Slightly thicker border
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05), // Subtle shadow
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone, // Changed to phone
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly, // Allow only digits
                  ],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: '08xxxxxxxxxx', // Updated hint
                    hintStyle: TextStyle(
                      color: Colors.grey[500],
                      fontWeight: FontWeight.normal,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.phone_outlined,
                        color: Colors.grey[600],
                        size: 22,
                      ),
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
                      });
                    }
                  },
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 56, // Slightly taller button
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(
                      0xFFFD9914,
                    ), // Your brand orange
                    foregroundColor: Colors.white,
                    elevation: 0, // No shadow
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16), // More rounded
                    ),
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[600],
                  ),
                  child:
                      _isLoading
                          ? const SizedBox(
                            height: 24, // Larger indicator
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5, // Thicker stroke
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                          : const Text(
                            'Kirim Kode OTP', // Updated button text
                            style: TextStyle(
                              fontSize: 18, // Larger font size
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5, // Slight letter spacing
                            ),
                          ),
                ),
              ),

              const Spacer(),

              // Register Link
              Center(
                child: GestureDetector(
                  onTap: () {
                    context.go(
                      '/register',
                    ); // Assuming '/register' is your registration route
                  },
                  child: RichText(
                    text: TextSpan(
                      text: 'Belum punya akun? ',
                      style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                      children: const [
                        TextSpan(
                          text: 'Daftar Sekarang', // Changed text for clarity
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFFFD9914), // Your brand orange
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20), // Bottom padding
            ],
          ),
        ),
      ),
    );
  }
}
