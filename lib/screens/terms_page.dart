import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../widgets/bottom_navigation.dart'; // Sesuaikan path sesuai struktur proyek

class TermsAndConditionsPage extends StatefulWidget {
  const TermsAndConditionsPage({Key? key}) : super(key: key);

  @override
  State<TermsAndConditionsPage> createState() => _TermsAndConditionsPageState();
}

class _TermsAndConditionsPageState extends State<TermsAndConditionsPage>
    with TickerProviderStateMixin {
  String _userRole = 'guest';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final role = await _storage.read(key: 'role');
    if (mounted) {
      setState(() {
        _userRole = role ?? 'guest';
      });
    }
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
      return false; // Jangan keluar dulu
    }
    return true; // Keluar dari aplikasi
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop, // <- pasang di sini
      child: PageWithBottomNav(
        activeTab: 'terms',
        userRole: _userRole,
        child: Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: CustomScrollView(
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      _buildHeader(),
                      _buildContent(),
                      _buildLastUpdated(),
                      const SizedBox(height: 100),
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

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 220,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFFFF8C00),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => context.go('/'),
      ),
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'Syarat & Ketentuan',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF8C00), Color(0xFFFF6B35), Color(0xFFFF4500)],
            ),
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                right: -80,
                top: -80,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              Positioned(
                right: -40,
                top: 40,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
              Positioned(
                left: -60,
                bottom: -60,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),
              // Main icon
              const Positioned(
                bottom: 70,
                left: 20,
                child: Icon(
                  Icons.article_rounded,
                  color: Colors.white,
                  size: 50,
                ),
              ),
              // Status badge
              Positioned(
                bottom: 70,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Telah Disetujui',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.withOpacity(0.1),
                  Colors.orange.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Colors.orange,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Selamat Datang di LHOKRIDE+',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Kamu telah menyetujui ketentuan ini saat mendaftar.\nBerikut adalah ringkasan syarat dan ketentuan yang berlaku.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final terms = [
      {
        'icon': Icons.person_add_alt_1_rounded,
        'title': 'Pendaftaran Akun',
        'content':
            'Setiap pengguna wajib mendaftarkan akun dengan informasi yang valid dan akurat. Data yang Kamu berikan akan digunakan untuk memberikan layanan terbaik dan memastikan keamanan dalam setiap transaksi.',
        'color': const Color(0xFF4CAF50),
      },
      {
        'icon': Icons.security_rounded,
        'title': 'Keamanan & Tanggung Jawab',
        'content':
            'Pengguna bertanggung jawab penuh atas keamanan akun dan semua aktivitas yang dilakukan. Jangan bagikan informasi login kepada pihak lain dan segera laporkan jika terjadi aktivitas mencurigakan.',
        'color': const Color(0xFF2196F3),
      },
      {
        'icon': Icons.payments_rounded,
        'title': 'Pembayaran & Tarif',
        'content':
            'Tarif dihitung berdasarkan jarak tempuh, waktu perjalanan, dan kondisi lalu lintas. Pembayaran dapat dilakukan melalui berbagai metode yang tersedia dengan jaminan keamanan transaksi.',
        'color': const Color(0xFFFF9800),
      },
      {
        'icon': Icons.privacy_tip_rounded,
        'title': 'Perlindungan Data Pribadi',
        'content':
            'Kami berkomitmen melindungi privasi Kamu. Semua data pribadi akan dikelola sesuai stKamur keamanan tinggi dan hanya digunakan untuk keperluan layanan sesuai kebijakan privasi.',
        'color': const Color(0xFF9C27B0),
      },
      {
        'icon': Icons.update_rounded,
        'title': 'Pembaruan Ketentuan',
        'content':
            'Ketentuan dapat diperbarui sewaktu-waktu untuk penyesuaian layanan. Pengguna akan diberitahu melalui aplikasi atau nomor wa terdaftar mengenai setiap perubahan penting.',
        'color': const Color(0xFF607D8B),
      },
      {
        'icon': Icons.support_agent_rounded,
        'title': 'Dukungan Pelanggan',
        'content':
            'Tim dukungan kami siap membantu 24/7. Hubungi kami melalui email support@lhokride.com atau fitur live chat di aplikasi untuk bantuan dan pertanyaan apapun.',
        'color': const Color(0xFFE91E63),
      },
    ];

    return Column(
      children:
          terms.asMap().entries.map((entry) {
            int index = entry.key;
            Map<String, dynamic> term = entry.value;

            return AnimatedContainer(
              duration: Duration(milliseconds: 200 + (index * 100)),
              child: _buildTermCard(
                icon: term['icon'] as IconData,
                title: term['title'] as String,
                content: term['content'] as String,
                color: term['color'] as Color,
              ),
            );
          }).toList(),
    );
  }

  Widget _buildTermCard({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ExpansionTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.6,
                ),
                textAlign: TextAlign.justify,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Colors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Terakhir Diperbarui',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Aktif',
              style: TextStyle(
                color: Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
