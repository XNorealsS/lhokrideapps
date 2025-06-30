// lib/pages/OrderConfirmationPage.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

import 'package:lhokride/models/partner.dart';
import 'package:lhokride/models/menu.dart';
import 'package:lhokride/utils/route_utils.dart';
import 'package:lhokride/services/firebase_service.dart';

class OrderConfirmationPage extends StatefulWidget {
  final Partner partner;
  final Map<Menu, int> cart;
  final double totalPrice;
  final LatLng deliveryLocation;
  final String? deliveryAddress;
  final int deliveryFee;
  final double? estimatedDistance;
  final int? estimatedDuration;

  const OrderConfirmationPage({
    Key? key,
    required this.partner,
    required this.cart,
    required this.totalPrice,
    required this.deliveryLocation,
    this.deliveryAddress,
    this.deliveryFee = 0,
    this.estimatedDistance,
    this.estimatedDuration,
  }) : super(key: key);

  @override
  State<OrderConfirmationPage> createState() => _OrderConfirmationPageState();
}

// --- REDESIGNED THEME COLORS ---
class AppColors {
  static const Color primaryOrange = Color(0xFFE94F2E); // Gojek-like Orange
  static const Color darkOrange = Color(0xFFD94222);
  static const Color background = Color(0xFFF7F7F7);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF0D0D0D);
  static const Color textSecondary = Color(0xFF6A6A6A);
  static const Color divider = Color(0xFFE8E8E8);
  static const Color successGreen = Color(0xFF00AA13);
  static const Color errorRed = Color(0xFFD92121);
  static const Color shadow = Color.fromARGB(255, 224, 224, 224);
}

class _OrderConfirmationPageState extends State<OrderConfirmationPage>
    with TickerProviderStateMixin {
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _deliveryAddressResolved;
  bool _isLoadingAddress = true;
  bool _isLoadingBalance = true;
  bool _isProcessingOrder = false;
  double _userBalance = 0.0;
  String _selectedPaymentMethod = 'xpay'; // Default to XPay

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _resolveDeliveryAddress();
    _fetchWalletBalance();
    FirebaseService.initialize();
  }

  void _initAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  // --- Core Logic Functions (No UI Changes Here) ---
  Future<void> _resolveDeliveryAddress() async {
    try {
      if (widget.deliveryAddress != null &&
          widget.deliveryAddress!.isNotEmpty) {
        _deliveryAddressResolved = widget.deliveryAddress;
      } else {
        final address = await RouteUtils.reverseGeocode(
          widget.deliveryLocation,
        );
        _deliveryAddressResolved = address ?? 'Alamat tidak dapat ditemukan';
      }
    } catch (e) {
      _deliveryAddressResolved = 'Alamat tidak dapat ditemukan';
    } finally {
      if (mounted) setState(() => _isLoadingAddress = false);
    }
  }

  Future<void> _fetchWalletBalance() async {
    setState(() => _isLoadingBalance = true);
    try {
      final storedBalance = await _storage.read(key: 'saldo');
      if (mounted) {
        setState(() {
          _userBalance = double.tryParse(storedBalance ?? '0.0') ?? 0.0;
        });
      }
    } catch (e) {
      _showSnackBar('Gagal memuat saldo: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingBalance = false);
    }
  }

  Future<void> _processFoodOrder() async {
    if (_isProcessingOrder) return;
    final double grandTotal = widget.totalPrice + widget.deliveryFee;

    if (_selectedPaymentMethod == 'xpay' && _userBalance < grandTotal) {
      _showSnackBar('Saldo XPay tidak cukup.', isError: true);
      return;
    }
    setState(() => _isProcessingOrder = true);

    try {
      final userId = await _storage.read(key: 'user_id');
      final token = await _storage.read(key: 'token');
      if (userId == null || token == null) {
        _showSnackBar('Sesi berakhir, silakan login kembali.', isError: true);
        return;
      }

      final List<Map<String, dynamic>> items =
          widget.cart.entries
              .map(
                (e) => {
                  'id': e.key.id ?? 0,
                  'name': e.key.name,
                  'price': e.key.price,
                  'qty': e.value,
                },
              )
              .toList();

      final requestBody = {
        'userId': int.parse(userId),
        'merchantId': widget.partner.id,
        'items': items,
        'pickup': {
          'latitude': widget.partner.latitude,
          'longitude': widget.partner.longitude,
          'address': widget.partner.alamat ?? widget.partner.namaToko,
        },
        'destination': {
          'latitude': widget.deliveryLocation.latitude,
          'longitude': widget.deliveryLocation.longitude,
          'address': _deliveryAddressResolved ?? 'Alamat pengiriman',
        },
        'paymentMethod': _selectedPaymentMethod,
        'totalFoodPrice': widget.totalPrice,
        'deliveryFee': widget.deliveryFee,
        'grandTotal': grandTotal,
      };

      final response = await http.post(
        Uri.parse('http://api.lhokride.com/api/lhokfood/request'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final orderId = data['orderId'];
          if (_selectedPaymentMethod == 'xpay') {
            final newBalance = _userBalance - grandTotal;
            await _storage.write(key: 'saldo', value: newBalance.toString());
          }
          // Assuming FirebaseService is set up correctly
          // await FirebaseService.updateFoodOrderStatus(orderId, {...});

          _showSnackBar(
            _selectedPaymentMethod == 'xpay'
                ? 'Pembayaran berhasil! Pesanan sedang diproses.'
                : 'Pesanan berhasil dibuat! Siapkan uang tunai.',
            isError: false,
          );

         
            if (mounted) context.push('/order-tracking/$orderId');
        
        } else {
          _showSnackBar(
            'Gagal: ${data['message'] ?? 'Error tidak diketahui'}',
            isError: true,
          );
        }
      } else {
        _showSnackBar('Error: Gagal membuat pesanan.', isError: true);
      }
    } catch (e) {
      _showSnackBar('Terjadi kesalahan: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessingOrder = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.errorRed : AppColors.successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          80,
        ), // Adjust margin for floating action button
      ),
    );
  }

  // --- WIDGET BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rincian Pesanan'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: AppColors.shadow,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDeliveryDetailsCard(),
              const SizedBox(height: 16),
              _buildOrderSummaryCard(),
              const SizedBox(height: 120), // Space for bottom sheet
            ],
          ),
        ),
      ),
      bottomSheet: _buildBottomSheet(),
    );
  }

  // --- REDESIGNED WIDGETS ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.5),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildDeliveryDetailsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Pengiriman"),
        _buildCard(
          child: Column(
            children: [
              // Merchant Location
              _buildLocationRow(
                icon: Icons.storefront,
                iconColor: AppColors.primaryOrange,
                title: widget.partner.namaToko,
                subtitle: widget.partner.alamat ?? 'Alamat merchant',
              ),
              // Dotted line
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
                child: CustomPaint(painter: DottedLinePainter()),
              ),
              // Delivery Location
              _buildLocationRow(
                icon: Icons.location_on,
                iconColor: AppColors.successGreen,
                title: "Tujuan Pengantaran",
                subtitle:
                    _isLoadingAddress
                        ? "Memuat alamat..."
                        : _deliveryAddressResolved ?? "Alamat tidak tersedia",
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSummaryCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Pesanan dari ${widget.partner.namaToko}"),
        _buildCard(
          child: Column(
            children: [
              // Cart Items
              ...widget.cart.entries.map((entry) {
                return _buildMenuItem(entry.key, entry.value);
              }).toList(),
              const Divider(color: AppColors.divider, thickness: 1, height: 32),
              // Price Details
              _buildPriceRow("Subtotal Makanan", widget.totalPrice),
              const SizedBox(height: 8),
              _buildPriceRow("Ongkos Kirim", widget.deliveryFee.toDouble()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(Menu menu, int quantity) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "$quantity",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              menu.name,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            _currencyFormatter.format(menu.price * quantity),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(
          _currencyFormatter.format(value),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSheet() {
    final double grandTotal = widget.totalPrice + widget.deliveryFee;
    final bool canUseXpay = _userBalance >= grandTotal;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Payment Method Selection
          Row(
            children: [
              // XPay Option
              Expanded(
                child: _buildPaymentOption(
                  icon: Icons.account_balance_wallet,
                  title: "XPay",
                  subtitle:
                      _isLoadingBalance
                          ? "Memuat..."
                          : _currencyFormatter.format(_userBalance),
                  isSelected: _selectedPaymentMethod == 'xpay',
                  isEnabled: !_isLoadingBalance,
                  onTap: () => setState(() => _selectedPaymentMethod = 'xpay'),
                ),
              ),
              const SizedBox(width: 12),
              // Cash Option
              Expanded(
                child: _buildPaymentOption(
                  icon: Icons.money,
                  title: "Tunai",
                  subtitle: "Bayar di tempat",
                  isSelected: _selectedPaymentMethod == 'cash',
                  onTap: () => setState(() => _selectedPaymentMethod = 'cash'),
                ),
              ),
            ],
          ),

          // Insufficient Balance Warning
          if (_selectedPaymentMethod == 'xpay' &&
              !_isLoadingBalance &&
              !canUseXpay)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Saldo tidak mencukupi. Pilih metode tunai atau top up.',
                style: TextStyle(color: AppColors.errorRed, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          // CTA Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed:
                  (_isProcessingOrder ||
                          (_selectedPaymentMethod == 'xpay' && !canUseXpay))
                      ? null
                      : _processFoodOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 2,
                shadowColor: AppColors.primaryOrange.withOpacity(0.5),
              ),
              child:
                  _isProcessingOrder
                      ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                      : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pesan Sekarang',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _currencyFormatter.format(grandTotal),
                            style: const TextStyle(
                              fontSize: 16,
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

  Widget _buildPaymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    bool isEnabled = true,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled ? Colors.white : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryOrange : AppColors.divider,
            width: isSelected ? 2.0 : 1.5,
          ),
        ),
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.5,
          child: Row(
            children: [
              Icon(
                icon,
                color:
                    isSelected
                        ? AppColors.primaryOrange
                        : AppColors.textSecondary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom Painter for the dotted line in delivery details
class DottedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint =
        Paint()
          ..color = AppColors.divider
          ..strokeWidth = 2;
    var max = 35;
    var dashWidth = 5;
    var dashSpace = 3;
    double startY = 0;
    while (max > 0) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashWidth), paint);
      final space = (dashSpace + dashWidth);
      startY += space;
      max -= space;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
