import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({Key? key}) : super(key: key);

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<OnboardingItem> _onboardingItems = [
    OnboardingItem(
      title: 'Selamat Datang di LhokRide',
      description: 'Nikmati perjalanan yang nyaman dan aman bersama kami di Lhokseumawe',
      imagePath: 'assets/images/onboarding_welcome.png',
      primaryColor: const Color(0xFFFF8C00),
      lightColor: const Color(0xFFFFF8E1),
      gradientColors: [const Color(0xFFE67E22), const Color(0xFFFF8C00)],
    ),
    // OnboardingItem(
    //   title: 'Layanan Terlengkap',
    //   description: 'Dari transportasi hingga kebutuhan sehari-hari, semua ada dalam genggaman',
    //   imagePath: 'assets/images/onboarding_services.png',
    // primaryColor: const Color(0xFFFFA726),
    //   lightColor: const Color(0xFFFFF8E1),
    //   gradientColors: [const Color(0xFFFFA726), const Color(0xFFFFB74D)],
    // ),
    // OnboardingItem(
    //   title: 'Didukung Pemerintah Kota',
    //   description: 'Bekerja sama dengan Pemerintah Kota Lhokseumawe untuk kemajuan bersama',
    //   imagePath: 'assets/images/logo_lhokseumawe.png',
    //   primaryColor: const Color(0xFFFFA726),
    //   lightColor: const Color(0xFFFFF8E1),
    //   gradientColors: [const Color(0xFFFFA726), const Color(0xFFFFB74D)],
    // ),
    // OnboardingItem(
    //   title: 'Bank Aceh Syariah',
    //   description: 'Transaksi mudah dan aman dengan dukungan perbankan syariah terpercaya',
    //   imagePath: 'assets/images/bank_aceh_logo.png',
    // primaryColor: const Color(0xFFFFA726),
    //   lightColor: const Color(0xFFFFF8E1),
    //   gradientColors: [const Color(0xFFFFA726), const Color(0xFFFFB74D)],
    // ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOutCubic),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _onboardingItems[_currentPage].lightColor,
              Colors.white,
              _onboardingItems[_currentPage].lightColor.withOpacity(0.3),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, isTablet),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                    _fadeController.reset();
                    _slideController.reset();
                    _fadeController.forward();
                    _slideController.forward();
                  },
                  itemCount: _onboardingItems.length,
                  itemBuilder: (context, index) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: _buildOnboardingSlide(context, index, isTablet),
                      ),
                    );
                  },
                ),
              ),
              _buildBottomSection(context, isTablet),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Padding(
      padding: EdgeInsets.all(isTablet ? 32.0 : 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo or Brand
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              'LhokRide+',
              style: TextStyle(
                fontSize: isTablet ? 18 : 16,
                fontWeight: FontWeight.w700,
                color: _onboardingItems[_currentPage].primaryColor,
              ),
            ),
          ),
          // Skip Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextButton(
              onPressed: _goToAuth,
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 24 : 20,
                  vertical: isTablet ? 12 : 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(
                'Lewati',
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingSlide(BuildContext context, int index, bool isTablet) {
    final item = _onboardingItems[index];

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 60.0 : 24.0,
        vertical: 20.0,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Main Content Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 0),
            padding: EdgeInsets.all(isTablet ? 40 : 30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  item.lightColor.withOpacity(0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: item.primaryColor.withOpacity(0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: _buildSlideContent(index, item, isTablet),
          ),
          SizedBox(height: isTablet ? 48 : 40),
          
          // Title with gradient text
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: item.gradientColors,
            ).createShader(bounds),
            child: Text(
              item.title,
              style: TextStyle(
                fontSize: isTablet ? 32 : 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.2,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: isTablet ? 20 : 16),
          
          // Description
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              item.description,
              style: TextStyle(
                fontSize: isTablet ? 18 : 16,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade600,
                height: 1.6,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlideContent(int index, OnboardingItem item, bool isTablet) {
    switch (index) {
      case 0:
        return _buildWelcomeContent(item, isTablet);
      // case 1:
      //   return _buildServicesContent(isTablet);
      // case 2:
      //   return _buildSponsorImageContent(item.imagePath, isTablet, 'Pemerintah Kota Lhokseumawe', item);
      // case 3:
      //   return _buildSponsorImageContent(item.imagePath, isTablet, 'Bank Aceh Syariah', item);
      default:
        return const SizedBox();
    }
  }

  Widget _buildWelcomeContent(OnboardingItem item, bool isTablet) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: isTablet ? 140 : 120,
          height: isTablet ? 140 : 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: item.gradientColors,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: item.primaryColor.withOpacity(0.4),
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            Icons.waving_hand_rounded,
            size: isTablet ? 70 : 60,
            color: Colors.white,
          ),
        ),
        SizedBox(height: isTablet ? 24 : 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: item.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: item.primaryColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Text(
            'Aplikasi Andalanmu',
            style: TextStyle(
              fontSize: isTablet ? 20 : 18,
              fontWeight: FontWeight.w700,
              color: item.primaryColor,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServicesContent(bool isTablet) {
    final services = [
      {'icon': Icons.directions_bike_rounded, 'label': 'LhokRide', 'color': const Color(0xFF3B82F6)},
      {'icon': Icons.restaurant_rounded, 'label': 'LhokFood', 'color': const Color(0xFF10B981)},
      {'icon': Icons.shopping_cart_rounded, 'label': 'LhokMart', 'color': const Color(0xFF8B5CF6)},
      {'icon': Icons.local_shipping_rounded, 'label': 'LhokSend', 'color': const Color(0xFFEF4444)},
    ];

    return Center(
      child: Wrap(
        spacing: isTablet ? 20 : 16,
        runSpacing: isTablet ? 20 : 16,
        alignment: WrapAlignment.center,
        children: services.map((service) {
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 800 + services.indexOf(service) * 100),
            tween: Tween(begin: 0.0, end: 1.0),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: _buildServiceCard(
                  icon: service['icon'] as IconData,
                  label: service['label'] as String,
                  color: service['color'] as Color,
                  isTablet: isTablet,
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildServiceCard({
    required IconData icon,
    required String label,
    required Color color,
    required bool isTablet,
  }) {
    final size = isTablet ? 110.0 : 90.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            color.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: color.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: isTablet ? 56 : 48,
            height: isTablet ? 56 : 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withOpacity(0.8)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: isTablet ? 32 : 28,
              color: Colors.white,
            ),
          ),
          SizedBox(height: isTablet ? 12 : 10),
          Text(
            label,
            style: TextStyle(
              fontSize: isTablet ? 14 : 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSponsorImageContent(String assetPath, bool isTablet, String sponsorName, OnboardingItem item) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 40.0 : 20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: item.primaryColor.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Image.asset(
              assetPath,
              height: isTablet ? 180 : 140,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: isTablet ? 180 : 140,
                  height: isTablet ? 180 : 140,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: item.gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.business_rounded,
                    size: isTablet ? 80 : 60,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
          SizedBox(height: isTablet ? 28 : 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: item.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: item.primaryColor.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Text(
              sponsorName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isTablet ? 18 : 16,
                fontWeight: FontWeight.w700,
                color: item.primaryColor,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 32.0 : 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPageIndicators(isTablet),
          SizedBox(height: isTablet ? 32 : 24),
          _buildActionButtons(context, isTablet),
        ],
      ),
    );
  }

  Widget _buildPageIndicators(bool isTablet) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _onboardingItems.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: _currentPage == index ? (isTablet ? 40 : 32) : 10,
          height: 10,
          decoration: BoxDecoration(
            gradient: _currentPage == index
                ? LinearGradient(colors: _onboardingItems[_currentPage].gradientColors)
                : null,
            color: _currentPage != index ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(5),
            boxShadow: _currentPage == index
                ? [
                    BoxShadow(
                      color: _onboardingItems[_currentPage].primaryColor.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, bool isTablet) {
    final buttonHeight = isTablet ? 64.0 : 56.0;
    final fontSize = isTablet ? 18.0 : 16.0;

    return Column(
      children: [
        Container(
          width: double.infinity,
          height: buttonHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _onboardingItems[_currentPage].gradientColors,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _onboardingItems[_currentPage].primaryColor.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: () {
              if (_currentPage == _onboardingItems.length - 1) {
                _goToAuth();
              } else {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _currentPage == _onboardingItems.length - 1
                      ? 'Mulai Sekarang'
                      : 'Lanjutkan',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _currentPage == _onboardingItems.length - 1
                      ? Icons.rocket_launch_rounded
                      : Icons.arrow_forward_rounded,
                  size: fontSize + 2,
                ),
              ],
            ),
          ),
        ),
        if (_currentPage > 0) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: buttonHeight * 0.85,
            child: TextButton(
              onPressed: () {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                backgroundColor: Colors.white.withOpacity(0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: fontSize,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Kembali',
                    style: TextStyle(
                      fontSize: fontSize * 0.9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _goToAuth() {
    context.go('/auth');
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pageController.dispose();
    super.dispose();
  }
}

class OnboardingItem {
  final String title;
  final String description;
  final String imagePath;
  final Color primaryColor;
  final Color lightColor;
  final List<Color> gradientColors;

  OnboardingItem({
    required this.title,
    required this.description,
    required this.imagePath,
    required this.primaryColor,
    required this.lightColor,
    required this.gradientColors,
  });
}