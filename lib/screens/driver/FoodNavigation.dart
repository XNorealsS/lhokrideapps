// food_delivery_progress_screen.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:lhokride/utils/route_utils.dart';
import 'package:lhokride/services/firebase_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'component/chat_dialog.dart';

class FoodDeliveryProgressScreen extends StatefulWidget {
  final String orderId;
  final String userName;
  final String userId;
  final Map<String, dynamic> restaurantLocation;
  final Map<String, dynamic> userDestination;
  final List<dynamic> orderItems;
  final String userPhoneNumber;

  const FoodDeliveryProgressScreen({
    Key? key,
    required this.orderId,
    required this.userName,
    required this.userId,
    required this.restaurantLocation,
    required this.userDestination,
    required this.orderItems,
    required this.userPhoneNumber,
  }) : super(key: key);

  @override
  _FoodDeliveryProgressScreenState createState() =>
      _FoodDeliveryProgressScreenState();
}

class _FoodDeliveryProgressScreenState extends State<FoodDeliveryProgressScreen>
    with WidgetsBindingObserver {
  // --- Core State ---
  final _storage = const FlutterSecureStorage();
  final MapController _mapController = MapController();
  final PanelController _panelController = PanelController();
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _routeUpdateTimer;

  // --- Location & Route ---
  LatLng? _currentLocation;
  double _currentHeading = 0.0;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = true;

  // --- Order & Driver State ---
  String _currentDeliveryStatus = "to_restaurant";
  String? _driverId;

  // --- UI Constants ---
  static const Color _primaryOrangeColor = Color(0xFFFF6B35);
  static const Color _greenColor = Color(0xFF4CAF50);
  static const Color _blueColor = Color(0xFF2196F3);
  static const Color _textColor = Color(0xFF333333);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDriverAndInitialize();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _routeUpdateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchAndSetRoute();
      _centerMapOnDriver();
    }
  }

  Future<void> _loadDriverAndInitialize() async {
    _driverId = await _storage.read(key: 'driver_id');
    if (_driverId == null) {
      print("Error: Driver ID not found in storage.");
      _showSnackBar(
        "Gagal memuat ID driver, silakan coba lagi.",
        isError: true,
      );
      return;
    }
    await _fetchCurrentOrderStatus();
    await _initializeLocationAndMap();
    _startRouteUpdateTimer();
  }

  Future<void> _fetchCurrentOrderStatus() async {
    final orderDetails = await FirebaseService.getFoodOrderDetails(
      widget.orderId,
    );
    if (mounted && orderDetails != null && orderDetails['status'] != null) {
      setState(() {
        _currentDeliveryStatus = orderDetails['status'];
      });
    }
  }

  Future<void> _initializeLocationAndMap() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Layanan lokasi dinonaktifkan.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Izin lokasi ditolak.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar(
        'Izin lokasi ditolak secara permanen. Buka pengaturan aplikasi untuk mengizinkan.',
      );
      return;
    }

    // Get initial position to avoid waiting for the stream
    try {
      Position initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(
            initialPosition.latitude,
            initialPosition.longitude,
          );
          _currentHeading = initialPosition.heading;
        });
        _centerMapOnDriver();
        await _fetchAndSetRoute();
      }
    } catch (e) {
      print("Error getting initial position: $e");
    }

    // Listen for continuous location updates
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _currentHeading = position.heading; // Heading in degrees
          _mapController.move(_currentLocation!, _mapController.zoom);
        });

        if (_driverId != null) {
          _updateDriverLocationInFirebase(position);
        }
      }
    });
  }

  void _startRouteUpdateTimer() {
    _routeUpdateTimer?.cancel();
    _routeUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) _fetchAndSetRoute(); // Fetch route periodically
    });
  }

  void _centerMapOnDriver() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16.5);
    }
  }

  Future<void> _fetchAndSetRoute() async {
    if (_currentLocation == null || !mounted) return;

    setState(() => _isLoadingRoute = true);

    LatLng start = _currentLocation!;
    LatLng? end;

    if (_currentDeliveryStatus == "to_restaurant" ||
        _currentDeliveryStatus == "accepted") {
      end = LatLng(
        widget.restaurantLocation['latitude'],
        widget.restaurantLocation['longitude'],
      );
    } else if (_currentDeliveryStatus == "arrived_at_restaurant" ||
        _currentDeliveryStatus == "picked_up_order") {
      end = LatLng(
        widget.userDestination['latitude'],
        widget.userDestination['longitude'],
      );
    }

    if (end == null) {
      if (mounted)
        setState(() {
          _routePoints = [];
          _isLoadingRoute = false;
        });
      return;
    }

    try {
      final route = await RouteUtils.calculateRoute(start, end);
      if (mounted) {
        setState(() {
          _routePoints = route['routePoints'] ?? [];
        });
      }
    } catch (e) {
      print('Error fetching route: $e');
      if (mounted) _showSnackBar('Gagal memperbarui rute.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Future<void> _updateDriverLocationInFirebase(Position position) async {
    if (_driverId != null) {
      try {
        await FirebaseService.updateDriverLocation(
          _driverId!,
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        print('Error updating driver location: $e');
      }
    }
  }

  Future<void> _updateOrderStatus(String status) async {
    try {
      await FirebaseService.updateFoodOrderStatus(widget.orderId, {
        'status': status,
      });

      if (mounted) {
        setState(() => _currentDeliveryStatus = status);

        if (status == "delivered") {
          _showSnackBar('Pesanan berhasil diantar!', isError: false);
          // Pop after a short delay to allow user to see the snackbar
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        } else {
          _fetchAndSetRoute(); // Recalculate route for the next stage
        }
      }
    } catch (e) {
      print('Error updating order status: $e');
      if (mounted)
        _showSnackBar('Gagal memperbarui status pesanan.', isError: true);
    }
  }

  // --- UI Helpers ---

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : _greenColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openMapForNavigation() async {
    LatLng? destination;
    if (_currentDeliveryStatus == "to_restaurant" ||
        _currentDeliveryStatus == "accepted") {
      destination = LatLng(
        widget.restaurantLocation['latitude'],
        widget.restaurantLocation['longitude'],
      );
    } else if (_currentDeliveryStatus == "arrived_at_restaurant" ||
        _currentDeliveryStatus == "picked_up_order") {
      destination = LatLng(
        widget.userDestination['latitude'],
        widget.userDestination['longitude'],
      );
    } else {
      _showSnackBar("Tidak ada rute navigasi saat ini.");
      return;
    }

    final String googleMapsUrl =
        'google.navigation:q=${destination.latitude},${destination.longitude}&mode=d';
    final Uri googleMapsUri = Uri.parse(googleMapsUrl);

    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri);
    } else {
      // Fallback to a web-based Google Maps URL
      final String webUrl =
          'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving';
      final Uri webUri = Uri.parse(webUrl);
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri);
      } else {
        _showSnackBar('Tidak dapat membuka aplikasi peta.');
      }
    }
  }

  void _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      _showSnackBar('Tidak dapat melakukan panggilan.');
    }
  }

  Future<void> _openChatDialog() async {
    if (_driverId == null) {
      _showSnackBar('ID driver tidak tersedia untuk chat.');
      return;
    }
    await ChatService.show(
      context,
      rideId: widget.orderId,
      otherUserName: widget.userName,
      otherUserId: widget.userId,
      isDriver: true,
    );
  }

  // --- Widget Builders ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SlidingUpPanel(
        controller: _panelController,
        minHeight:
            MediaQuery.of(context).size.height * 0.25, // Responsive height
        maxHeight:
            MediaQuery.of(context).size.height * 0.75, // Responsive height
        parallaxEnabled: true,
        parallaxOffset: 0.5,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
        panelBuilder:
            (scrollController) => _buildSlidingPanelContent(scrollController),
        body: _buildMap(),
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter:
                _currentLocation ??
                const LatLng(5.18, 97.14), // Default to Lhokseumawe
            initialZoom: 15.0,
            maxZoom: 18.0,
            minZoom: 10.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.becak.lhokride',
              retinaMode: RetinaMode.isHighDensity(context),
            ),
            if (_routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    color: _primaryOrangeColor,
                    strokeWidth: 5.0,
                    borderColor: const Color(0xFFF2994A),
                    borderStrokeWidth: 2.5,
                  ),
                ],
              ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        // Map Buttons
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          right: 16,
          child: Column(
            children: [
              FloatingActionButton(
                heroTag: "myLocation",
                onPressed: _centerMapOnDriver,
                backgroundColor: Colors.white,
                foregroundColor: _textColor,
                mini: true,
                child: const Icon(Icons.my_location, size: 22),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: "smartNavigation",
                onPressed: _openMapForNavigation,
                backgroundColor: _blueColor,
                foregroundColor: Colors.white,
                mini: true,
                child: const Icon(Icons.navigation, size: 22),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final List<Marker> markers = [];

    // Driver Marker
    if (_currentLocation != null) {
      markers.add(
        Marker(
          width: 80.0,
          height: 80.0,
          point: _currentLocation!,
          child: Transform.rotate(
            angle:
                (_currentHeading *
                    (math.pi / 180)), // Convert degrees to radians
            child: const Icon(
              Icons.navigation_rounded,
              color: _primaryOrangeColor,
              size: 40,
              shadows: [Shadow(color: Colors.black54, blurRadius: 10.0)],
            ),
          ),
        ),
      );
    }

    // Restaurant Marker
    markers.add(
      _buildLocationMarker(
        point: LatLng(
          widget.restaurantLocation['latitude'],
          widget.restaurantLocation['longitude'],
        ),
        icon: Icons.restaurant,
        color: _blueColor,
      ),
    );

    // User Destination Marker
    markers.add(
      _buildLocationMarker(
        point: LatLng(
          widget.userDestination['latitude'],
          widget.userDestination['longitude'],
        ),
        icon: Icons.location_on,
        color: _greenColor,
      ),
    );

    return markers;
  }

  Marker _buildLocationMarker({
    required LatLng point,
    required IconData icon,
    required Color color,
  }) {
    return Marker(
      width: 48.0,
      height: 48.0,
      point: point,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildSlidingPanelContent(ScrollController scrollController) {
    // Responsive sizing helper
    double screenWidth = MediaQuery.of(context).size.width;
    double scaleFactor = screenWidth / 375.0; // Base width for scaling

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.zero,
      children: [
        // Panel grabber
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12.0),
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
        ),

        // Status and Action Button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              _buildStatusHeader(scaleFactor),
              const SizedBox(height: 16),
              _buildActionButton(scaleFactor),
            ],
          ),
        ),

        const Divider(height: 32, thickness: 1, indent: 16, endIndent: 16),

        // Collapsible Details
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOrderDetails(scaleFactor),
              const SizedBox(height: 16),
              _buildCustomerInfo(scaleFactor),
              const SizedBox(height: 16),
              _buildRestaurantInfo(scaleFactor),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusHeader(double scaleFactor) {
    IconData icon;
    String statusText;
    String subText;

    switch (_currentDeliveryStatus) {
      case "to_restaurant":
      case "accepted":
        icon = Icons.store_mall_directory_rounded;
        statusText = "Menuju Restoran";
        subText = "Ambil pesanan pelanggan";
        break;
      case "arrived_at_restaurant":
        icon = Icons.shopping_bag_rounded;
        statusText = "Tiba di Restoran";
        subText = "Konfirmasi dan ambil pesanan";
        break;
      case "picked_up_order":
        icon = Icons.delivery_dining_rounded;
        statusText = "Menuju Pelanggan";
        subText = "Antarkan pesanan ke lokasi tujuan";
        break;
      case "delivered":
        icon = Icons.home_rounded;
        statusText = "Tiba di Tujuan";
        subText = "Selesaikan pesanan dengan pelanggan";
        break;
      default:
        icon = Icons.info_outline_rounded;
        statusText = "Status Tidak Dikenal";
        subText = "Memuat status terkini...";
    }

    return Row(
      children: [
        Icon(icon, color: _primaryOrangeColor, size: 36 * scaleFactor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18 * scaleFactor,
                  color: _textColor,
                ),
              ),
              Text(
                subText,
                style: TextStyle(
                  fontSize: 14 * scaleFactor,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(double scaleFactor) {
    String buttonText = "Memuat...";
    VoidCallback? onPressed;
    Color buttonColor = _primaryOrangeColor;
    bool isLoading = false;

    switch (_currentDeliveryStatus) {
      case "accepted":
      case "to_restaurant":
        buttonText = "Sudah Sampai di Restoran";
        onPressed = () => _updateOrderStatus("arrived_at_restaurant");
        break;
      case "arrived_at_restaurant":
        buttonText = "Ambil Pesanan";
        onPressed = () => _updateOrderStatus("picked_up_order");
        buttonColor = _blueColor;
        break;
      case "picked_up_order":
        buttonText = "Sudah Sampai di Tujuan";
        onPressed = () => _updateOrderStatus("arrived_at_destination");
        break;
      case "delivered":
        buttonText = "Selesaikan Pengantaran";
        onPressed = () => _updateOrderStatus("delivered");
        buttonColor = _greenColor;
        break;
      default:
        buttonText = "Status Tidak Dikenal";
        onPressed = null;
        isLoading = true;
        buttonColor = Colors.grey;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16 * scaleFactor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        child:
            isLoading
                ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
                : Text(
                  buttonText,
                  style: TextStyle(
                    fontSize: 16 * scaleFactor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Widget content,
    required double scaleFactor,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(16 * scaleFactor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _primaryOrangeColor, size: 20 * scaleFactor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildOrderDetails(double scaleFactor) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    );

    return _buildInfoCard(
      title: "Detail Pesanan",
      icon: Icons.receipt_long_rounded,
      scaleFactor: scaleFactor,
      content: Column(
        children: [
          if (widget.orderItems.isEmpty)
            const Text("Tidak ada item pesanan.")
          else
            ...widget.orderItems.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "${item['name'] ?? 'N/A'} (x${item['qty'] ?? 0})",
                        style: TextStyle(fontSize: 14 * scaleFactor),
                      ),
                    ),
                    Text(
                      currencyFormatter.format(
                        (item['price'] ?? 0) * (item['qty'] ?? 0),
                      ),
                      style: TextStyle(
                        fontSize: 14 * scaleFactor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total Pembayaran",
                style: TextStyle(
                  fontSize: 15 * scaleFactor,
                  fontWeight: FontWeight.bold,
                  color: _primaryOrangeColor,
                ),
              ),
              Text(
                currencyFormatter.format(
                  widget.orderItems.fold(
                        0.0,
                        (sum, item) =>
                            sum + (item['price'] ?? 0) * (item['qty'] ?? 0),
                      ) +
                      (widget.userDestination['deliveryFee'] ?? 0),
                ),
                style: TextStyle(
                  fontSize: 15 * scaleFactor,
                  fontWeight: FontWeight.bold,
                  color: _primaryOrangeColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfo(double scaleFactor) {
    return _buildInfoCard(
      title: "Info Pelanggan",
      icon: Icons.person_rounded,
      scaleFactor: scaleFactor,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.userName,
            style: TextStyle(
              fontSize: 15 * scaleFactor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_on_outlined,
                color: Colors.grey[600],
                size: 18 * scaleFactor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.userDestination['address'] ?? 'Alamat tidak tersedia',
                  style: TextStyle(
                    fontSize: 13 * scaleFactor,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _makePhoneCall(widget.userPhoneNumber),
                  icon: Icon(Icons.call_rounded, size: 18 * scaleFactor),
                  label: Text(
                    "Telepon",
                    style: TextStyle(fontSize: 13 * scaleFactor),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _greenColor,
                    side: const BorderSide(color: _greenColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openChatDialog,
                  icon: Icon(Icons.chat_rounded, size: 18 * scaleFactor),
                  label: Text(
                    "Chat",
                    style: TextStyle(fontSize: 13 * scaleFactor),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blueColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantInfo(double scaleFactor) {
    return _buildInfoCard(
      title: "Info Restoran",
      icon: Icons.storefront_rounded,
      scaleFactor: scaleFactor,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_on_outlined,
            color: Colors.grey[600],
            size: 18 * scaleFactor,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.restaurantLocation['address'] ??
                  'Alamat restoran tidak tersedia',
              style: TextStyle(
                fontSize: 13 * scaleFactor,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
