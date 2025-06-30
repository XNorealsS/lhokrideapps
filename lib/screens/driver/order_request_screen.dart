// order_request_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:lhokride/utils/route_utils.dart';
import 'package:shimmer/shimmer.dart';

/// Layar Permintaan Pesanan - Tampilan yang disederhanakan dan mudah dibaca
/// untuk driver melihat detail pesanan baru
class OrderRequestScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final String orderType;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const OrderRequestScreen({
    Key? key,
    required this.orderData,
    required this.orderType,
    required this.onAccept,
    required this.onReject,
  }) : super(key: key);

  @override
  State<OrderRequestScreen> createState() => _OrderRequestScreenState();
}

class _OrderRequestScreenState extends State<OrderRequestScreen> {
  String pickupAddress = "Memuat alamat...";
  String destinationAddress = "Memuat alamat...";
  bool isLoadingAddresses = true;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      // Untuk food, pickup adalah nama toko
      if (widget.orderType == 'food') {
        setState(() {
          pickupAddress = widget.orderData['mitraName'] ?? "Toko tidak diketahui";
        });
      } else {
        // Untuk ride, load alamat pickup
        if (widget.orderData['pickup'] != null) {
          final pickupLat = widget.orderData['pickup']['latitude'];
          final pickupLng = widget.orderData['pickup']['longitude'];

          if (pickupLat != null && pickupLng != null) {
            final pickupLocation = LatLng(
              pickupLat.toDouble(),
              pickupLng.toDouble(),
            );
            final fetchedPickupAddress = await RouteUtils.reverseGeocode(
              pickupLocation,
            );

            if (mounted) {
              setState(() {
                pickupAddress = fetchedPickupAddress;
              });
            }
          } else {
            if (mounted) {
              setState(() {
                pickupAddress = widget.orderData['pickup']['address'] ?? 
                    "Alamat penjemputan tidak tersedia";
              });
            }
          }
        }
      }

      // Load alamat tujuan
      if (widget.orderData['destination'] != null) {
        final destLat = widget.orderData['destination']['latitude'];
        final destLng = widget.orderData['destination']['longitude'];

        if (destLat != null && destLng != null) {
          final destLocation = LatLng(destLat.toDouble(), destLng.toDouble());
          final fetchedDestAddress = await RouteUtils.reverseGeocode(
            destLocation,
          );

          if (mounted) {
            setState(() {
              destinationAddress = fetchedDestAddress;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              destinationAddress = widget.orderData['destination']['address'] ?? 
                  "Alamat tujuan tidak tersedia";
            });
          }
        }
      }
    } catch (e) {
      print("Error loading addresses: $e");
      if (mounted) {
        setState(() {
          pickupAddress = "Gagal memuat alamat";
          destinationAddress = "Gagal memuat alamat";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoadingAddresses = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Tentukan detail pesanan berdasarkan type
    final orderInfo = _getOrderInfo();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            // Header yang disederhanakan
            _buildHeader(screenWidth, screenHeight, orderInfo),
            
            // Content area
            Expanded(
              child: _buildContent(screenWidth, screenHeight, orderInfo),
            ),
            
            // Action buttons
            _buildActionButtons(screenWidth, screenHeight),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getOrderInfo() {
    if (widget.orderType == 'ride') {
      return {
        'title': 'Permintaan Perjalanan',
        'icon': Icons.motorcycle,
        'customerName': widget.orderData['passenger']['name'] ?? "Penumpang",
        'customerPhone': widget.orderData['passenger']['phone'] ?? 'N/A',
        'price': widget.orderData['price'] ?? 0,
        'orderId': widget.orderData['rideId'] ?? "N/A",
        'details': "Jarak: ${widget.orderData['distance']?.toStringAsFixed(1) ?? 'N/A'} km",
        'paymentMethod': widget.orderData['paymentMethod'] ?? 'Tunai',
      };
    } else {
      double totalPrice = 0;
      List<String> itemsList = [];
      if (widget.orderData['items'] != null) {
        for (var item in widget.orderData['items']) {
          totalPrice += (item['price'] ?? 0) * (item['qty'] ?? 1);
          itemsList.add("${item['name']} x${item['qty']}");
        }
      }
      
      return {
        'title': 'Pesanan Makanan',
        'icon': Icons.restaurant,
        'customerName': widget.orderData['user']['name'] ?? "Pembeli",
        'customerPhone': widget.orderData['user']['phone'] ?? 'N/A',
        'price': totalPrice,
        'orderId': widget.orderData['orderId'] ?? "N/A",
        'details': "Item: ${itemsList.join(', ')}",
        'paymentMethod': widget.orderData['paymentMethod'] ?? 'Tunai',
      };
    }
  }

  Widget _buildHeader(double screenWidth, double screenHeight, Map<String, dynamic> orderInfo) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: screenHeight * 0.02,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: screenWidth * 0.12,
            height: screenWidth * 0.12,
            decoration: BoxDecoration(
              color: const Color(0xFFE48700).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              orderInfo['icon'],
              size: screenWidth * 0.06,
              color: const Color(0xFFE48700),
            ),
          ),
          SizedBox(width: screenWidth * 0.04),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  orderInfo['title'],
                  style: TextStyle(
                    fontSize: screenWidth * 0.05,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'ID: ${orderInfo['orderId']}',
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          // Price
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.03,
              vertical: screenHeight * 0.01,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE48700),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '').format(orderInfo['price'])}",
              style: TextStyle(
                fontSize: screenWidth * 0.04,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(double screenWidth, double screenHeight, Map<String, dynamic> orderInfo) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.all(screenWidth * 0.04),
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer Info
            _buildInfoSection(
              title: "Informasi Pelanggan",
              children: [
                _buildInfoItem(
                  icon: Icons.person_outline,
                  label: "Nama",
                  value: orderInfo['customerName'],
                  screenWidth: screenWidth,
                ),
                _buildInfoItem(
                  icon: Icons.phone_outlined,
                  label: "Telepon",
                  value: orderInfo['customerPhone'],
                  screenWidth: screenWidth,
                ),
              ],
              screenWidth: screenWidth,
            ),
            
            SizedBox(height: screenHeight * 0.02),
            
            // Location Info
            _buildInfoSection(
              title: "Informasi Lokasi",
              children: [
                _buildInfoItem(
                  icon: Icons.location_on_outlined,
                  label: widget.orderType == 'food' ? "Toko" : "Penjemputan",
                  value: pickupAddress,
                  isLoading: isLoadingAddresses && widget.orderType == 'ride',
                  screenWidth: screenWidth,
                ),
                _buildInfoItem(
                  icon: Icons.flag_outlined,
                  label: "Tujuan",
                  value: destinationAddress,
                  isLoading: isLoadingAddresses,
                  screenWidth: screenWidth,
                ),
              ],
              screenWidth: screenWidth,
            ),
            
            SizedBox(height: screenHeight * 0.02),
            
            // Order Details
            _buildInfoSection(
              title: "Detail Pesanan",
              children: [
                _buildInfoItem(
                  icon: Icons.info_outline,
                  label: "Rincian",
                  value: orderInfo['details'],
                  screenWidth: screenWidth,
                ),
                _buildInfoItem(
                  icon: Icons.payment_outlined,
                  label: "Pembayaran",
                  value: orderInfo['paymentMethod'],
                  screenWidth: screenWidth,
                ),
              ],
              screenWidth: screenWidth,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required List<Widget> children,
    required double screenWidth,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: screenWidth * 0.045,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: screenWidth * 0.02),
        ...children,
      ],
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required double screenWidth,
    bool isLoading = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: screenWidth * 0.03),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: screenWidth * 0.05,
            color: const Color(0xFFE48700),
          ),
          SizedBox(width: screenWidth * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: screenWidth * 0.01),
                if (isLoading)
                  Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Container(
                      height: screenWidth * 0.04,
                      width: screenWidth * 0.6,
                      color: Colors.white,
                    ),
                  )
                else
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: screenWidth * 0.04,
                      color: Colors.black87,
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

  Widget _buildActionButtons(double screenWidth, double screenHeight) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Reject Button
          Expanded(
            child: ElevatedButton(
              onPressed: widget.onReject,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade500,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: Text(
                "Tolak",
                style: TextStyle(
                  fontSize: screenWidth * 0.04,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: screenWidth * 0.04),
          // Accept Button
          Expanded(
            child: ElevatedButton(
              onPressed: widget.onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade500,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: Text(
                "Terima",
                style: TextStyle(
                  fontSize: screenWidth * 0.04,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}