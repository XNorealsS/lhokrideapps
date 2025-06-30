import 'package:lhokride/screens/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:dio/dio.dart';
import 'auth/auth_page.dart';
import 'package:lhokride/app_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:install_plugin/install_plugin.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/fcm_listener.dart';
import 'package:app_settings/app_settings.dart'; // Import for opening app settings

class AuthChecker extends StatefulWidget {
  const AuthChecker({Key? key}) : super(key: key);

  @override
  State<AuthChecker> createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker>
    with TickerProviderStateMixin {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _isChecking = true;
  late AnimationController _animationController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  final String _currentAppVersion = '1.0.0';
  final _storage = const FlutterSecureStorage();
  final String _apiBaseUrl = 'https://api.lhokride.com';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _animationController.forward();
    _pulseController.repeat(reverse: true);

    Future.delayed(Duration(seconds: 2), () {
      _checkAppFlowAndNavigate();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<bool> initialBoarded(BuildContext context) async {
    final isboarded = await _storage.read(key: 'isonboarding');
    if (isboarded == null || isboarded.isEmpty) {
      context.go('/onboarding');
      await _storage.write(key: 'isonboarding', value: 'true');
    } else {
      context.go('/auth');
    }
    print("✅ Semua data berhasil dimuat dan disimpan.");
    return true;
  }

  // Mengganti atau memodifikasi initializeAppData
  Future<bool> _fetchCriticalAppData(String token) async {
    try {
      print("🚀 Starting critical app data fetch...");

      // Coba fetch dan simpan user profile. Ini adalah bagian paling kritis.
      final profileSuccess = await _fetchAndSaveUserProfile(token);
      if (!profileSuccess) {
        print(
          "❌ Gagal load profile atau token tidak valid. Akan logout jika 401.",
        );
        // _fetchAndSaveUserProfile sudah menangani logout jika 401,
        // jadi kita hanya perlu mengembalikan false di sini.
        return false;
      }

      // Coba ambil pengaturan aplikasi
      try {
        await _fetchAppSettings();
        _checkAppUpdateIfNeeded(
          context,
        ); // Panggil pengecekan update setelah setting terambil
      } catch (e) {
        print(
          "⚠️ Warning: Gagal fetch app settings (mungkin karena jaringan), akan menggunakan cached atau default. $e",
        );
        // Jangan langsung return false, biarkan aplikasi tetap berjalan dengan setting terakhir jika ada.
      }

      // Coba ambil data toko
      try {
        await _fetchCachedTokoData();
      } catch (e) {
        print(
          "⚠️ Warning: Gagal fetch toko data (mungkin karena jaringan), akan menggunakan cached. $e",
        );
        // Jangan langsung return false.
      }

      print("✅ Critical data successfully fetched or handled.");
      return true;
    } on DioException catch (e) {
      // Atau pakai http.ClientException untuk http package
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        print("❌ Network error during critical data fetch: ${e.message}");
        // Jika ini hanya error jaringan, dan token masih ada, anggap ini bukan kegagalan fatal.
        // Biarkan aplikasi mencoba lanjut dengan data yang ada di storage.
        // Anda bisa tambahkan toast/snackbar di sini untuk memberitahu user.
        print("❗ Proceeding with cached data due to network error.");
        return true; // Anggap sukses jika hanya masalah jaringan dan sudah ada token
      }
      // Untuk error lain (misal 401 dari server), tetap anggap gagal
      print("❌ Non-network error during critical data fetch: $e");
      return false;
    } catch (e) {
      print("❌ General error during critical app data fetch: $e");
      return false;
    }
  }

  Future<void> _checkAppFlowAndNavigate() async {
    try {
      print("🔍 Starting full app flow check...");

      final token = await _storage.read(key: 'token');
      final isboarded = await _storage.read(key: 'isonboarding');

      // Cek apakah token ada. Jika tidak ada, lanjutkan ke onboarding/login
      if (token == null || token.isEmpty) {
        if (isboarded == null || isboarded.isEmpty) {
          await initialBoarded(context);
        } else {
          _navigateToLogin(); // Arahkan ke login jika sudah onboarding tapi tidak ada token
        }
        return; // Hentikan eksekusi lebih lanjut jika tidak ada token
      }

      // Jika token ada, coba inisialisasi data.
      // Bedakan penanganan error: jika error jaringan, jangan langsung logout.
      final bool initSuccess = await _fetchCriticalAppData(
        token,
      ); // Ubah nama fungsi untuk kejelasan

      if (!initSuccess) {
        // Ini berarti _fetchCriticalAppData gagal karena alasan yang tidak bisa diatasi,
        // seperti token invalid atau akun diblokir saat mencoba refresh data penting.
        print(
          "❌ Gagal inisialisasi data penting atau token tidak valid, arahkan ke login.",
        );
        _navigateToLogin();
        return;
      }

      // Cek apakah status user diblokir (status ini baru valid jika _fetchCriticalAppData sukses)
      final status = await _storage.read(key: 'status');
      if (status == 'blocked') {
        print("⛔ Akun diblokir, arahkan ke halaman blocked.");
        _navigateToBlocked();
        return;
      }

      // Semua aman, arahkan ke dashboard
      print("✅ Semua valid, arahkan ke dashboard.");
      final role = await _storage.read(key: 'role');
      if (role == 'driver') {
        _navigateToDashboardDriver();
      } else {
        _navigateToDashboard();
      }
    } catch (e) {
      print('❌ Error during auth flow: $e');
      // Jika terjadi error tak terduga, fallback ke login
      _navigateToLogin();
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _logout({bool navigate = true}) async {
    try {
      print("🚪 Logging out...");
      // Clear all stored data
      await _storage.deleteAll();

      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Navigate to landing page only if navigate is true
      if (navigate && mounted) {
        context.go('/');
      }
      print("✅ Logout successful.");
    } catch (e) {
      print('❌ Error during logout: $e');
    }
  }

  void _navigateToDashboard() {
    if (mounted) {
      context.go('/dashboard');
    }
  }
  void _navigateToDashboardDriver() {
    if (mounted) {
      context.go('/dashboard/driver');
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      context.go('/auth');
    }
  }

  void _navigateToBlocked() {
    if (mounted) {
      context.go('/blocked');
    }
  }

  Future<Map<String, dynamic>> _getAppFlowStatus() async {
    final token = await _storage.read(key: 'token');
    final isLoggedIn = token != null && token.isNotEmpty;

    return {'isLoggedIn': isLoggedIn};
  }

  Future<bool> _fetchAndSaveUserProfile(String token) async {
    try {
      print("Sending request to fetch user profile...");
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Profile fetch status code: ${response.statusCode}');
      print('Profile fetch response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'];

        await _storage.write(
          key: 'user_id',
          value: user['user_id']?.toString(),
        );
        await _storage.write(key: 'name', value: user['name']);
        await _storage.write(key: 'phone', value: user['phone']);
        await _storage.write(key: 'role', value: user['role']);
        await _storage.write(key: 'status', value: user['status'] ?? '');
        await _storage.write(key: 'photo', value: user['photo']);
        await _storage.write(
          key: 'saldo',
          value: user['saldo']?.toString() ?? '0',
        );
        await _storage.write(
          key: 'user_created_at',
          value: user['created_at']?.toString() ?? '',
        );
        await _storage.write(key: 'user_updated_at', value: user['updated_at']);

        if (user['role'] == 'driver' && user['driver'] != null) {
          final driver = user['driver'];
          await _storage.write(
            key: 'driver_id',
            value: driver['driver_id']?.toString(),
          );
          await _storage.write(key: 'vehicle', value: driver['vehicle']);
          await _storage.write(
            key: 'plate_number',
            value: driver['plate_number'],
          );
          await _storage.write(
            key: 'rating',
            value: driver['rating']?.toString(),
          );
          await _storage.write(
            key: 'total_trips',
            value: driver['total_trips']?.toString(),
          );
          await _storage.write(
            key: 'driver_created_at',
            value: driver['created_at'],
          );
          await _storage.write(
            key: 'driver_updated_at',
            value: driver['updated_at'],
          );
        } else {
          await _storage.delete(key: 'driver_id');
          await _storage.delete(key: 'vehicle');
          await _storage.delete(key: 'plate_number');
          await _storage.delete(key: 'rating');
          await _storage.delete(key: 'total_trips');
          await _storage.delete(key: 'driver_created_at');
          await _storage.delete(key: 'driver_updated_at');
        }

        print("✅ Success Loaded All Data");
        return true;
      } else if (response.statusCode == 401) {
        print("❌ Unauthorized: Token expired or invalid. Forcing logout.");
        await _logout(
          navigate: false,
        ); // Don't navigate here, let _checkAppFlowAndNavigate handle it
      } else {
        print("❌ Failed to fetch and update profile: ${response.body}");
        await _logout(
          navigate: false,
        ); // Don't navigate here, let _checkAppFlowAndNavigate handle it
      }
    } catch (e) {
      print('❌ Error fetching and saving user profile: $e');
      await _logout(
        navigate: false,
      ); // Don't navigate here, let _checkAppFlowAndNavigate handle it
    }

    return false;
  }

  Future<void> _fetchAppSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/config/app-setting'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'App-Version': _currentAppVersion,
        },
      );

      print('App settings fetch status: ${response.statusCode}');
      print('App settings response: ${response.body}');

      final prefs = await SharedPreferences.getInstance();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final settings = data['data'];

        await prefs.setString(
          'app_fee',
          settings['app_fee']?.toString() ?? '0',
        );
        await prefs.setString(
          'base_price',
          settings['base_price']?.toString() ?? '0',
        );
        await prefs.setString(
          'price_per_km',
          settings['price_per_km']?.toString() ?? '0',
        );
        await prefs.setString(
          'service_open',
          settings['service_open']?.toString() ?? '',
        );
        await prefs.setString(
          'service_close',
          settings['service_close']?.toString() ?? '',
        );
        await prefs.setString(
          'app_version_server',
          settings['app_version']?.toString() ?? '',
        );
        await prefs.setBool('force_update', settings['force_update'] == true);
        await prefs.setString('apk_url', settings['apk_url']?.toString() ?? '');
        await prefs.setString(
          'update_message',
          settings['update_message']?.toString() ??
              'Tersedia pembaruan penting. Silakan perbarui aplikasi.',
        );
        await prefs.setString(
          'running_teks',
          settings['running_teks']?.toString() ?? '',
        );

        print("✅ App config saved to SharedPreferences (Status 200)");
      } else if (response.statusCode == 426) {
        final data = jsonDecode(response.body);
        final message =
            data['message']?.toString() ?? 'Aplikasi perlu diperbarui.';
        final serverLatestVersion = data['latest_version']?.toString() ?? '';
        final apkUrlFromServer = data['apk_url']?.toString() ?? '';

        print(
          '❗ Force update required (Status 426): $message (Server Version: $serverLatestVersion)',
        );

        await prefs.setString('app_version_server', serverLatestVersion);
        await prefs.setBool('force_update', true);
        await prefs.setString('apk_url', apkUrlFromServer);
        await prefs.setString('update_message', message);

        print(
          "✅ App config for force update saved to SharedPreferences (Status 426)",
        );
      } else {
        print(
          '❌ Failed to fetch app settings with status: ${response.statusCode}',
        );
        await prefs.setBool('force_update', false);
        await prefs.setString('app_version_server', _currentAppVersion);
      }
    } catch (e) {
      print('❌ Error fetching app settings: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('force_update', false);
      await prefs.setString('app_version_server', _currentAppVersion);
    }
  }

  Future<void> _fetchCachedTokoData() async {
    try {
      print("📦 Fetching all toko & menu data");

      final tokoResponse = await http.get(
        Uri.parse('$_apiBaseUrl/api/mitratoko/toko'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      print('Toko fetch status: ${tokoResponse.statusCode}');
      if (tokoResponse.statusCode == 200) {
        final tokoListJson = tokoResponse.body;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_lhokfood', tokoListJson);

        print('✅ Toko data saved to SharedPreferences (cached_lhokfood)');
      } else {
        print('❌ Failed to fetch toko: ${tokoResponse.body}');
      }
    } catch (e) {
      print('❌ Error fetching toko data: $e');
    }
  }

  Future<void> _checkAppUpdateIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final appVersionServer = prefs.getString('app_version_server');
    final forceUpdate = prefs.getBool('force_update') ?? false;
    final apkUrl = prefs.getString('apk_url');
    final updateMessage =
        prefs.getString('update_message') ??
        'Tersedia pembaruan penting. Silakan perbarui aplikasi.';

    print("--- DIALOG TRIGGER CHECK ---");
    print("Current App Version (in dialog check): $_currentAppVersion");
    print("Server App Version (in dialog check): $appVersionServer");
    print("Force Update Flag (in dialog check): $forceUpdate");
    print("APK URL (in dialog check): $apkUrl");
    print(
      "Is Current Version Lower (in dialog check): ${_isVersionLower(_currentAppVersion, appVersionServer ?? '0.0.0')}",
    );
    print(
      "APK URL is not empty (in dialog check): ${apkUrl != null && apkUrl.isNotEmpty}",
    );
    print("--- END DIALOG TRIGGER CHECK ---");

    if (appVersionServer != null &&
        forceUpdate &&
        _isVersionLower(_currentAppVersion, appVersionServer) &&
        apkUrl != null &&
        apkUrl.isNotEmpty) {
      print(
        "✅ All conditions met for update popup. Navigating to ForceUpdateScreen.",
      );
      // Navigate to the dedicated ForceUpdateScreen
      if (mounted) {
        context.go(
          '/update',
          extra: {
            'updateMessage': updateMessage,
            'apkUrl': apkUrl,
            'currentAppVersion': _currentAppVersion,
            'serverAppVersion': appVersionServer,
          },
        );
      }
    } else {
      print("❌ Update popup conditions NOT met. Dialog will not show.");
    }
  }

  bool _isVersionLower(String currentVersion, String serverVersion) {
    final currentParts = currentVersion.split('.').map(int.parse).toList();
    final serverParts = serverVersion.split('.').map(int.parse).toList();

    for (int i = 0; i < currentParts.length; i++) {
      if (i >= serverParts.length) return false;
      if (currentParts[i] < serverParts[i]) return true;
      if (currentParts[i] > serverParts[i]) return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // If _isChecking is true, always show the loading screen
    if (_isChecking) {
      return _buildLoadingScreen();
    }

    // Once _isChecking is false, we can determine the next screen
    // and potentially show the update dialog.
    return FutureBuilder<String?>(
      future: _storage.read(
        key: 'status',
      ), // Only read status after initial check
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // This case should ideally not be hit often if _isChecking is handled correctly,
          // but it's a fallback.
          return _buildLoadingScreen();
        }

        final status = snapshot.data;
        print("Current stored status in build: $status");

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && status != 'blocked') {
            _checkAppUpdateIfNeeded(context);
          }
        });

        if (status == 'blocked') {
          return _buildBlockedScreen();
        }

        // Default to LoginPage if not blocked and other checks passed.
        // The actual navigation to dashboard/login happens within _checkAppFlowAndNavigate,
        // so this part of build will only show the LoginPage if go_router hasn't navigated yet.
        return const LoginPage();
      },
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.orange.withOpacity(0.03),
              Colors.orange.withOpacity(0.05),
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 220,
                              height: 220,
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  16.0,
                                ), // Optional jika SVG terlalu nempel
                                child: AppIcons.lhlagos(), // TIDAK pakai size
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 40),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.orange.shade500,
                          ),
                          backgroundColor: Colors.orange.withOpacity(0.1),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Menyiapkan Aplikasi...',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Loading Resource Aplikasi',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey.shade600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Consider animating these dots or removing if not functional
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (index) {
                          return AnimatedContainer(
                            duration: Duration(
                              milliseconds: 600 + (index * 200),
                            ),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.orange.withOpacity(0.7),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.red.shade50, Colors.white, Colors.red.shade50],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Blocked Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.shade100,
                    border: Border.all(color: Colors.red.shade300, width: 3),
                  ),
                  child: Icon(
                    Icons.block,
                    size: 60,
                    color: Colors.red.shade600,
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                Text(
                  'Akun Terblokir',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // Subtitle
                Text(
                  'Akun Kamu telah terblokir oleh sistem kami karena ada aktivitas mencurigakan',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Information Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade200, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.red.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Informasi Pemblokiran',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '• Akun Kamu diblokir sementara untuk keamanan\n'
                        '• Pemblokiran dilakukan karena terdeteksi aktivitas mencurigakan\n'
                        '• Hubungi customer service untuk bantuan lebih lanjut',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Contact Support Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      _showContactDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Hubungi Customer Service',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Logout Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () async {
                      await _logout();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      side: BorderSide(color: Colors.red.shade600),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Keluar dari Akun',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Footer text
                Text(
                  'Maaf atas ketidaknyamanan yang terjadi.\nTim kami akan membantu menyelesaikan masalah ini.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContactDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Hubungi Customer Service'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Silakan hubungi kami melalui:'),
              const SizedBox(height: 16),
              _buildContactItem(Icons.phone, 'Telepon', '0822-7214-1313'),
              const SizedBox(height: 8),
              _buildContactItem(Icons.email, 'Email', 'lhokrideplus@gmail.com'),
              const SizedBox(height: 8),
              _buildContactItem(Icons.schedule, 'Jam Operasional', '24/7'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}
