import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:shared_preferences/shared_preferences.dart';
// Model
import 'package:lhokride/models/partner.dart';
// Utils
import 'package:intl/intl.dart'; // Format mata uang

// Import halaman detail
import 'DetailsMerchant.dart';

class LhokfoodPage extends StatefulWidget {
  const LhokfoodPage({super.key});

  @override
  State<LhokfoodPage> createState() => _LhokfoodPageState();
}

class _LhokfoodPageState extends State<LhokfoodPage> {
  String _searchQuery = '';
  List<Partner> _umkmPartners = [];
  bool _isLoading = true;
  String _errorMessage = '';
  late Box<Partner> _partnersBox;
  late Box _appMetadataBox;
  final String _baseUrl = 'http://api.lhokride.com/api/mitratoko/';
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  Position? _currentPosition;
  bool _locationPermissionGranted = false;
  bool? _isOpen; // null artinya belum dicek

  // Color scheme
  static const Color primaryOrange = Color(0xFFFF8C00);
  static const Color lightOrange = Color(0xFFFFB84D);
  static const Color darkOrange = Color(0xFFE67E00);
  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _partnersBox = Hive.box<Partner>('partnersBox');
    _appMetadataBox = Hive.box('appMetadata');
    _getCurrentLocation();
    _loadPartners();
    _loadServiceStatus();
  }

  void _loadServiceStatus() async {
    final isOpen = await _isServiceAvailable();
    setState(() {
      _isOpen = isOpen;
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _locationPermissionGranted = true;
        setState(() {});
      }
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  String _getDistanceText(Partner partner) {
    if (_currentPosition == null || !_locationPermissionGranted) {
      return 'Lokasi tidak tersedia';
    }

    double distance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      partner.latitude,
      partner.longitude,
    );

    if (distance < 1) {
      return '${(distance * 1000).round()} m';
    } else {
      return '${distance.toStringAsFixed(1)} km';
    }
  }

  Future<bool> _isServiceAvailable() async {
    final prefs = await SharedPreferences.getInstance();
    final openStr = prefs.getString('service_open') ?? '06:00:00';
    final closeStr = prefs.getString('service_close') ?? '23:00:00';

    // Parsing jam dan menit dari format HH:mm:ss
    final openParts = openStr.split(':');
    final closeParts = closeStr.split(':');

    final openHour = int.parse(openParts[0]);
    final openMinute = int.parse(openParts[1]);
    final closeHour = int.parse(closeParts[0]);
    final closeMinute = int.parse(closeParts[1]);

    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final openMinutes = openHour * 60 + openMinute;
    final closeMinutes = closeHour * 60 + closeMinute;

    return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
  }

  String _getPriceRange(Partner partner) {
    if (partner.menu.isEmpty) return 'Menu tidak tersedia';

    final prices = partner.menu.map((menu) => menu.price).toList();
    prices.sort();

    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    if (prices.length == 1) {
      return formatter.format(prices.first);
    } else {
      return '${formatter.format(prices.first)} - ${formatter.format(prices.last)}';
    }
  }

  Future<void> _loadPartners() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (_partnersBox.isNotEmpty) {
        _umkmPartners = _partnersBox.values.toList();
        setState(() => _isLoading = false);
        _checkForUpdatesInBackground();
      } else {
        await _fetchDataFromServer();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Terjadi kesalahan saat memuat data';
        _isLoading = false;
      });
    }
  }

  Future<void> _checkForUpdatesInBackground() async {
    try {
      final String? lastFetchTimestampStr = _appMetadataBox.get(
        'lastFetchTimestamp',
      );
      const Duration cacheDuration = Duration(hours: 1);

      if (lastFetchTimestampStr != null) {
        final DateTime lastFetched = DateTime.parse(lastFetchTimestampStr);
        if (DateTime.now().difference(lastFetched) > cacheDuration) {
          await _fetchDataFromServer();
        }
      } else {
        await _fetchDataFromServer();
      }
    } catch (e) {
      // Silent failure for background updates
    }
  }

  Future<void> _fetchDataFromServer() async {
    if (_umkmPartners.isEmpty || !_isLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final response = await http
          .get(
            Uri.parse('${_baseUrl}toko'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final fetchedPartners =
            data.map((json) => Partner.fromJson(json)).toList();

        await _partnersBox.clear();
        for (var partner in fetchedPartners) {
          await _partnersBox.put(partner.id, partner);
        }
        await _appMetadataBox.put(
          'lastFetchTimestamp',
          DateTime.now().toIso8601String(),
        );

        setState(() {
          _umkmPartners = fetchedPartners;
          _isLoading = false;
        });
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Tidak dapat terhubung ke server. Periksa koneksi internet Kamu.';
        _isLoading = false;
      });
      _showSnackBar('Koneksi bermasalah', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                color == Colors.red ? Icons.error_outline : Icons.check_circle,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  List<Partner> get filteredPartners {
    if (_searchQuery.isEmpty) return _umkmPartners;
    final query = _searchQuery.toLowerCase();
    return _umkmPartners
        .where(
          (p) =>
              p.namaToko.toLowerCase().contains(query) ||
              (p.alamat?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = query);
    });
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryOrange, lightOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Selamat datang di Lhokfood!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Temukan makanan lezat dari ${_umkmPartners.length} toko partner kami',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isOpen == null
                      ? Icons
                          .hourglass_top // saat memuat
                      : _isOpen!
                      ? Icons
                          .access_time // layanan buka
                      : Icons.access_time_filled, // layanan tutup
                  color: _isOpen == true ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _isOpen == null
                      ? 'Memeriksa layanan...'
                      : _isOpen!
                      ? 'Layanan Lhokfood tersedia'
                      : 'Layanan Lhokfood tutup Saat Ini',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Cari toko atau alamat...',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.search, color: primaryOrange),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                  : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPartnerCard(Partner partner) {
    final isServiceTime = _isServiceAvailable();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border:
            _isOpen == null || _isOpen == true
                ? null
                : Border.all(color: Colors.grey.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          InkWell(
            onTap:
                _isOpen == null || _isOpen == true
                    ? () => context.push('/partnerDetail', extra: partner)
                    : null,
            borderRadius: BorderRadius.circular(16),
            child: Opacity(
              opacity: _isOpen == null || _isOpen == true ? 1.0 : 0.6,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image on the left
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey[100],
                            child:
                                partner.fotoToko != null &&
                                        partner.fotoToko!.isNotEmpty
                                    ? partner.fotoToko != null
                                        ? CachedNetworkImage(
                                          imageUrl: partner.fotoToko!,
                                          fit: BoxFit.cover,
                                          placeholder:
                                              (context, url) =>
                                                  _buildImagePlaceholder(),
                                          errorWidget:
                                              (context, url, error) =>
                                                  _buildImagePlaceholder(),
                                        )
                                        : _buildImagePlaceholder()
                                    : _buildImagePlaceholder(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Content on the right
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                partner.namaToko ?? 'Nama Toko Tidak Tersedia',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: primaryOrange,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      partner.alamat ?? 'Alamat tidak tersedia',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.near_me,
                                    size: 14,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getDistanceText(partner),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Info row
                    Row(
                      children: [
                        // Menu count
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: lightOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: lightOrange.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.restaurant_menu,
                                size: 12,
                                color: darkOrange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${partner.menu.length} Menu',
                                style: const TextStyle(
                                  color: darkOrange,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Price range
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              _getPriceRange(partner),
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient:
                                _isOpen == null || _isOpen == true
                                    ? const LinearGradient(
                                      colors: [primaryOrange, lightOrange],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    )
                                    : LinearGradient(
                                      colors: [
                                        Colors.grey.shade400,
                                        Colors.grey.shade500,
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _isOpen == null || _isOpen == true
                                ? 'Lihat Menu'
                                : 'Tutup',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isOpen != true)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'TUTUP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: 80,
      height: 80,
      color: Colors.grey[200],
      child: const Icon(Icons.restaurant, size: 30, color: Colors.grey),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: lightOrange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Icon(
            Icons.restaurant_menu,
            size: 60,
            color: primaryOrange,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Toko tidak ditemukan',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Coba gunakan kata kunci lain',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 100), // Add extra space at bottom
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Icon(Icons.error_outline, size: 60, color: Colors.red),
        ),
        const SizedBox(height: 20),
        const Text(
          'Oops! Terjadi Kesalahan',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _errorMessage,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          onPressed: _fetchDataFromServer,
          icon: const Icon(Icons.refresh),
          label: const Text('Coba Lagi'),
        ),
        const SizedBox(height: 100), // Add extra space at bottom
      ],
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Lhokfood',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryOrange,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.push('/dashboard'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDataFromServer,
        color: primaryOrange,
        child: CustomScrollView(
          slivers: [
            // Header dengan welcome message
            SliverToBoxAdapter(child: _buildHeader()),
            // Search bar
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: const SizedBox(height: 16)),
            // Content area
            _isLoading
                ? SliverFillRemaining(
                  child: const Center(
                    child: CircularProgressIndicator(color: primaryOrange),
                  ),
                )
                : _errorMessage.isNotEmpty
                ? SliverFillRemaining(child: _buildErrorState())
                : filteredPartners.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState())
                : SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final partner = filteredPartners[index];
                    return _buildPartnerCard(partner);
                  }, childCount: filteredPartners.length),
                ),
            // Add extra space at the bottom
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
          ],
        ),
      ),
    );
  }
}
