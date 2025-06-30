import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:lhokride/models/partner.dart';
import 'package:lhokride/models/menu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PartnerDetailPage extends StatefulWidget {
  final Partner partner;

  const PartnerDetailPage({super.key, required this.partner});

  @override
  State<PartnerDetailPage> createState() => _PartnerDetailPageState();
}

class _PartnerDetailPageState extends State<PartnerDetailPage>
    with TickerProviderStateMixin {
  final Map<Menu, int> _cart = {};
  double _totalPrice = 0.0;
  int _totalItemsInCart = 0;
  double _userBalance =
      0.0; // Initialize to 0.0, it will be loaded from secure storage

  AnimationController? _fabAnimationController;
  Animation<double>? _fabScaleAnimation;

  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  // Color scheme
  static const Color primaryOrange = Color(0xFFFF8C00);
  static const Color lightOrange = Color(0xFFFFF3E0);
  static const Color darkOrange = Color(0xFFE67E00);
  static const Color greyText = Color(0xFF666666);
  static const Color lightGrey = Color(0xFFF5F5F5);

  final FlutterSecureStorage _secureStorage =
      const FlutterSecureStorage(); // Initialize secure storage here

  @override
  void initState() {
    super.initState();
    _loadUserBalance(); // Load balance when the page initializes
    _updateCartSummary();
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fabAnimationController!,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _fabAnimationController?.dispose();
    super.dispose();
  }

  // Load user balance from secure storage
  Future<void> _loadUserBalance() async {
    final String? balanceString = await _secureStorage.read(key: 'saldo');
    if (balanceString != null) {
      setState(() {
        _userBalance = double.tryParse(balanceString) ?? 0.0;
      });
    }
  }

  void _addItemToCart(Menu menu) {
    setState(() {
      if (_cart.containsKey(menu)) {
        _cart[menu] = _cart[menu]! + 1;
      } else {
        _cart[menu] = 1;
      }
      _updateCartSummary();
      _showEnhancedSnackBar(
        '${menu.name} ditambahkan!',
        Icons.check_circle,
        Colors.green,
      );
    });
  }

  void _removeItemFromCart(Menu menu) {
    setState(() {
      if (_cart.containsKey(menu)) {
        if (_cart[menu]! > 1) {
          _cart[menu] = _cart[menu]! - 1;
          _showEnhancedSnackBar(
            '${menu.name} dikurangi',
            Icons.remove_circle,
            Colors.orange,
          );
        } else {
          _cart.remove(menu);
          _showEnhancedSnackBar(
            '${menu.name} dihapus',
            Icons.delete,
            Colors.red,
          );
        }
      }
      _updateCartSummary();
    });
  }

  void _updateCartSummary() {
    _totalPrice = 0.0;
    _totalItemsInCart = 0;
    for (var entry in _cart.entries) {
      _totalPrice += entry.key.price * entry.value;
      _totalItemsInCart += entry.value;
    }

    // Animate FAB - hanya jalankan jika controller sudah diinisialisasi
    if (_fabAnimationController != null) {
      if (_totalItemsInCart > 0 && !_fabAnimationController!.isCompleted) {
        _fabAnimationController!.forward();
      } else if (_totalItemsInCart == 0 &&
          _fabAnimationController!.isCompleted) {
        _fabAnimationController!.reverse();
      }
    }
  }

  void _showEnhancedSnackBar(String message, IconData icon, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          backgroundColor: color,
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _showCartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            // Responsive height for bottom sheet
            final screenHeight = MediaQuery.of(context).size.height;
            return Container(
              height:
                  screenHeight *
                  0.75, // Adjust as needed, e.g., 75% of screen height
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(
                      top: 12,
                      bottom: 16,
                    ), // Slightly reduced margin
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                    ), // Reduced horizontal padding
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8), // Reduced padding
                          decoration: BoxDecoration(
                            color: lightOrange,
                            borderRadius: BorderRadius.circular(
                              10,
                            ), // Slightly smaller border radius
                          ),
                          child: const Icon(
                            Icons.shopping_cart,
                            color: primaryOrange,
                            size: 22,
                          ), // Slightly smaller icon
                        ),
                        const SizedBox(width: 10), // Reduced width
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Keranjang Belanja',
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  // Used titleMedium for a slightly smaller but still prominent header
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                '$_totalItemsInCart item dipilih',
                                style: TextStyle(
                                  color: greyText,
                                  fontSize: 13,
                                ), // Slightly smaller font size
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16), // Reduced height
                  // Cart items
                  Expanded(
                    child:
                        _cart.isEmpty
                            ? _buildEmptyCart()
                            : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ), // Reduced horizontal padding
                              itemCount: _cart.length,
                              itemBuilder: (context, index) {
                                final menu = _cart.keys.elementAt(index);
                                final quantity = _cart[menu]!;
                                return _buildCartItem(
                                  menu,
                                  quantity,
                                  modalSetState,
                                );
                              },
                            ),
                  ),

                  // Bottom section
                  if (_totalItemsInCart > 0)
                    _buildCartBottomSection(modalSetState),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24), // Reduced padding
            decoration: BoxDecoration(
              color: lightOrange,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 56, // Reduced icon size
              color: primaryOrange,
            ),
          ),
          const SizedBox(height: 20), // Reduced height
          Text(
            'Keranjang Masih Kosong',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              // Adjusted text theme
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6), // Reduced height
          Text(
            'Yuk pilih menu favorit kamu!',
            style: TextStyle(
              color: greyText,
              fontSize: 14,
            ), // Slightly smaller font size
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(Menu menu, int quantity, StateSetter modalSetState) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), // Reduced margin
      padding: const EdgeInsets.all(12), // Reduced padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12), // Reduced border radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              0.03,
            ), // Slightly less prominent shadow
            spreadRadius: 0,
            blurRadius: 8, // Reduced blur radius
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withOpacity(0.08),
        ), // Lighter border
      ),
      child: Row(
        children: [
          // Menu image
          ClipRRect(
            borderRadius: BorderRadius.circular(10), // Reduced border radius
            child: CachedNetworkImage(
              imageUrl: menu.image,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              placeholder:
                  (context, url) => Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: lightOrange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              errorWidget:
                  (context, url, error) => Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: lightOrange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.fastfood,
                      size: 28,
                      color: primaryOrange,
                    ),
                  ),
            ),
          ),

          const SizedBox(width: 12), // Reduced width
          // Menu details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  menu.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15, // Slightly reduced font size
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2), // Reduced height
                Text(
                  _currencyFormatter.format(menu.price),
                  style: const TextStyle(
                    color: primaryOrange,
                    fontWeight: FontWeight.bold,
                    fontSize: 14, // Slightly reduced font size
                  ),
                ),
                const SizedBox(height: 6), // Reduced height
                Text(
                  'Subtotal: ${_currencyFormatter.format(menu.price * quantity)}',
                  style: TextStyle(
                    color: greyText,
                    fontSize: 13, // Reduced font size
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Quantity controls
          Container(
            decoration: BoxDecoration(
              color: lightGrey,
              borderRadius: BorderRadius.circular(20), // Reduced border radius
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQuantityButton(
                  icon: Icons.remove,
                  onPressed: () {
                    modalSetState(() {
                      _removeItemFromCart(menu);
                    });
                  },
                  color: Colors.red,
                ),
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 30,
                  ), // Reduced minWidth
                  child: Text(
                    '$quantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15, // Reduced font size
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _buildQuantityButton(
                  icon: Icons.add,
                  onPressed: () {
                    modalSetState(() {
                      _addItemToCart(menu);
                    });
                  },
                  color: Colors.green,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(18), // Reduced border radius
      child: Container(
        padding: const EdgeInsets.all(6), // Reduced padding
        child: Icon(icon, color: color, size: 18), // Reduced icon size
      ),
    );
  }

  Widget _buildCartBottomSection(StateSetter modalSetState) {
    // The only condition to proceed is having items in the cart
    final bool canProceed = _totalItemsInCart > 0;

    return Container(
      padding: const EdgeInsets.all(16), // Reduced padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ), // Reduced border radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              0.08,
            ), // Slightly less prominent shadow
            spreadRadius: 0,
            blurRadius: 8, // Reduced blur radius
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Price breakdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Pembayaran', // This will now represent total price without delivery
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  // Adjusted text theme
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                _currencyFormatter.format(_totalPrice),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  // Adjusted text theme
                  fontWeight: FontWeight.bold,
                  color: primaryOrange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16), // Reduced height
          // Checkout button
          SizedBox(
            width: double.infinity,
            height: 50, // Slightly reduced height
            child: ElevatedButton(
              onPressed:
                  canProceed
                      ? () {
                        Navigator.pop(context); // Close the bottom sheet
                        _showLocationSelectionConfirmation();
                      }
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canProceed ? primaryOrange : Colors.grey[300],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    12,
                  ), // Reduced border radius
                ),
                elevation: canProceed ? 6 : 0, // Reduced elevation
                shadowColor: primaryOrange.withOpacity(0.2), // Lighter shadow
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 22,
                  ), // Icon changed to location
                  const SizedBox(width: 6), // Reduced width
                  Text(
                    canProceed
                        ? 'Pilih Lokasi Pengantaran'
                        : 'Keranjang Kosong', // Text changed
                    style: const TextStyle(
                      fontSize: 15, // Reduced font size
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLocationSelectionConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ), // Reduced border radius
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6), // Reduced padding
                decoration: BoxDecoration(
                  color: lightOrange,
                  borderRadius: BorderRadius.circular(
                    8,
                  ), // Reduced border radius
                ),
                child: const Icon(
                  Icons.location_on,
                  color: primaryOrange,
                  size: 22,
                ), // Icon changed
              ),
              const SizedBox(width: 10), // Reduced width
              const Expanded(
                child: Text(
                  'Konfirmasi Pesanan & Lokasi', // Title changed
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ), // Slightly reduced font size
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12), // Reduced padding
                decoration: BoxDecoration(
                  color: lightGrey,
                  borderRadius: BorderRadius.circular(
                    10,
                  ), // Reduced border radius
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Jumlah Item:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ), // Reduced font size
                        Text(
                          '$_totalItemsInCart item',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ), // Reduced font size
                      ],
                    ),
                    const SizedBox(height: 6), // Reduced height
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Harga Pesanan:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ), // Reduced font size
                        Text(
                          _currencyFormatter.format(_totalPrice),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primaryOrange,
                            fontSize: 14,
                          ), // Reduced font size
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12), // Reduced height
              const Text(
                'Anda akan diarahkan untuk memilih lokasi pengantaran Anda. Lanjutkan?', // Message changed
                style: TextStyle(
                  fontSize: 14,
                  color: greyText,
                ), // Reduced font size
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Batal',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ), // Reduced font size
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToMapForDelivery(); // New method for navigation
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ), // Reduced border radius
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ), // Reduced padding
              ),
              child: const Text(
                'Lanjutkan',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ), // Text changed
            ),
          ],
        );
      },
    );
  }

  void _navigateToMapForDelivery() {
    // navigasikan ke map dengan semua orderan dan data disini
    context.push(
      '/delivery_map',
      extra: {
        'partner': widget.partner,
        'cart': _cart,
        'totalPrice': _totalPrice,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: lightGrey,
      body: CustomScrollView(
        slivers: [
          // Custom App Bar with image
          SliverAppBar(
            expandedHeight:
                screenHeight *
                0.35, // Responsive height (e.g., 35% of screen height)
            pinned: true,
            backgroundColor: primaryOrange,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.partner.fotoToko,
                    fit: BoxFit.cover,
                    placeholder:
                        (context, url) => Container(
                          color: lightOrange,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: primaryOrange,
                            ),
                          ),
                        ),
                    errorWidget:
                        (context, url, error) => Container(
                          color: lightOrange,
                          child: const Icon(
                            Icons.store,
                            size: 70,
                            color: primaryOrange,
                          ),
                        ),
                  ),

                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.partner.namaToko,
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.partner.alamat,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
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
          ),
          SliverToBoxAdapter(
            // Wrap SizedBox with SliverToBoxAdapter
            child: const SizedBox(height: 8),
          ),
          // Content
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  // Store info section
                  _buildStoreInfoSection(),
                  const SizedBox(
                    height: 10,
                  ), // This should NOT be wrapped in SliverToBoxAdapter
                  // Menu section
                  _buildMenuSection(),
                  // --- START OF NEW FOOTER SECTION ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    color: const Color.fromARGB(255, 255, 255, 255),
                    child: Column(
                      children: [
                        Text(
                          'Aplikasi Lokal, Mendukung UMKM Lokal',
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(
                            color: const Color.fromARGB(255, 0, 0, 0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dengan setiap pesanan, Anda turut memajukan ekonomi lokal.',
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: const Color.fromARGB(179, 0, 0, 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // --- END OF NEW FOOTER SECTION ---
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation!,
        child:
            _totalItemsInCart > 0
                ? Container(
                  margin: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 12,
                  ),
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _showCartBottomSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 6,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Row(
                      children: [
                        // Left: Icon + Badge
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.shopping_cart, size: 22),
                            if (_totalItemsInCart > 0)
                              Positioned(
                                right: -6,
                                top: -6,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  child: Text(
                                    '$_totalItemsInCart',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        // Center: Flexible space with centered content
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currencyFormatter.format(_totalPrice),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'View My Cart',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Right: Arrow icon (optional)
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                )
                : null,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildStoreInfoSection() {
    return Container(
      margin: const EdgeInsets.all(16), // Reduced margins
      padding: const EdgeInsets.all(16), // Reduced padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // Reduced border radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04), // Lighter shadow
            spreadRadius: 0,
            blurRadius: 10, // Reduced blur radius
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6), // Reduced padding
                decoration: BoxDecoration(
                  color: lightOrange,
                  borderRadius: BorderRadius.circular(
                    6,
                  ), // Reduced border radius
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: primaryOrange,
                  size: 18,
                ), // Reduced icon size
              ),
              const SizedBox(width: 10), // Reduced width
              Text(
                'Tentang Toko',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  // Adjusted text theme
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12), // Reduced height
          Text(
            widget.partner.deskripsi.isNotEmpty
                ? widget.partner.deskripsi
                : 'Deskripsi toko tidak tersedia.',
            style: TextStyle(
              color: greyText,
              fontSize: 14, // Reduced font size
              height: 1.4,
            ),
          ),

          const SizedBox(height: 20), // Reduced height
          // Operating hours
          Container(
            padding: const EdgeInsets.all(12), // Reduced padding
            decoration: BoxDecoration(
              color: lightOrange.withOpacity(0.2), // Slightly less opaque
              borderRadius: BorderRadius.circular(10), // Reduced border radius
              border: Border.all(
                color: primaryOrange.withOpacity(0.2),
              ), // Lighter border
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time,
                  color: primaryOrange,
                  size: 20,
                ), // Reduced icon size
                const SizedBox(width: 10), // Reduced width
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Jam Operasional',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15, // Reduced font size
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2), // Reduced height
                      Text(
                        '${widget.partner.jamBuka ?? 'Tidak tersedia'} - ${widget.partner.jamTutup ?? 'Tidak tersedia'}',
                        style: const TextStyle(
                          color: primaryOrange,
                          fontSize: 14, // Reduced font size
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ), // Reduced padding
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(
                      18,
                    ), // Reduced border radius
                  ),
                  child: const Text(
                    'Buka',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11, // Reduced font size
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection() {
    return Container(
      color: lightGrey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16), // Reduced padding
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6), // Reduced padding
                  decoration: BoxDecoration(
                    color: lightOrange,
                    borderRadius: BorderRadius.circular(
                      6,
                    ), // Reduced border radius
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    color: primaryOrange,
                    size: 18,
                  ), // Reduced icon size
                ),
                const SizedBox(width: 10), // Reduced width
                Text(
                  'Menu Tersedia',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    // Adjusted text theme
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ), // Reduced padding
                  decoration: BoxDecoration(
                    color: primaryOrange.withOpacity(
                      0.08,
                    ), // Slightly less opaque
                    borderRadius: BorderRadius.circular(
                      18,
                    ), // Reduced border radius
                  ),
                  child: Text(
                    '${widget.partner.menu?.length ?? 0} Menu',
                    style: const TextStyle(
                      color: primaryOrange,
                      fontSize: 11, // Reduced font size
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (widget.partner.menu?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ), // Reduced horizontal padding
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.partner.menu!.length,
                separatorBuilder:
                    (context, index) =>
                        const SizedBox(height: 12), // Reduced height
                itemBuilder: (context, index) {
                  final menu = widget.partner.menu![index];
                  final int currentQuantity =
                      _cart.containsKey(menu) ? _cart[menu]! : 0;
                  return _buildMenuCard(menu, currentQuantity);
                },
              ),
            )
          else
            _buildEmptyMenu(),

          const SizedBox(height: 80), // Space for FAB, slightly reduced
        ],
      ),
    );
  }

  Widget _buildMenuCard(Menu menu, int currentQuantity) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // Reduced border radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04), // Lighter shadow
            spreadRadius: 0,
            blurRadius: 10, // Reduced blur radius
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12), // Reduced padding
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Menu image
            Hero(
              tag: 'menu_${menu.id ?? menu.name}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  12,
                ), // Reduced border radius

                child: CachedNetworkImage(
                  imageUrl: menu.image ?? '',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  placeholder:
                      (context, url) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              lightOrange,
                              primaryOrange.withOpacity(0.2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryOrange,
                          ),
                        ),
                      ),
                  errorWidget:
                      (context, url, error) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              lightOrange,
                              primaryOrange.withOpacity(0.2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.fastfood,
                          size: 32,
                          color: primaryOrange,
                        ),
                      ),
                ),
              ),
            ),

            const SizedBox(width: 12), // Reduced width
            // Menu details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    menu.name ?? 'Menu tidak tersedia',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16, // Reduced font size
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6), // Reduced height

                  if (menu.description?.isNotEmpty == true)
                    Text(
                      menu.description!,
                      style: TextStyle(
                        color: greyText,
                        fontSize: 13, // Reduced font size
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 10), // Reduced height
                  // Price and controls row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Price
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ), // Reduced padding
                        decoration: BoxDecoration(
                          color: primaryOrange.withOpacity(
                            0.08,
                          ), // Slightly less opaque
                          borderRadius: BorderRadius.circular(
                            18,
                          ), // Reduced border radius
                        ),
                        child: Text(
                          _currencyFormatter.format(menu.price ?? 0),
                          style: const TextStyle(
                            color: primaryOrange,
                            fontWeight: FontWeight.bold,
                            fontSize: 14, // Reduced font size
                          ),
                        ),
                      ),

                      // Quantity controls
                      currentQuantity > 0
                          ? Container(
                            decoration: BoxDecoration(
                              color: primaryOrange.withOpacity(
                                0.08,
                              ), // Slightly less opaque
                              borderRadius: BorderRadius.circular(
                                20,
                              ), // Reduced border radius
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildMenuQuantityButton(
                                  icon: Icons.remove,
                                  onPressed: () => _removeItemFromCart(menu),
                                  backgroundColor: Colors.red.withOpacity(
                                    0.08,
                                  ), // Lighter background
                                  iconColor: Colors.red,
                                ),
                                Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                  ), // Reduced minWidth
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ), // Reduced padding
                                  child: Text(
                                    '$currentQuantity',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 15, // Reduced font size
                                      fontWeight: FontWeight.bold,
                                      color: primaryOrange,
                                    ),
                                  ),
                                ),
                                _buildMenuQuantityButton(
                                  icon: Icons.add,
                                  onPressed: () => _addItemToCart(menu),
                                  backgroundColor: Colors.green.withOpacity(
                                    0.08,
                                  ), // Lighter background
                                  iconColor: Colors.green,
                                ),
                              ],
                            ),
                          )
                          : InkWell(
                            onTap: () => _addItemToCart(menu),
                            borderRadius: BorderRadius.circular(
                              20,
                            ), // Reduced border radius
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ), // Reduced padding
                              decoration: BoxDecoration(
                                color: primaryOrange,
                                borderRadius: BorderRadius.circular(
                                  20,
                                ), // Reduced border radius
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryOrange.withOpacity(
                                      0.2,
                                    ), // Lighter shadow
                                    spreadRadius: 0,
                                    blurRadius: 6, // Reduced blur radius
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 16,
                                  ), // Reduced icon size
                                  SizedBox(width: 4),
                                  Text(
                                    'Tambah',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13, // Reduced font size
                                    ),
                                  ),
                                ],
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

  Widget _buildMenuQuantityButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(18), // Reduced border radius
      child: Container(
        padding: const EdgeInsets.all(6), // Reduced padding
        margin: const EdgeInsets.all(3), // Reduced margin
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: iconColor, size: 16), // Reduced icon size
      ),
    );
  }

  Widget _buildEmptyMenu() {
    return Container(
      margin: const EdgeInsets.all(16), // Reduced margins
      padding: const EdgeInsets.all(32), // Reduced padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // Reduced border radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04), // Lighter shadow
            spreadRadius: 0,
            blurRadius: 10, // Reduced blur radius
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24), // Reduced padding
            decoration: BoxDecoration(
              color: lightOrange,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.restaurant_outlined,
              size: 56, // Reduced icon size
              color: primaryOrange,
            ),
          ),
          const SizedBox(height: 20), // Reduced height
          Text(
            'Menu Belum Tersedia',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              // Adjusted text theme
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6), // Reduced height
          Text(
            'Toko ini belum menambahkan menu. Silakan coba lagi nanti.',
            style: TextStyle(
              color: greyText,
              fontSize: 14, // Reduced font size
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
