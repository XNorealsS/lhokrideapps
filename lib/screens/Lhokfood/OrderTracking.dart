// lib/pages/order_tracking_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:go_router/go_router.dart';
import 'package:lhokride/services/firebase_service.dart';
import 'package:lhokride/utils/route_utils.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart'; // For loading indicators
import 'dart:math' as math;
// Import the sliding_up_panel package
import 'package:sliding_up_panel/sliding_up_panel.dart';


// Assuming AppColors are defined globally or in a common utility file
class AppColors {
  static const Color primaryOrange = Color(0xFFFF8C00); // Main orange
  static const Color lightOrange = Color(0xFFFFE0B2); // Very light orange
  static const Color darkerOrange = Color(0xFFE67E22); // Slightly darker orange
  static const Color accentBlue = Color(0xFF2196F3); // Accent blue
  static const Color greyText = Color(0xFF757575); // Grey text for general use
  static const Color gojekGreen = Color(0xFF00AA13); // Gojek primary green
  static const Color gojekGreenLight = Color(
    0xFFE6FFE9,
  ); // Lighter shade of Gojek green
  static const Color successGreen = Color(0xFF4CAF50); // General success green
  static const Color infoBlue = Color(0xFF2196F3); // General info blue
  static const Color darkGrey = Color(0xFF424242); // Dark grey for text/icons
  static const Color cardBg = Color(0xFFFFFFFF); // Card background color
  static const Color shadowColor = Color(0xFF000000); // Shadow color
}

// Enum to define order status more clearly, aligned with driver statuses
enum _OrderStatus {
  pending, // Before driver accepts
  accepted, // Driver accepted
  preparing, // Partner preparing order
  toRestaurant, // Driver on the way to restaurant
  arrivedAtRestaurant, // Driver arrived at restaurant
  pickedUp, // Driver picked up order
  onTheWayToDestination, // Driver on the way to user
  delivered,
  canceled,
}

class OrderTrackingPage extends StatefulWidget {
  final String orderId;

  const OrderTrackingPage({Key? key, required this.orderId}) : super(key: key);

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage>
    with TickerProviderStateMixin {
  // Map and Location Variables
  final MapController _mapController = MapController();
  // Using PanelController for SlidingUpPanel
  final PanelController _panelController = PanelController();

  LatLng? _driverLocation;
  LatLng?
  _partnerLocation; // Renamed from _pickupLocation for clarity with existing code
  LatLng?
  _userDeliveryLocation; // Renamed from _deliveryLocation for clarity with existing code
  List<LatLng> _deliveryRoutePoints = []; // Renamed from _routePoints
  Timer? _mapDebounceTimer;
  StreamSubscription<DatabaseEvent>? _orderStatusSubscription;
  StreamSubscription<DatabaseEvent>? _driverLocationSubscription;
  Timer? _locationUpdateTimer; // New timer for periodic location updates

  // Order Data
  Map<String, dynamic>? _orderData; // Renamed from _orderDetails
  _OrderStatus _currentOrderStatus =
      _OrderStatus.pending; // Renamed from _orderStatus
  String? _driverName;
  String? _driverId;
  String? _driverPhone;
  String? _estimatedDeliveryTime;
  List<dynamic> _orderItems = []; // New variable for order items
  double _totalAmount = 0.0; // New variable for total amount
  double _deliveryFee = 0.0; // Variable for delivery fee

  // UI State
  // double _panelHeight = 0.0; // No longer needed with SlidingUpPanel
  // bool _isPanelExpanded = false; // No longer explicitly needed for panel state
  // late AnimationController _panelAnimationController; // No longer needed
  late Animation<double> _fabAnimation;
  late AnimationController _fabAnimationController;
  bool _isLoadingOrderDetails = true; // New loading indicator
  bool _isDriverFound = false; // New flag for driver found status
  bool _isOrderCompleted = false; // New flag for order completion/cancellation

  // Marker animation for driver
  late AnimationController _driverMarkerAnimationController;
  late Animation<double> _driverMarkerAnimation;
  late AnimationController _radarAnimationController; // New for radar animation
  late Animation<double> _radarAnimation; // New for radar animation

  @override
  void initState() {
    super.initState();
    // _panelAnimationController = AnimationController( // No longer needed
    //   vsync: this,
    //   duration: const Duration(milliseconds: 300),
    // );
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeOut),
    );

    _driverMarkerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _driverMarkerAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(
      CurvedAnimation(
        parent: _driverMarkerAnimationController,
        curve: Curves.linear,
      ),
    );
    _driverMarkerAnimationController
        .repeat(); // Keep the driver marker animating

    _radarAnimationController = AnimationController(
      // Initialize radar animation
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _radarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _radarAnimationController, curve: Curves.linear),
    );

    _initializeOrderTracking();
  }

  Future<void> _initializeOrderTracking() async {
    await _fetchOrderDetailsAndListen(); // Renamed to include listening
    // No explicit _togglePanel needed, SlidingUpPanel handles initial state
    // We can directly open the panel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_panelController.isAttached) {
        _panelController.show();
      }
    });
  }

  Future<void> _fetchOrderDetailsAndListen() async {
    setState(() {
      _isLoadingOrderDetails = true;
    });

    try {
      final orderDetails = await FirebaseService.getFoodOrderDetails(
        widget.orderId,
      );
      if (orderDetails != null) {
        _orderData = orderDetails;

        // Extract location data
        final pickupLat =
            (orderDetails['pickup']?['latitude'] as num?)?.toDouble();
        final pickupLng =
            (orderDetails['pickup']?['longitude'] as num?)?.toDouble();
        final deliveryLat =
            (orderDetails['destination']?['latitude'] as num?)?.toDouble();
        final deliveryLng =
            (orderDetails['destination']?['longitude'] as num?)?.toDouble();

        if (pickupLat != null && pickupLng != null) {
          _partnerLocation = LatLng(pickupLat, pickupLng);
        }
        if (deliveryLat != null && deliveryLng != null) {
          _userDeliveryLocation = LatLng(deliveryLat, deliveryLng);
        }

        // Extract order items and calculate total
        _orderItems = orderDetails['items'] ?? [];
        _deliveryFee =
            (orderDetails['deliveryFee'] as num? ?? 0)
                .toDouble(); // Get delivery fee
        _totalAmount = _calculateTotalAmount();

        setState(() {
          _currentOrderStatus = _parseOrderStatus(
            orderDetails['status'] as String?,
          );
          // Driver data from 'driver' map if available
          _driverId =
              (orderDetails['driver']?['id'] as dynamic)?.toString() ??
              (orderDetails['driverId'] as dynamic)?.toString();
          _driverName = orderDetails['driver']?['name'] as String?;
          _driverPhone =
              orderDetails['driver']?['phone']
                  as String?; // Assuming phone is within driver map
          _isDriverFound =
              (orderDetails['status'] != 'pending' && _driverId != null);
        });

        // Listen to order status changes
        _listenToOrderStatusChanges();

        // If driver is found, start tracking
        if (_driverId != null && _isDriverFound) {
          _stopRadarAnimation();
          _listenToDriverLocation();
          _startLocationUpdateTimer();
        }

        // Setup map view after data is loaded
        _setupMapView();
      }
    } catch (e) {
      print('Error fetching order details: $e');
      setState(() {
        _currentOrderStatus =
            _OrderStatus
                .pending; // Revert to pending or a specific error status
      });
    } finally {
      setState(() {
        _isLoadingOrderDetails = false;
      });
    }
  }

  void _listenToDriverLocation() {
    _driverLocationSubscription
        ?.cancel(); // Cancel previous subscription if any
    if (_driverId != null) {
      _driverLocationSubscription = FirebaseService.listenToDriverLocation(
        _driverId!,
        (locationData) {
          if (mounted) {
            final lat = (locationData['latitude'] as num?)?.toDouble();
            final lng = (locationData['longitude'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              setState(() {
                _driverLocation = LatLng(lat, lng);
              });
              _updateRoute(); // Update route when driver location changes
            }
          }
        },
      );
    }
  }

  void _listenToOrderStatusChanges() {
    _orderStatusSubscription = FirebaseService.listenToFoodStatus(
      widget.orderId,
      (orderData) {
        if (mounted) {
          setState(() {
            _currentOrderStatus = _parseOrderStatus(
              orderData['status'] as String?,
            );

            final newDriverId =
                (orderData['driver']?['id'] as dynamic)?.toString();
            if (newDriverId != null && _driverId != newDriverId) {
              _driverId = newDriverId;
              _driverName = orderData['driver']?['name'] as String?;
              _driverPhone = orderData['driver']?['phone'] as String?;
              _isDriverFound = true;
              _stopRadarAnimation();
              _listenToDriverLocation();
              _startLocationUpdateTimer();
            } else if (orderData['status'] != 'pending' &&
                _driverId != null &&
                !_isDriverFound) {
              _isDriverFound = true;
              _stopRadarAnimation();
              _listenToDriverLocation();
              _startLocationUpdateTimer();
            }

            if (_currentOrderStatus == _OrderStatus.delivered ||
                _currentOrderStatus == _OrderStatus.canceled) {
              _isOrderCompleted = true;
              _disposeListeners();
              _stopTimers();
            }
          });
        }
      },
    );
  }

  _OrderStatus _parseOrderStatus(String? statusString) {
    switch (statusString?.toLowerCase()) {
      case 'pending':
        return _OrderStatus.pending;
      case 'accepted':
        return _OrderStatus.accepted;
      case 'preparing':
        return _OrderStatus.preparing;
      case 'to_restaurant':
        return _OrderStatus.toRestaurant;
      case 'arrived_at_restaurant':
        return _OrderStatus.arrivedAtRestaurant;
      case 'picked_up_order':
        return _OrderStatus.pickedUp;
      case 'on_the_way_to_destination':
        return _OrderStatus.onTheWayToDestination;
      case 'delivering': // Added 'delivering' to map to onTheWayToDestination
        return _OrderStatus.onTheWayToDestination;
      case 'delivered':
        return _OrderStatus.delivered;
      case 'canceled':
        return _OrderStatus.canceled;
      default:
        return _OrderStatus.pending; // Default or error state
    }
  }

  String _getOrderStatusText(_OrderStatus status) {
    switch (status) {
      case _OrderStatus.pending:
        return 'Menunggu Konfirmasi Penjual';
      case _OrderStatus.accepted:
        return 'Pesanan Diterima Driver';
      case _OrderStatus.preparing:
        return 'Pesanan Sedang Diproses Penjual';
      case _OrderStatus.toRestaurant:
        return 'Driver Menuju ke Penjual';
      case _OrderStatus.arrivedAtRestaurant:
        return 'Driver Sudah di Penjual';
      case _OrderStatus.pickedUp:
        return 'Pesanan Sudah Diambil Driver';
      case _OrderStatus.onTheWayToDestination:
        return 'Driver Menuju Lokasi Anda';
      case _OrderStatus.delivered:
        return 'Pesanan Telah Tiba!';
      case _OrderStatus.canceled:
        return 'Pesanan Dibatalkan';
    }
  }

  int _getStepIndex(_OrderStatus status) {
    switch (status) {
      case _OrderStatus.pending:
        return 0; // Pre-acceptance
      case _OrderStatus.accepted:
        return 1; // Order accepted by driver
      case _OrderStatus.preparing:
        return 1; // Partner preparing, driver might have accepted
      case _OrderStatus.toRestaurant:
        return 2; // Driver on the way to restaurant
      case _OrderStatus.arrivedAtRestaurant:
        return 3; // Driver arrived at restaurant
      case _OrderStatus.pickedUp:
        return 4; // Driver picked up order
      case _OrderStatus.onTheWayToDestination:
        return 5; // Driver en route to destination
      case _OrderStatus.delivered:
        return 6; // Order delivered
      case _OrderStatus.canceled:
        return 0; // Canceled state doesn't fit into a linear progress
    }
  }

  Future<void> _updateRoute() async {
    if (_driverLocation != null &&
        _partnerLocation != null &&
        _userDeliveryLocation != null &&
        !_isOrderCompleted) {
      try {
        LatLng destination;
        if ([
          _OrderStatus.toRestaurant,
          _OrderStatus.arrivedAtRestaurant,
          _OrderStatus
              .accepted, // Driver just accepted, likely heading to partner
        ].contains(_currentOrderStatus)) {
          destination = _partnerLocation!;
        } else if ([
          _OrderStatus.pickedUp,
          _OrderStatus.onTheWayToDestination,
        ].contains(_currentOrderStatus)) {
          destination = _userDeliveryLocation!;
        } else {
          // If status is pending or preparing, show route from partner to user directly
          // Or if driver is not yet assigned/moving, the initial route is from partner to user.
          destination = _userDeliveryLocation!;
          if (_partnerLocation != null) {
            final routeData = await RouteUtils.calculateRoute(
              _partnerLocation!,
              destination,
            );
            _deliveryRoutePoints =
                (routeData['routePoints'] as List<LatLng>? ?? []);
            final etaSeconds = routeData['eta'] as int;
            _estimatedDeliveryTime = _formatDuration(
              Duration(seconds: etaSeconds),
            );
            // _fitMapToShowAllPoints();
            return; // Exit as this is a specific case
          }
        }

        final routeData = await RouteUtils.calculateRoute(
          _driverLocation!,
          destination,
        );
        final List<LatLng> newRoutePoints =
            (routeData['routePoints'] as List<LatLng>? ?? []);

        if (mounted) {
          setState(() {
            _deliveryRoutePoints = newRoutePoints;
            final etaSeconds = routeData['eta'] as int;
            _estimatedDeliveryTime = _formatDuration(
              Duration(seconds: etaSeconds),
            );
          });
        }
      } catch (e) {
        print('Error calculating route: $e');
        if (mounted) {
          setState(() {
            _deliveryRoutePoints = [];
            _estimatedDeliveryTime = null;
          });
        }
      }
    }
    // _fitMapToShowAllPoints();
  }

  void _startLocationUpdateTimer() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateRoute();
    });
    _updateRoute(); // Call immediately on start
  }

  void _stopTimers() {
    _locationUpdateTimer?.cancel();
  }

  void _setupMapView() {
    if (_partnerLocation != null && _userDeliveryLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fitMapToShowAllPoints();
        }
      });
    }
  }

  void _fitMapToShowAllPoints() {
    List<LatLng> points = [];
    if (_partnerLocation != null) points.add(_partnerLocation!);
    if (_userDeliveryLocation != null) points.add(_userDeliveryLocation!);
    if (_driverLocation != null) points.add(_driverLocation!);

    if (points.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
      );
    }
  }

  double _calculateTotalAmount() {
    double total = 0.0;
    for (var item in _orderItems) {
      total +=
          (item['price'] as num? ?? 0).toDouble() *
          (item['qty'] as num? ?? 0).toDouble();
    }
    total += _deliveryFee; // Use the stored _deliveryFee
    return total;
  }

  void _onMapMoved(MapCamera camera) {
    _mapDebounceTimer?.cancel();
    _mapDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      // Potentially re-center map if user moves it too far off route,
      // or simply do nothing if the intention is to let the user explore
    });
  }

  String _formatCurrency(double amount) {
    final formatCurrency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return formatCurrency.format(amount);
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return 'Kurang dari 1 menit';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes} menit';
    } else {
      final hours = duration.inHours;
      final remainingMinutes = duration.inMinutes % 60;
      return '$hours jam ${remainingMinutes} menit';
    }
  }

  // Removed _togglePanel as SlidingUpPanel handles its own state
  // void _togglePanel() {
  //   setState(() {
  //     _isPanelExpanded = !_isPanelExpanded;
  //     if (_isPanelExpanded) {
  //       _panelHeight =
  //           MediaQuery.of(context).size.height * 0.55; // Adjust as needed
  //       _panelAnimationController.forward();
  //       _fabAnimationController.forward();
  //     } else {
  //       _panelHeight = 0.0;
  //       _panelAnimationController.reverse();
  //       _fabAnimationController.reverse();
  //     }
  //   });
  // }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat melakukan panggilan')),
      );
    }
  }

  Future<void> _sendWhatsAppMessage(String phoneNumber) async {
    final Uri launchUri = Uri.parse('https://wa.me/$phoneNumber');
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat membuka WhatsApp')),
      );
    }
  }

  void _stopRadarAnimation() {
    _radarAnimationController.stop();
    // No need to dispose here, it will be disposed in the main dispose
  }

  void _disposeListeners() {
    _orderStatusSubscription?.cancel();
    _driverLocationSubscription?.cancel();
  }

  Widget _buildStatusHeader(double scaleFactor) {
    int currentStep = _getStepIndex(_currentOrderStatus);
    // Adjusted total steps to align with the visual progress bar
    // Accepted (1), To Restaurant (2), Arrived At Restaurant (3), Picked Up (4), On The Way To Destination (5), Delivered (6)
    int totalSteps = 6;

    IconData statusIcon;
    Color statusIconColor;
    String statusSubtitle;

    switch (_currentOrderStatus) {
      case _OrderStatus.pending:
        statusIcon = Icons.pending_actions;
        statusIconColor = AppColors.primaryOrange;
        statusSubtitle = "Pesanan Anda sedang menunggu konfirmasi penjual.";
        break;
      case _OrderStatus.accepted:
        statusIcon = Icons.check_circle_outline;
        statusIconColor = AppColors.gojekGreen;
        statusSubtitle = "Driver telah menerima pesanan Anda.";
        break;
      case _OrderStatus.preparing:
        statusIcon = Icons.restaurant_menu;
        statusIconColor = AppColors.primaryOrange;
        statusSubtitle = "Penjual sedang menyiapkan pesanan Anda.";
        break;
      case _OrderStatus.toRestaurant:
        statusIcon = Icons.directions_bike;
        statusIconColor = AppColors.gojekGreen;
        statusSubtitle = "Driver sedang menuju ke penjual.";
        break;
      case _OrderStatus.arrivedAtRestaurant:
        statusIcon = Icons.storefront;
        statusIconColor = AppColors.gojekGreen;
        statusSubtitle = "Driver sudah tiba di penjual.";
        break;
      case _OrderStatus.pickedUp:
        statusIcon = Icons.shopping_bag;
        statusIconColor = AppColors.gojekGreen;
        statusSubtitle = "Pesanan Anda sudah diambil driver.";
        break;
      case _OrderStatus.onTheWayToDestination:
        statusIcon = Icons.delivery_dining;
        statusIconColor = AppColors.gojekGreen;
        statusSubtitle = "Driver sedang menuju lokasi Anda.";
        break;
      case _OrderStatus.delivered:
        statusIcon = Icons.check_circle;
        statusIconColor = AppColors.successGreen;
        statusSubtitle = "Pesanan Anda telah tiba!";
        break;
      case _OrderStatus.canceled:
        statusIcon = Icons.cancel;
        statusIconColor = Colors.red;
        statusSubtitle = "Pesanan Anda telah dibatalkan.";
        break;
    }


    return Container(
      color: AppColors.cardBg, // Use card background color for header
      padding: EdgeInsets.symmetric(horizontal: 20 * scaleFactor, vertical: 15 * scaleFactor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time, color: AppColors.primaryOrange, size: 24 * scaleFactor),
              SizedBox(width: 8 * scaleFactor),
              Text(
                'Estimasi Tiba: ${_estimatedDeliveryTime ?? (_isDriverFound ? "Menghitung..." : "Menunggu Driver...")}',
                style: TextStyle(
                  fontSize: 16 * scaleFactor,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryOrange,
                ),
              ),
              const Spacer(),
              Icon(
                statusIcon,
                color: statusIconColor,
                size: 30 * scaleFactor,
              ),
            ],
          ),
          SizedBox(height: 10 * scaleFactor),
          Text(
            _getOrderStatusText(_currentOrderStatus),
            style: TextStyle(
              fontSize: 18 * scaleFactor,
              fontWeight: FontWeight.bold,
              color: AppColors.darkGrey,
            ),
          ),
          SizedBox(height: 5 * scaleFactor),
          Text(
            statusSubtitle,
            style: TextStyle(
              fontSize: 13 * scaleFactor,
              color: AppColors.greyText,
            ),
          ),
          SizedBox(height: 15 * scaleFactor),
          LinearProgressIndicator(
            value:
                currentStep /
                totalSteps, // Adjusted total steps for the new stages
            backgroundColor: AppColors.lightOrange.withOpacity(0.5), // Lighter background
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.gojekGreen,
            ),
            minHeight: 8 * scaleFactor,
            borderRadius: BorderRadius.circular(10),
          ),
          SizedBox(height: 5 * scaleFactor),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Diterima', // Accepted
                style: TextStyle(
                  fontSize: 10 * scaleFactor,
                  color:
                      currentStep >= 1
                          ? AppColors.gojekGreen
                          : AppColors.greyText,
                ),
              ),
              Text(
                'Tiba Di Toko', // Arrived at Restaurant
                style: TextStyle(
                  fontSize: 10 * scaleFactor,
                  color:
                      currentStep >= 3
                          ? AppColors.gojekGreen
                          : AppColors.greyText,
                ),
              ),
              Text(
                'Diambil', // Picked Up
                style: TextStyle(
                  fontSize: 10 * scaleFactor,
                  color:
                      currentStep >= 4
                          ? AppColors.gojekGreen
                          : AppColors.greyText,
                ),
              ),
              Text(
                'Pengiriman', // On The Way To Destination
                style: TextStyle(
                  fontSize: 10 * scaleFactor,
                  color:
                      currentStep >= 5
                          ? AppColors.gojekGreen
                          : AppColors.greyText,
                ),
              ),
              Text(
                'Tiba', // Delivered
                style: TextStyle(
                  fontSize: 10 * scaleFactor,
                  color:
                      currentStep >= 6
                          ? AppColors.gojekGreen
                          : AppColors.greyText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Renamed from _buildSlidingPanel to _buildPanelContent as it's passed to SlidingUpPanel
  Widget _buildPanelContent(ScrollController scrollController, double scaleFactor) {
    return Column(
      children: [
        // Handle for dragging
        Center(
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 12.0 * scaleFactor),
            width: 40 * scaleFactor,
            height: 5 * scaleFactor,
            decoration: BoxDecoration(
              color: AppColors.greyText.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.symmetric(
              horizontal: 20 * scaleFactor,
              vertical: 10 * scaleFactor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detail Pesanan #${widget.orderId.substring(0, 8)}',
                  style: TextStyle(
                    fontSize: 20 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGrey,
                  ),
                ),
                SizedBox(height: 15 * scaleFactor),

                // Partner Info Card
                _buildInfoCard(
                  title: 'Informasi Penjual',
                  icon: Icons.store,
                  color: AppColors.primaryOrange,
                  scaleFactor: scaleFactor,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRowContent(
                        Icons.shop,
                        'Nama Penjual',
                        _orderData?['mitraname'] ?? 'N/A',
                        scaleFactor,
                      ),
                      _buildInfoRowContent(
                        Icons.location_on,
                        'Alamat Penjual',
                        _orderData?['pickup']?['address'] ?? 'N/A',
                        scaleFactor,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20 * scaleFactor),

                // Customer Delivery Info Card
                _buildInfoCard(
                  title: 'Informasi Pengiriman',
                  icon: Icons.home,
                  color: AppColors.infoBlue,
                  scaleFactor: scaleFactor,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRowContent(
                        Icons.person,
                        'Nama Penerima',
                        _orderData?['username'] ?? 'N/A', // Assuming username is directly available
                        scaleFactor,
                      ),
                      _buildInfoRowContent(
                        Icons.location_on,
                        'Alamat Tujuan',
                        _orderData?['destination']?['address'] ?? 'N/A',
                        scaleFactor,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20 * scaleFactor),

                // Driver Info Section (Conditional and in a card)
                _buildDriverInfoSection(scaleFactor),

                SizedBox(height: 20 * scaleFactor),

                // Order Summary Card
                _buildInfoCard(
                  title: 'Ringkasan Belanja',
                  icon: Icons.receipt,
                  color: AppColors.primaryOrange,
                  scaleFactor: scaleFactor,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOrderItemsList(scaleFactor),
                      Divider(height: 25 * scaleFactor, color: AppColors.lightOrange),
                      _buildPriceRow(
                        'Harga Makanan',
                        _calculateFoodPrice(),
                        scaleFactor: scaleFactor,
                      ),
                      _buildPriceRow(
                        'Biaya Pengiriman',
                        _deliveryFee,
                        scaleFactor: scaleFactor,
                      ),
                      Divider(height: 25 * scaleFactor, color: AppColors.lightOrange),
                      _buildPriceRow(
                        'Total Pembayaran',
                        _totalAmount,
                        isGrandTotal: true,
                        scaleFactor: scaleFactor,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 30 * scaleFactor),
                _buildActionButtons(scaleFactor),
                SizedBox(height: 30 * scaleFactor), // Extra space for bottom button
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Widget content,
    required Color color,
    required double scaleFactor,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(16 * scaleFactor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22 * scaleFactor),
                SizedBox(width: 10 * scaleFactor),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGrey,
                  ),
                ),
              ],
            ),
            Divider(height: 24 * scaleFactor),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRowContent(IconData icon, String label, String value, double scaleFactor) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0 * scaleFactor),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.greyText, size: 18 * scaleFactor),
          SizedBox(width: 8 * scaleFactor),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12 * scaleFactor,
                    color: AppColors.greyText,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14 * scaleFactor,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkGrey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _calculateFoodPrice() {
    double foodPrice = 0.0;
    for (var item in _orderItems) {
      foodPrice +=
          (item['price'] as num? ?? 0).toDouble() *
          (item['qty'] as num? ?? 0).toDouble();
    }
    return foodPrice;
  }

  Widget _buildDriverInfoSection(double scaleFactor) {
    return _buildInfoCard(
      title: 'Informasi Driver',
      icon: Icons.person_pin,
      color: AppColors.gojekGreen,
      scaleFactor: scaleFactor,
      content: _isLoadingOrderDetails
          ? _buildPlaceholderDriverInfo(scaleFactor)
          : (_isDriverFound && _driverName != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.gojekGreen.withOpacity(0.2),
                          radius: 25 * scaleFactor,
                          child: Icon(
                            Icons.person,
                            color: AppColors.gojekGreen,
                            size: 30 * scaleFactor,
                          ),
                        ),
                        SizedBox(width: 15 * scaleFactor),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _driverName!,
                              style: TextStyle(
                                fontSize: 16 * scaleFactor,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkGrey,
                              ),
                            ),
                            Text(
                              'Driver LhokRide+',
                              style: TextStyle(
                                fontSize: 13 * scaleFactor,
                                color: AppColors.greyText,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 15 * scaleFactor),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _makePhoneCall(_driverPhone!),
                            icon: Icon(Icons.call, size: 18 * scaleFactor),
                            label: Text(
                              'Telepon',
                              style: TextStyle(fontSize: 13 * scaleFactor),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.gojekGreen,
                              side: const BorderSide(color: AppColors.gojekGreen),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 10 * scaleFactor),
                            ),
                          ),
                        ),
                        SizedBox(width: 10 * scaleFactor),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _sendWhatsAppMessage(_driverPhone!),
                            icon: Icon(Icons.chat, size: 18 * scaleFactor),
                            label: Text(
                              'Chat',
                              style: TextStyle(fontSize: 13 * scaleFactor),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 10 * scaleFactor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SpinKitThreeBounce(color: AppColors.gojekGreen, size: 20 * scaleFactor),
                    SizedBox(width: 10 * scaleFactor),
                    Text(
                      'Menunggu Driver...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppColors.greyText,
                        fontSize: 14 * scaleFactor,
                      ),
                    ),
                  ],
                )),
    );
  }

  Widget _buildPlaceholderDriverInfo(double scaleFactor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.greyText.withOpacity(0.1),
              radius: 25 * scaleFactor,
            ),
            SizedBox(width: 15 * scaleFactor),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlaceholder(width: 120 * scaleFactor, height: 16 * scaleFactor),
                SizedBox(height: 5 * scaleFactor),
                _buildPlaceholder(width: 80 * scaleFactor, height: 14 * scaleFactor),
              ],
            ),
          ],
        ),
        SizedBox(height: 15 * scaleFactor),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildPlaceholder(width: 100 * scaleFactor, height: 40 * scaleFactor, borderRadius: 8),
            SizedBox(width: 10 * scaleFactor),
            _buildPlaceholder(width: 100 * scaleFactor, height: 40 * scaleFactor, borderRadius: 8),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceholder({double? width, double? height, double borderRadius = 4.0}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.lightOrange.withOpacity(0.3),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }


  Widget _buildOrderItemsList(double scaleFactor) {
    if (_orderItems.isEmpty) {
      return Text('Tidak ada item pesanan.', style: TextStyle(fontSize: 14 * scaleFactor, color: AppColors.greyText));
    }
    return Column(
      children:
          _orderItems.map<Widget>((item) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 5.0 * scaleFactor),
              child: Row(
                children: [
                  Text(
                    '${item['qty']}x',
                    style: TextStyle(
                      fontSize: 14 * scaleFactor,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                  SizedBox(width: 10 * scaleFactor),
                  Expanded(
                    child: Text(
                      item['name'],
                      style: TextStyle(
                        fontSize: 14 * scaleFactor,
                        color: AppColors.darkGrey,
                      ),
                    ),
                  ),
                  Text(
                    _formatCurrency(
                      (item['price'] as num? ?? 0).toDouble() *
                          (item['qty'] as num? ?? 0).toDouble(),
                    ),
                    style: TextStyle(
                      fontSize: 14 * scaleFactor,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _buildPriceRow(
    String label,
    double amount, {
    bool isGrandTotal = false,
    required double scaleFactor,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0 * scaleFactor),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isGrandTotal ? 16 * scaleFactor : 14 * scaleFactor,
              fontWeight: isGrandTotal ? FontWeight.bold : FontWeight.normal,
              color: isGrandTotal ? AppColors.darkGrey : AppColors.greyText,
            ),
          ),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
              fontSize: isGrandTotal ? 16 * scaleFactor : 14 * scaleFactor,
              fontWeight: isGrandTotal ? FontWeight.bold : FontWeight.normal,
              color: isGrandTotal ? AppColors.darkGrey : AppColors.greyText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(double scaleFactor) {
    List<Widget> buttons = [];

    if (_currentOrderStatus != _OrderStatus.delivered &&
        _currentOrderStatus != _OrderStatus.canceled) {
      if (_isDriverFound && _driverName != null) {
        buttons.add(
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _makePhoneCall(_driverPhone!),
              icon: Icon(Icons.phone, size: 18 * scaleFactor),
              label: Text('Telepon Driver', style: TextStyle(fontSize: 13 * scaleFactor)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gojekGreen,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12 * scaleFactor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        );
        buttons.add(SizedBox(width: 10 * scaleFactor));
        buttons.add(
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _sendWhatsAppMessage(_driverPhone!),
              icon: Icon(Icons.chat, size: 18 * scaleFactor),
              label: Text('Chat Driver', style: TextStyle(fontSize: 13 * scaleFactor)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentBlue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12 * scaleFactor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        );
      } else if (_currentOrderStatus == _OrderStatus.pending ||
          _currentOrderStatus == _OrderStatus.preparing) {
        // Option to cancel order if still pending or preparing
        buttons.add(
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                // Implement order cancellation logic
                // showDialog for confirmation, then update Firebase
                print('Cancel Order: ${widget.orderId}');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Fungsi batalkan pesanan belum diimplementasikan.',
                    ),
                  ),
                );
              },
              icon: Icon(Icons.cancel, color: Colors.red, size: 18 * scaleFactor),
              label: Text('Batalkan Pesanan', style: TextStyle(fontSize: 13 * scaleFactor)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: EdgeInsets.symmetric(vertical: 12 * scaleFactor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        );
      }
    } else if (_currentOrderStatus == _OrderStatus.delivered) {
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              context.go('/'); // Or navigate to order history
            },
            icon: Icon(Icons.thumb_up, size: 18 * scaleFactor),
            label: Text('Selesai', style: TextStyle(fontSize: 13 * scaleFactor)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12 * scaleFactor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      );
    } else if (_currentOrderStatus == _OrderStatus.canceled) {
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              context.go('/home'); // Or navigate to order history
            },
            icon: Icon(Icons.home, size: 18 * scaleFactor),
            label: Text('Kembali ke Beranda', style: TextStyle(fontSize: 13 * scaleFactor)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.greyText,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12 * scaleFactor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: buttons);
  }

  @override
  void dispose() {
    _mapDebounceTimer?.cancel();
    _disposeListeners(); // Centralized listener disposal
    _stopTimers(); // Centralized timer disposal
    // _panelAnimationController.dispose(); // No longer needed
    _fabAnimationController.dispose();
    _driverMarkerAnimationController.dispose();
    _radarAnimationController.dispose(); // Dispose radar animation controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double scaleFactor = screenWidth / 375.0; // Base width for scaling

    return Scaffold(
      extendBodyBehindAppBar: true, // Allows content to go behind app bar
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Make app bar transparent
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.darkGrey, size: 24 * scaleFactor),
          onPressed: () {
            context.pop();
          },
        ),
        title: Text(
          'Lacak Pesanan Anda',
          style: TextStyle(
            color: AppColors.darkGrey,
            fontWeight: FontWeight.bold,
            fontSize: 18 * scaleFactor,
          ),
        ),
        centerTitle: true,
      ),
      body: SlidingUpPanel(
        controller: _panelController,
        minHeight: MediaQuery.of(context).size.height * 0.30, // Adjusted min height for more info
        maxHeight: MediaQuery.of(context).size.height * 0.85, // Allow more space for details
        parallaxEnabled: true,
        parallaxOffset: 0.5,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 5,
          ),
        ],
        panelBuilder: (scrollController) => _buildPanelContent(scrollController, scaleFactor),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _partnerLocation ??
                    const LatLng(5.1787, 96.8833), // Default Lhokseumawe
                initialZoom: 13.0,
                maxZoom: 18.0,
                minZoom: 10.0,
                interactiveFlags:
                    InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                onMapEvent: (event) {
                  if (event is MapEventMoveEnd) {
                    _onMapMoved(event.camera);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app',
                  retinaMode: RetinaMode.isHighDensity(context),
                ),
                PolylineLayer(
                  polylines: [
                    if (_deliveryRoutePoints.isNotEmpty)
                      Polyline(
                        points: _deliveryRoutePoints,
                        strokeWidth: 5.0,
                        color: AppColors.gojekGreen,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // Partner Marker (Restaurant)
                    if (_partnerLocation != null)
                      Marker(
                        point: _partnerLocation!,
                        width: 60 * scaleFactor,
                        height: 60 * scaleFactor,
                        child: Column(
                          children: [
                            Icon(
                              Icons.storefront,
                              color: AppColors.primaryOrange,
                              size: 35 * scaleFactor,
                            ),
                            Text(
                              'Toko',
                              style: TextStyle(
                                color: AppColors.primaryOrange,
                                fontWeight: FontWeight.bold,
                                fontSize: 10 * scaleFactor,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Driver Marker (Conditional)
                    if (_driverLocation != null &&
                        _isDriverFound &&
                        (_currentOrderStatus == _OrderStatus.toRestaurant ||
                            _currentOrderStatus ==
                                _OrderStatus.arrivedAtRestaurant ||
                            _currentOrderStatus == _OrderStatus.pickedUp ||
                            _currentOrderStatus ==
                                _OrderStatus.onTheWayToDestination ||
                            _currentOrderStatus ==
                                _OrderStatus
                                    .accepted)) // Show driver if accepted too
                      Marker(
                        point: _driverLocation!,
                        width: 60 * scaleFactor,
                        height: 60 * scaleFactor,
                        child: AnimatedBuilder(
                          animation: _driverMarkerAnimationController,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _driverMarkerAnimation.value,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.directions_bike,
                                    color: AppColors.gojekGreen,
                                    size: 35 * scaleFactor,
                                  ),
                                  Text(
                                    'Driver',
                                    style: TextStyle(
                                      color: AppColors.gojekGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10 * scaleFactor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    else if (_partnerLocation != null &&
                        !_isDriverFound) // Show radar animation when no driver found, centered at partner
                      Marker(
                        point: _partnerLocation!,
                        width: 100 * scaleFactor,
                        height: 100 * scaleFactor,
                        child: AnimatedBuilder(
                          animation: _radarAnimationController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: 1.0 - _radarAnimation.value,
                              child: CustomPaint(
                                painter: RadarPainter(_radarAnimation.value),
                                child: Center(
                                  child: Icon(
                                    Icons.person_search,
                                    color: AppColors.gojekGreen.withOpacity(0.8),
                                    size: 35 * scaleFactor,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // User Delivery Location Marker
                    if (_userDeliveryLocation != null)
                      Marker(
                        point: _userDeliveryLocation!,
                        width: 60 * scaleFactor,
                        height: 60 * scaleFactor,
                        child: Column(
                          children: [
                            Icon(Icons.home, color: AppColors.infoBlue, size: 35 * scaleFactor),
                            Text(
                              'Anda',
                              style: TextStyle(
                                color: AppColors.infoBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 10 * scaleFactor,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Status Header
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(child: _buildStatusHeader(scaleFactor)),
            ),

            // Floating Action Button to toggle panel - remains for convenience, but SlidingUpPanel handles primary interaction
            Positioned(
              bottom: (MediaQuery.of(context).size.height * 0.30) + (16 * scaleFactor), // Adjust based on minHeight of panel
              right: 24 * scaleFactor,
              child: ScaleTransition(
                scale: _fabAnimation,
                child: FloatingActionButton(
                  onPressed: () {
                    if (_panelController.isPanelOpen) {
                      _panelController.close();
                      _fabAnimationController.reverse();
                    } else {
                      _panelController.open();
                      _fabAnimationController.forward();
                    }
                  },
                  backgroundColor: AppColors.primaryOrange,
                  child: Icon(
                    _panelController.isPanelOpen ? Icons.close : Icons.info_outline,
                    color: Colors.white,
                    size: 24 * scaleFactor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom Painter for Radar Animation
class RadarPainter extends CustomPainter {
  final double animationValue;

  RadarPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppColors.gojekGreen.withOpacity(0.5 * (1 - animationValue))
          ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * animationValue;

    canvas.drawCircle(center, radius, paint);

    final strokePaint =
        Paint()
          ..color = AppColors.gojekGreen.withOpacity(1.0 - animationValue)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    canvas.drawCircle(center, radius, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}