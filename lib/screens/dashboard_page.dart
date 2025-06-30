import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:marquee/marquee.dart';
import '../widgets/bottom_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_icons.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:ui'; // For BackdropFilter if needed for frosted glass effects
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'webview_page.dart';

// --- Constants for Gradients and Colors (Enhanced) ---
const mainGradient = LinearGradient(
  colors: [Color(0xFFF9A825), Color(0xFFF57F17)], // Warm oranges
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const secondaryGradient = LinearGradient(
  colors: [Color(0xFF42A5F5), Color(0xFF1976D2)], // Vibrant blues
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const premiumGradient = LinearGradient(
  colors: [Color(0xFFFF6B35), Color(0xFFE91E63)], // Orange to deep pink/red
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const eliteGradient = LinearGradient(
  colors: [Color(0xFF9C27B0), Color(0xFF673AB7)], // Purple to deep violet
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// New color palette additions for better consistency and appeal
const Color primaryTextColor = Color(0xFF212121); // Dark grey for general text
const Color secondaryTextColor = Color(
  0xFF616161,
); // Medium grey for secondary text
const Color accentColor = Color(0xFFF9A825); // Main accent orange
const Color backgroundColor = Color(0xFFF8FAFC); // Light background grey

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  String? _userRole, _userId, _userName, _xpayBalance;
  bool _isBalanceHidden = true;
  String _currentLocation = 'Mengambil lokasi...';
  bool _locationPermissionGranted = false;
  bool _isLoadingLocation = true;

  // Enhanced banner system
  final PageController _headerBackgroundBannerController = PageController(
    viewportFraction: 1.0, // Full width for header carousel
  );
  final PageController _premiumPromotionsBannerController = PageController(
    viewportFraction: 1.0,
  );
  final PageController _eliteBannerController = PageController(
    viewportFraction: 0.9,
  );
  int _currentHeaderBackgroundBannerIndex = 0;
  int _currentPremiumPromotionsBannerIndex = 0;
  int _currentEliteBannerIndex = 0;
  List<Map<String, String>> _premiumBanners = [];
  List<Map<String, String>> _eliteBanners = [];

  DateTime? _lastBackPressTime;

  // Animation controllers
  late AnimationController _headerAnimationController;
  late AnimationController _cardAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Timer? _headerBackgroundBannerTimer;
  Timer? _premiumPromotionsBannerTimer;
  Timer? _eliteBannerTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadAllData();
    _setupBannerListeners();
    _loadXpayBalance();
  }

  void _initializeAnimations() {
    _headerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _cardAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _headerAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _cardAnimationController.forward();
    });
  }

  void _startBannerAutoScroll() {
    _headerBackgroundBannerTimer?.cancel();
    _premiumPromotionsBannerTimer?.cancel();
    _eliteBannerTimer?.cancel();

    // Header background banner auto-scroll
    _headerBackgroundBannerTimer = Timer.periodic(const Duration(seconds: 4), (
      timer,
    ) {
      if (!mounted ||
          _premiumBanners.isEmpty ||
          !_headerBackgroundBannerController.hasClients ||
          _headerBackgroundBannerController.positions.isEmpty) {
        // Check for positions
        return;
      }

      try {
        int nextPage =
            (_currentHeaderBackgroundBannerIndex + 1) % _premiumBanners.length;
        _headerBackgroundBannerController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      } catch (e) {
        debugPrint('Header background banner animation error: $e');
        timer.cancel();
      }
    });

    // Premium promotions banner auto-scroll
    _premiumPromotionsBannerTimer = Timer.periodic(const Duration(seconds: 4), (
      timer,
    ) {
      if (!mounted ||
          _premiumBanners.isEmpty ||
          !_premiumPromotionsBannerController.hasClients ||
          _premiumPromotionsBannerController.positions.isEmpty) {
        // Check for positions
        return;
      }

      try {
        int nextPage =
            (_currentPremiumPromotionsBannerIndex + 1) % _premiumBanners.length;

        _premiumPromotionsBannerController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      } catch (e) {
        debugPrint('Premium promotions banner animation error: $e');
        timer.cancel();
      }
    });

    // Elite banner auto-scroll with proper controller checks
    _eliteBannerTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      // Check if widget is still mounted and controller is properly attached
      if (!mounted ||
          _eliteBanners.isEmpty ||
          !_eliteBannerController.hasClients ||
          _eliteBannerController.positions.isEmpty) {
        // Check for positions
        return;
      }

      try {
        int nextPage = (_currentEliteBannerIndex + 1) % _eliteBanners.length;

        _eliteBannerController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      } catch (e) {
        // Handle any animation errors gracefully
        debugPrint('Elite banner animation error: $e');
        timer.cancel();
      }
    });
  }

  // Also update your _setupBannerListeners method for better safety
  void _setupBannerListeners() {
    _headerBackgroundBannerController.addListener(() {
      if (!mounted) return;
      // Only update if dimensions are available and page is not null and controller is attached
      if (_headerBackgroundBannerController.position.haveDimensions &&
          _headerBackgroundBannerController.page != null &&
          _headerBackgroundBannerController.positions.isNotEmpty) {
        final newIndex = _headerBackgroundBannerController.page!.round();
        if (_currentHeaderBackgroundBannerIndex != newIndex) {
          setState(() => _currentHeaderBackgroundBannerIndex = newIndex);
        }
      }
    });

    _premiumPromotionsBannerController.addListener(() {
      if (!mounted) return;
      if (_premiumPromotionsBannerController.position.haveDimensions &&
          _premiumPromotionsBannerController.page != null &&
          _premiumPromotionsBannerController.positions.isNotEmpty) {
        final newIndex = _premiumPromotionsBannerController.page!.round();
        if (_currentPremiumPromotionsBannerIndex != newIndex) {
          setState(() => _currentPremiumPromotionsBannerIndex = newIndex);
        }
      }
    });

    _eliteBannerController.addListener(() {
      if (!mounted) return;
      if (_eliteBannerController.position.haveDimensions &&
          _eliteBannerController.page != null &&
          _eliteBannerController.positions.isNotEmpty) {
        final newIndex = _eliteBannerController.page!.round();
        if (_currentEliteBannerIndex != newIndex) {
          setState(() => _currentEliteBannerIndex = newIndex);
        }
      }
    });
  }

  void _loadAllData() async {
    await _loadUserData(); // Wait for user data to load first
    _loadXpayBalance();
    _initializeLocation();
    _loadBannerUrls().then((_) {
      // Add a small delay to ensure widgets are built
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _startBannerAutoScroll();
        }
      });
    });
    _showDriverActivePopup(); // Call after user role is loaded
  }

  // And make sure to properly manage the timer lifecycle
  @override
  void dispose() {
    // Cancel timers first
    _headerBackgroundBannerTimer?.cancel();
    _premiumPromotionsBannerTimer?.cancel();
    _eliteBannerTimer?.cancel();

    // Then dispose controllers
    _headerAnimationController.dispose();
    _cardAnimationController.dispose();
    _headerBackgroundBannerController.dispose();
    _premiumPromotionsBannerController.dispose();
    _eliteBannerController.dispose();

    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final role = await _storage.read(key: 'role');
      final userId = await _storage.read(key: 'user_id');
      final name = await _storage.read(key: 'name');
      if (mounted) {
        setState(() {
          _userRole = role;
          _userId = userId;
          _userName = name;
          debugPrint('User data loaded: Role=$_userRole, Name=$_userName');
        });
      }
    } catch (e) {
      debugPrint('Error loading user data from storage: $e');
      if (mounted) {
        setState(() {
          _userRole = 'guest'; // Default to guest if data fails
          _userId = 'Unknown';
          _userName = 'Pengguna';
        });
      }
    }
  }

  Future<void> _loadXpayBalance() async {
    // Simulate network delay for balance fetching
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final storedBalance = await _storage.read(key: 'saldo');
      if (mounted) {
        final parsedBalance = int.tryParse(storedBalance ?? '0') ?? 0;
        final formattedBalance = NumberFormat.currency(
          locale: 'id_ID',
          symbol: 'Rp ',
          decimalDigits: 0,
        ).format(parsedBalance);
        setState(() => _xpayBalance = formattedBalance);
        debugPrint('XPay balance loaded: $_xpayBalance');
      }
    } catch (e) {
      debugPrint('Error loading XPay balance: $e');
      if (mounted) {
        setState(() {
          _xpayBalance = 'Rp 0'; // Default to 0 if fails
        });
      }
    }
  }

  void _toggleBalanceVisibility() {
    HapticFeedback.lightImpact();
    setState(() => _isBalanceHidden = !_isBalanceHidden);
  }

  Future<void> _loadBannerUrls() async {
    final url = Uri.parse('http://api.lhokride.com/api/banners/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, String>> premiumBanners = [];
        final List<Map<String, String>> eliteBanners = [];

        for (var item in data) {
          // Ensure 'is_active' exists and is 1
          if (item['is_active'] == 1 &&
              item['direct_link'] != null &&
              item['direct_url'] != null &&
              item['tier'] != null) {
            final banner = {
              'image': item['direct_link'] as String,
              'url': item['direct_url'] as String,
              'tier': item['tier'] as String,
            };

            if (item['tier'] == 'premium') {
              premiumBanners.add(banner);
            } else if (item['tier'] == 'elite') {
              eliteBanners.add(banner);
            }
          }
        }

        if (mounted) {
          setState(() {
            _premiumBanners = premiumBanners;
            _eliteBanners = eliteBanners;
            debugPrint(
              'Banners loaded: Premium=${_premiumBanners.length}, Elite=${_eliteBanners.length}',
            );
          });
        }
      } else {
        debugPrint(
          'Failed to load banners: Status code ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error loading banners: $e');
      // Keep banners empty on error
      if (mounted) {
        setState(() {
          _premiumBanners = [];
          _eliteBanners = [];
        });
      }
    }
  }

  Future<void> _initializeLocation() async {
    if (!mounted) return;
    setState(() => _isLoadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _currentLocation = 'Layanan lokasi tidak aktif';
            _isLoadingLocation = false;
            _locationPermissionGranted = false;
            debugPrint('Location service disabled.');
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationPermissionGranted = false;
            _currentLocation = 'Buka pengaturan untuk izin lokasi';
            _isLoadingLocation = false;
            debugPrint('Location permission denied forever.');
          });
        }
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        if (mounted) setState(() => _locationPermissionGranted = true);
        await _getCurrentLocationSafely();
      } else {
        if (mounted) {
          setState(() {
            _locationPermissionGranted = false;
            _currentLocation = 'Izin lokasi diperlukan';
            _isLoadingLocation = false;
            debugPrint('Location permission not granted.');
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing location: $e');
      if (mounted) {
        setState(() {
          _locationPermissionGranted = false;
          _currentLocation = 'Error mengakses lokasi';
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocationSafely() async {
    if (!mounted) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException('Location fetching timed out');
        },
      );

      if (!mounted) return;

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Geocoding timed out');
        },
      );

      if (!mounted) return;

      String locationText = 'Lokasi tidak dikenal';
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Prioritize street and subLocality, then fall back to locality and subAdministrativeArea
        locationText = [
              place.street,
              place.subLocality,
              place.locality,
              place.subAdministrativeArea,
            ]
            .whereType<String>() // Filter out nulls
            .where((s) => s.isNotEmpty) // Filter out empty strings
            .join(', ');

        if (locationText.isEmpty) {
          locationText = 'Lokasi tidak spesifik';
        }
      }

      if (mounted) {
        setState(() {
          _currentLocation = locationText;
          _isLoadingLocation = false;
          debugPrint('Current location: $_currentLocation');
        });
      }
    } on TimeoutException catch (e) {
      debugPrint('Location/Geocoding timeout: ${e.message}');
      if (mounted) {
        setState(() {
          _currentLocation = 'Waktu habis: ${e.message}';
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      debugPrint('Generic error getting current location: $e');
      if (mounted) {
        setState(() {
          _currentLocation = 'Gagal mengambil lokasi';
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<String?> _getRunningTextFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString('running_teks');
      debugPrint('Running text from prefs: $text');
      return text;
    } catch (e) {
      debugPrint('Error getting running text from SharedPreferences: $e');
      return null;
    }
  }

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tekan sekali lagi untuk keluar'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
          backgroundColor: Colors.black87,
        ),
      );
      return false;
    }
    return true;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Pagi';
    if (hour < 15) return 'Siang';
    if (hour < 18) return 'Sore';
    return 'Malam';
  }

  String _formatRole(String? role) {
    if (role == null) return 'Pengguna';
    switch (role.toLowerCase()) {
      case 'driver':
        return 'Driver';
      case 'customer':
      case 'passenger':
        return 'Pelanggan';
      case 'admin':
        return 'Administrator';
      default:
        return 'Pengguna';
    }
  }

  // New SnackBar for driver restriction
  void _showDriverRestrictionSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Layanan ini hanya tersedia untuk akun pelanggan.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.red.shade600,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // New function to show driver active popup
  Future<void> _showDriverActivePopup() async {
    // Only proceed if context is mounted and _userRole has been loaded
    if (!mounted || _userRole == null) {
      debugPrint('Skipping driver popup: not mounted or role not loaded.');
      return;
    }

    if (_userRole == 'driver') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final bool? driverPopupShown = prefs.getBool('driver_popup_shown');

        if (driverPopupShown == null || !driverPopupShown) {
          debugPrint('Showing driver active popup...');
          Future.delayed(Duration.zero, () {
            if (mounted) {
              // Check mounted again before showing SnackBar
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Selamat! Akun driver Anda sudah aktif dan siap digunakan.',
                  ),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.green.shade600,
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          });
          await prefs.setBool('driver_popup_shown', true);
        } else {
          debugPrint('Driver popup already shown before.');
        }
      } catch (e) {
        debugPrint('Error showing driver active popup: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: PageWithBottomNav(
        activeTab: 'home',
        userRole: _userRole ?? 'guest', // Provide a fallback
        child: Scaffold(
          backgroundColor:
              Colors.transparent, // Make Scaffold background transparent
          body: RefreshIndicator(
            onRefresh: () async {
              debugPrint('Performing refresh...');
              await Future.wait([
                _loadBannerUrls(),
                _loadXpayBalance(),
                _initializeLocation(),
              ]);
              debugPrint('Refresh complete.');
            },
            child: NestedScrollView(
              headerSliverBuilder: (
                BuildContext context,
                bool innerBoxIsScrolled,
              ) {
                return <Widget>[
                  _buildSliverAppBar(context, screenWidth, screenHeight),
                ];
              },
              body: Container(
                decoration: BoxDecoration(
                  color:
                      backgroundColor, // Pastikan backgroundColor didefinisikan
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(screenWidth * 0.08),
                    topRight: Radius.circular(screenWidth * 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: screenWidth * 0.06),
                      _buildMainServices(screenWidth),
                      _buildNewsTicker(screenWidth),
                      _buildQuickActions(screenWidth),
                      if (_premiumBanners.isNotEmpty)
                        _buildPremiumPromotions(screenWidth),
                      if (_eliteBanners.isNotEmpty)
                        _buildElitePromotions(screenWidth),
                      _buildRecentActivity(screenWidth),
                      SizedBox(height: screenHeight * 0.1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    final expandedHeight = screenHeight * 0.32;

    return SliverOverlapAbsorber(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      sliver: SliverAppBar(
        expandedHeight: expandedHeight,
        floating: true,
        pinned: true,
        snap: false,
        stretch: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: FlexibleSpaceBar(
          collapseMode: CollapseMode.pin,
          background: Stack(
            children: [
              // Background content
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child:
                    _premiumBanners.isNotEmpty
                        ? PageView.builder(
                          key: const ValueKey('header_banner_pageview'),
                          controller: _headerBackgroundBannerController,
                          itemCount: _premiumBanners.length,
                          physics: const BouncingScrollPhysics(),
                          onPageChanged: (index) {
                            if (_currentHeaderBackgroundBannerIndex != index) {
                              setState(() {
                                _currentHeaderBackgroundBannerIndex = index;
                              });
                            }
                          },
                          itemBuilder: (context, index) {
                            final banner = _premiumBanners[index];
                            return GestureDetector(
                              onTap: () {
                                if (banner['url']?.isNotEmpty == true) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => WebviewPage(
                                            url: banner['url']!,
                                            Title: 'Promo Premium',
                                          ),
                                    ),
                                  );
                                }
                              },
                              child: AnimatedBuilder(
                                animation: _headerBackgroundBannerController,
                                builder: (context, child) {
                                  double value = 1.0;
                                  if (_headerBackgroundBannerController
                                      .position
                                      .haveDimensions) {
                                    double page =
                                        _headerBackgroundBannerController
                                            .page ??
                                        0;
                                    value = (1 - (index - page).abs()).clamp(
                                      0.0,
                                      1.0,
                                    );
                                  }

                                  return Transform.scale(
                                    scale: Curves.easeInOut.transform(
                                      0.9 + (value * 0.1),
                                    ),
                                    child: Opacity(
                                      opacity: 0.7 + (value * 0.3),
                                      child: CachedNetworkImage(
                                        imageUrl: banner['image']!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                        fadeInDuration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        fadeOutDuration: const Duration(
                                          milliseconds: 100,
                                        ),
                                        placeholder:
                                            (context, url) => Container(
                                              decoration: const BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Color(0xFFF9A825),
                                                    Color(0xFFF57F17),
                                                    Color(0xFFFF8F00),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  stops: [0.0, 0.7, 1.0],
                                                ),
                                              ),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      color: Colors.white
                                                          .withOpacity(0.8),
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                        errorWidget:
                                            (context, url, error) => Container(
                                              decoration: const BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Color(0xFFF9A825),
                                                    Color(0xFFF57F17),
                                                    Color(0xFFFF8F00),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  stops: [0.0, 0.7, 1.0],
                                                ),
                                              ),
                                              child: Center(
                                                child: Icon(
                                                  Icons
                                                      .image_not_supported_rounded,
                                                  color: Colors.white
                                                      .withOpacity(0.7),
                                                  size: screenWidth * 0.08,
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        )
                        : Container(
                          key: const ValueKey('header_gradient_fallback'),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFF9A825),
                                Color(0xFFF57F17),
                                Color(0xFFFF8F00),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              stops: [0.0, 0.7, 1.0],
                            ),
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white.withOpacity(0.8),
                              strokeWidth: 2,
                            ),
                          ),
                        ),
              ),
              // Overlay gradient
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.fromARGB(100, 255, 165, 0),
                      Color.fromARGB(220, 255, 140, 0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: screenHeight * 0.01),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Hero(
                            tag: 'logo',
                            child: AppIcons.lhlogo(size: screenWidth * 0.11),
                          ),
                          Row(
                            children: [
                              _buildColoredHeaderIcon(
                                icon: Icons.notifications_outlined,
                                color: Colors.white,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                },
                                tooltip: 'Notifikasi',
                                iconSize: screenWidth * 0.045,
                              ),
                              SizedBox(width: screenWidth * 0.03),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  context.push('/users/profile');
                                },
                                child: Hero(
                                  tag: 'profile_avatar',
                                  child: Container(
                                    padding: EdgeInsets.all(
                                      screenWidth * 0.005,
                                    ),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    child: CircleAvatar(
                                      radius: screenWidth * 0.04,
                                      backgroundColor: Colors.orange.shade100,
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.orange.shade800,
                                        size: screenWidth * 0.04,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Halo, Selamat ${_getGreeting()} 👋",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: screenWidth * 0.035,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: screenHeight * 0.004),
                            Text(
                              _userName ?? "Pengguna",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: screenWidth * 0.048,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _buildCompactWalletAndLocation(screenWidth),
                      SizedBox(height: screenHeight * 0.01),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColoredHeaderIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String tooltip = '',
    required double iconSize,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: EdgeInsets.all(iconSize * 0.25),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Icon(icon, color: color, size: iconSize),
        ),
      ),
    );
  }

  // --- This widget is now placed inside the SliverAppBar's main Column ---
  Widget _buildCompactWalletAndLocation(double screenWidth) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          _buildInfoCard(
            icon: Icons.location_on,
            iconColor: Colors.tealAccent,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child:
                  _isLoadingLocation
                      ? Text(
                        "Memuat lokasi...",
                        key: const ValueKey<String>('loading_location_compact'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: screenWidth * 0.03, // Resized
                          fontStyle: FontStyle.italic,
                        ),
                      )
                      : Text(
                        _currentLocation,
                        key: ValueKey<String>(_currentLocation),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: screenWidth * 0.03, // Resized
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
            ),
            onTap: _initializeLocation,
            screenWidth: screenWidth,
          ),
          SizedBox(height: screenWidth * 0.02),
          // This card was also resized and simplified
          _buildInfoCard(
            icon: Icons.account_balance_wallet,
            iconColor: Colors.deepPurpleAccent,
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggleBalanceVisibility,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (
                      Widget child,
                      Animation<double> animation,
                    ) {
                      return SizeTransition(
                        sizeFactor: animation,
                        axisAlignment: 0.0,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: Text(
                      _isBalanceHidden
                          ? "Rp •••••••"
                          : (_xpayBalance ??
                              'Memuat...'), // Fallback for _xpayBalance
                      key: ValueKey<bool>(_isBalanceHidden),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: screenWidth * 0.035, // Resized
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: screenWidth * 0.02),
                InkWell(
                  onTap: _toggleBalanceVisibility,
                  borderRadius: BorderRadius.circular(screenWidth * 0.05),
                  child: Icon(
                    _isBalanceHidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: screenWidth * 0.04, // Resized
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
            actions: [
              _buildCompactWalletAction(
                icon: Icons.add_circle_outline,
                onTap: () => context.push('/xpaytopup'),
                tooltip: 'Top Up',
                iconColor: Colors.lightGreenAccent,
                screenWidth: screenWidth,
              ),
              SizedBox(width: screenWidth * 0.025),
              _buildCompactWalletAction(
                icon: Icons.history_toggle_off_outlined,
                onTap: () => context.push('/history'),
                tooltip: 'Riwayat',
                iconColor: Colors.amberAccent,
                screenWidth: screenWidth,
              ),
              SizedBox(width: screenWidth * 0.025),
              _buildCompactWalletAction(
                icon: Icons.settings_outlined,
                onTap: () => context.push('/users/profile'),
                tooltip: 'Setelan',
                iconColor: Colors.cyanAccent,
                screenWidth: screenWidth,
              ),
            ],
            screenWidth: screenWidth,
          ),
        ],
      ),
    );
  }

  // Refactored common card style for location and wallet
  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required Widget child,
    VoidCallback? onTap,
    List<Widget>? actions,
    required double screenWidth,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.03,
          vertical: screenWidth * 0.02,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(screenWidth * 0.03),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor,
              size: screenWidth * 0.04, // Resized
            ),
            SizedBox(width: screenWidth * 0.02),
            Expanded(child: child),
            if (actions != null) Row(children: actions),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactWalletAction({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    required Color iconColor,
    required double screenWidth,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: EdgeInsets.all(screenWidth * 0.012),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(screenWidth * 0.02),
            border: Border.all(color: iconColor.withOpacity(0.4)),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: screenWidth * 0.038, // Resized
          ),
        ),
      ),
    );
  }

  // =======================================================================
  // === SERVICE WIDGETS REFACTOR
  // =======================================================================
  // All service widgets, quick actions, and banners have been resized
  // for a more compact and balanced look.
  // =======================================================================
  Widget _buildMainServices(double screenWidth) {
    bool isDriver = _userRole == 'driver'; // Check user role here

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenWidth * 0.03,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Layanan Utama",
            style: TextStyle(
              fontSize: screenWidth * 0.04, // Resized
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
          SizedBox(height: screenWidth * 0.03), // Adjusted spacing
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            crossAxisSpacing: screenWidth * 0.03, // Adjusted spacing
            mainAxisSpacing: screenWidth * 0.03, // Adjusted spacing
            childAspectRatio: 1.9, // Adjusted aspect ratio
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildPrimaryServiceCard(
                title: 'LhokRide',
                subtitle:
                    isDriver
                        ? 'Khusus Pelanggan'
                        : 'Transportasi Aman', // Change subtitle for drivers
                icon: Icons.two_wheeler_outlined,
                gradient: const LinearGradient(
                  colors: [Color(0xFF66BB6A), Color(0xFF388E3C)],
                ),
                onTap:
                    isDriver
                        ? () => _showDriverRestrictionSnackBar()
                        : () => context.push('/Lhokride'),
                enabled: !isDriver, // Pass enabled state
                screenWidth: screenWidth,
              ),
              _buildPrimaryServiceCard(
                title: 'LhokFood',
                subtitle:
                    isDriver
                        ? 'Khusus Pelanggan'
                        : 'Kuliner Pilihan', // Change subtitle for drivers
                icon: Icons.restaurant_menu_outlined,
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF5350), Color(0xFFC62828)],
                ),
                onTap:
                    isDriver
                        ? () => _showDriverRestrictionSnackBar()
                        : () => context.push('/Lhokfood'),
                enabled: !isDriver, // Pass enabled state
                screenWidth: screenWidth,
              ),
            ],
          ),
          SizedBox(height: screenWidth * 0.05),
          Text(
            "Segera Hadir", // Changed from "Comming Soon"
            style: TextStyle(
              fontSize: screenWidth * 0.038, // Resized
              fontWeight: FontWeight.w600,
              color: primaryTextColor,
            ),
          ),
          SizedBox(height: screenWidth * 0.03), // Adjusted spacing
          Row(
            children: [
              Expanded(
                child: _buildSecondaryServiceChip(
                  title: 'LhokSend',
                  icon: Icons.local_shipping_outlined,
                  onTap: () => _showComingSoonSnackBar('LhokSend'),
                  screenWidth: screenWidth,
                ),
              ),
              SizedBox(width: screenWidth * 0.03), // Adjusted spacing
              Expanded(
                child: _buildSecondaryServiceChip(
                  title: 'LhokMart',
                  icon: Icons.shopping_bag_outlined,
                  onTap: () => _showComingSoonSnackBar('LhokMart'),
                  screenWidth: screenWidth,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryServiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
    required double screenWidth,
    bool enabled = true, // New parameter for enabling/disabling card
  }) {
    return InkWell(
      onTap:
          enabled
              ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
              : null, // Disable tap if not enabled
      borderRadius: BorderRadius.circular(screenWidth * 0.035),
      child: Container(
        padding: EdgeInsets.all(screenWidth * 0.03),
        decoration: BoxDecoration(
          gradient:
              enabled
                  ? gradient
                  : LinearGradient(
                    colors: [Colors.grey.shade400, Colors.grey.shade600],
                  ), // Grey out if disabled
          borderRadius: BorderRadius.circular(screenWidth * 0.035),
          boxShadow: [
            BoxShadow(
              color: (enabled ? gradient.colors.last : Colors.grey.shade600)
                  .withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: EdgeInsets.all(screenWidth * 0.015),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(screenWidth * 0.02),
              ),
              child: Icon(
                icon,
                color: Colors.white.withOpacity(enabled ? 1.0 : 0.7),
                size: screenWidth * 0.045,
              ), // Dim icon if disabled
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(enabled ? 1.0 : 0.7),
                    fontSize: screenWidth * 0.036, // Resized
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: screenWidth * 0.005),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(
                      enabled ? 0.9 : 0.6,
                    ), // Dim subtitle if disabled
                    fontSize: screenWidth * 0.025, // Resized
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoonSnackBar(String serviceName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$serviceName akan segera tersedia!'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.orange.shade600,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSecondaryServiceChip({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    required double screenWidth,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(screenWidth * 0.03),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.035,
          vertical: screenWidth * 0.025,
        ), // Adjusted padding
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(screenWidth * 0.03),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: secondaryTextColor,
              size: screenWidth * 0.04,
            ), // Resized
            SizedBox(width: screenWidth * 0.02),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: secondaryTextColor,
                fontSize: screenWidth * 0.03, // Resized
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsTicker(double screenWidth) {
    return FutureBuilder<String?>(
      future: _getRunningTextFromPrefs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Placeholder for loading running text
          return Container(
            margin: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.04,
              vertical: screenWidth * 0.04,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.04,
              vertical: screenWidth * 0.03,
            ),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(screenWidth * 0.03),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.campaign_outlined,
                  color: Colors.blue.shade800,
                  size: screenWidth * 0.05,
                ),
                SizedBox(width: screenWidth * 0.03),
                Expanded(
                  child: SizedBox(
                    height: screenWidth * 0.05,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Memuat berita terkini...",
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.blue.shade800.withOpacity(0.7),
                          fontSize: screenWidth * 0.032,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        } else if (snapshot.hasError) {
          debugPrint('Error loading news ticker: ${snapshot.error}');
          return const SizedBox.shrink(); // Hide on error
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          debugPrint('News ticker data is empty or null.');
          return const SizedBox.shrink(); // Hide if no data
        }

        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.04,
            vertical: screenWidth * 0.04,
          ), // Added vertical margin
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.04,
            vertical: screenWidth * 0.03,
          ),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(screenWidth * 0.03),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(
                Icons.campaign_outlined,
                color: Colors.blue.shade800,
                size: screenWidth * 0.05, // Resized
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: SizedBox(
                  height: screenWidth * 0.05,
                  child: Marquee(
                    text: snapshot.data!,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.blue.shade800,
                      fontSize: screenWidth * 0.032, // Resized
                    ),
                    velocity: 35.0,
                    pauseAfterRound: const Duration(seconds: 4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // This widget was explicitly mentioned as being too large. It has been scaled down.
  Widget _buildQuickActions(double screenWidth) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenWidth * 0.04,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Akses Cepat",
            style: TextStyle(
              fontSize: screenWidth * 0.04, // Resized
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
          SizedBox(height: screenWidth * 0.03), // Adjusted spacing
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildQuickActionItem(
                icon: Icons.info_outline,
                label: "Informasi",
                color: Colors.purple.shade600,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => const WebviewPage(
                            url: 'https://lhokride.com/informasi',
                            Title: "Informasi",
                          ),
                    ),
                  );
                },
                screenWidth: screenWidth,
              ),
              SizedBox(width: screenWidth * 0.03),
              _buildQuickActionItem(
                icon: Icons.support_agent_outlined,
                label: "Bantuan",
                color: Colors.teal.shade600,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => const WebviewPage(
                            url: 'https://lhokride.com/docs',
                            Title: "Bantuan",
                          ),
                    ),
                  );
                },
                screenWidth: screenWidth,
              ),
              SizedBox(width: screenWidth * 0.03),
              _buildQuickActionItem(
                icon: Icons.card_giftcard_outlined,
                label: "Rewards",
                color: Colors.amber.shade700,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => const WebviewPage(
                            url: 'https://lhokride.com/rewards/',
                            Title: "Rewards",
                          ),
                    ),
                  );
                },
                screenWidth: screenWidth,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // This item has been significantly scaled down.
  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required double screenWidth,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(screenWidth * 0.03),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: screenWidth * 0.03,
          ), // Resized
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(screenWidth * 0.03),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(screenWidth * 0.025), // Resized
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(screenWidth * 0.025),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: screenWidth * 0.05,
                ), // Resized
              ),
              SizedBox(height: screenWidth * 0.02),
              Text(
                label,
                style: TextStyle(
                  fontSize: screenWidth * 0.028, // Resized
                  color: secondaryTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumPromotions(double screenWidth) {
    if (_premiumBanners.isEmpty) {
      debugPrint('No premium banners to display.');
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            screenWidth * 0.04,
            0,
            screenWidth * 0.04,
            screenWidth * 0.03,
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.02,
                  vertical: screenWidth * 0.01,
                ),
                decoration: BoxDecoration(
                  gradient: premiumGradient,
                  borderRadius: BorderRadius.circular(screenWidth * 0.015),
                ),
                child: Text(
                  "PREMIUM",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenWidth * 0.025, // Resized
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.025),
              Text(
                "Promo Eksklusif",
                style: TextStyle(
                  fontSize: screenWidth * 0.04, // Resized
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: screenWidth * 0.4, // Resized
          child: PageView.builder(
            key: const PageStorageKey<String>('premium_banners_content'),
            controller: _premiumPromotionsBannerController,
            itemCount: _premiumBanners.length,
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) {
              if (_currentPremiumPromotionsBannerIndex != index) {
                setState(() {
                  _currentPremiumPromotionsBannerIndex = index;
                });
              }
            },
            itemBuilder: (context, index) {
              final banner = _premiumBanners[index];
              return Container(
                margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (banner['url']?.isNotEmpty == true) {
                      // Safer null check
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => WebviewPage(
                                url: banner['url']!,
                                Title: 'Promo Premium',
                              ),
                        ),
                      );
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    child: CachedNetworkImage(
                      imageUrl: banner['image']!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder:
                          (context, url) => Container(
                            decoration: BoxDecoration(
                              gradient: premiumGradient,
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white.withOpacity(0.8),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            decoration: BoxDecoration(
                              gradient: premiumGradient,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white.withOpacity(0.7),
                                size: screenWidth * 0.1,
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: screenWidth * 0.04),
      ],
    );
  }

  Widget _buildElitePromotions(double screenWidth) {
    if (_eliteBanners.isEmpty) {
      debugPrint('No elite banners to display.');
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.02,
                  vertical: screenWidth * 0.01,
                ),
                decoration: BoxDecoration(
                  gradient: eliteGradient,
                  borderRadius: BorderRadius.circular(screenWidth * 0.015),
                ),
                child: Text(
                  "ELITE",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenWidth * 0.025, // Resized
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.025),
              Text(
                "Penawaran Terbaik",
                style: TextStyle(
                  fontSize: screenWidth * 0.04, // Resized
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: screenWidth * 0.03),
        SizedBox(
          height: screenWidth * 0.45, // Resized
          child: PageView.builder(
            key: const PageStorageKey<String>('elite_banners_content'),
            controller: _eliteBannerController,
            itemCount: _eliteBanners.length,
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) {
              if (_currentEliteBannerIndex != index) {
                setState(() {
                  _currentEliteBannerIndex = index;
                });
              }
            },
            itemBuilder: (context, index) {
              final banner = _eliteBanners[index];
              return Container(
                margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (banner['url'] != null && banner['url']!.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => WebviewPage(
                                url: banner['url']!,
                                Title: "Penawaran Elite",
                              ),
                        ),
                      );
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    child: CachedNetworkImage(
                      imageUrl: banner['image']!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder:
                          (context, url) => Container(
                            decoration: BoxDecoration(gradient: eliteGradient),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            decoration: BoxDecoration(gradient: eliteGradient),
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white,
                                size: screenWidth * 0.1,
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: screenWidth * 0.04),
      ],
    );
  }

  Widget _buildRecentActivity(double screenWidth) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Tentang LhokRide",
            style: TextStyle(
              fontSize: screenWidth * 0.04, // Resized
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
          SizedBox(height: screenWidth * 0.03),
          Container(
            padding: EdgeInsets.all(screenWidth * 0.04),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(screenWidth * 0.03),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "LhokRide adalah aplikasi transportasi lokal yang memudahkan Anda untuk bepergian dengan cepat dan aman di wilayah Lhokseumawe. Kami berkomitmen untuk menyediakan layanan terbaik bagi pengguna kami.",
                  style: TextStyle(
                    fontSize: screenWidth * 0.032, // Resized
                    height: 1.6,
                    color: secondaryTextColor,
                  ),
                ),
                SizedBox(height: screenWidth * 0.04),
                Text(
                  "Fitur Unggulan:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: screenWidth * 0.035, // Resized
                    color: primaryTextColor,
                  ),
                ),
                SizedBox(height: screenWidth * 0.02),
                _FeatureBullet(
                  text:
                      "Pesan ojek, mobil, atau layanan pengiriman barang dengan mudah lewat aplikasi.",
                  screenWidth: screenWidth,
                ),
                _FeatureBullet(
                  text: "Pembayaran digital yang aman dan cepat melalui XPays.",
                  screenWidth: screenWidth,
                ),
                _FeatureBullet(
                  text:
                      "Riwayat perjalanan dan transaksi top up tersimpan otomatis untuk kemudahan pelacakan.",
                  screenWidth: screenWidth,
                ),
                _FeatureBullet(
                  text:
                      "Promo dan penawaran eksklusif untuk pengguna setia kami.",
                  screenWidth: screenWidth,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Widget kustom untuk bullet fitur
class _FeatureBullet extends StatelessWidget {
  final String text;
  final double screenWidth;

  const _FeatureBullet({
    Key? key,
    required this.text,
    required this.screenWidth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: screenWidth * 0.01),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: screenWidth * 0.04, // Resized
            color: Colors.green.shade600,
          ),
          SizedBox(width: screenWidth * 0.02),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: screenWidth * 0.03, // Resized
                color: secondaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
