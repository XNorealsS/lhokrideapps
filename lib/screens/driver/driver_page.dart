// driver_page.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:lhokride/services/firebase_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../utils/route_utils.dart';
import 'DriverNavigation.dart'; // Assuming this is RideProgressScreen
import 'FoodNavigation.dart'; // Assuming this is FoodDeliveryProgressScreen
import '../../widgets/bottom_navigation.dart';
import '../../screens/webview_page.dart'; // Import the new WebviewPage

import 'package:intl/intl.dart'; // Format mata uang
import 'order_request_screen.dart'; // Import the new screen

class DriverPage extends StatefulWidget {
  @override
  _DriverPageState createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> with WidgetsBindingObserver {
  final _storage = const FlutterSecureStorage();
  final DatabaseReference _driverStatusRef = FirebaseDatabase.instance
      .ref()
      .child('drivers'); // Added for onDisconnect
  String _driverId = "";
  String _driverName = "Driver";
  String _status =
      "offline"; // offline, online, requested, accepted, in_progress, completed
  String? _currentOrderId;
  String _currentOrderType = ""; // "ride" or "food"
  String? _userRole;
  String? _passengerId;
  String _passengerName = "Passenger";
  Map<String, dynamic>? _currentRide;
  Map<String, dynamic>? _currentFoodOrder;

  StreamSubscription<DatabaseEvent>? _rideRequestListener;
  StreamSubscription<DatabaseEvent>? _foodOrderRequestListener;
  StreamSubscription<Position>?
  _positionStreamSubscription; // Changed to StreamSubscription
  bool _isOnlineSwitch = false; // To control the switch state
  bool _isRequestPopupShowing = false; // Prevent multiple popups

  // Driver details
  String _driverVehicle = "";
  String _driverPlateNumber = "";
  String _driverRating = "0.0";
  String _driverTotalTrips = "0";

  String _xpayBalance = "Rp 0"; // Saldo XPay

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeDriverData();
    _loadXpayBalance(); // Load balance on init
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rideRequestListener?.cancel();
    _foodOrderRequestListener?.cancel();
    _positionStreamSubscription?.cancel(); // Cancel location stream
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      print("App is paused. Driver ID: $_driverId, Online: $_isOnlineSwitch");
    } else if (state == AppLifecycleState.resumed) {
      print("App is resumed. Driver ID: $_driverId, Online: $_isOnlineSwitch");
      if (_isOnlineSwitch) {
        _checkLocationPermissionAndStartUpdates();
      }
    } else if (state == AppLifecycleState.detached) {
      print("App is detached. Attempting to set driver offline.");
    }
  }

  Future<void> _initializeDriverData() async {
    await FirebaseService.initialize(); // Ensure Firebase is initialized
    final storedDriverId = await _storage.read(key: 'user_id');
    final storedDriverName = await _storage.read(key: 'name');
    final storedUserRole = await _storage.read(key: 'role');

    // Retrieve driver details
    final storedDriverVehicle = await _storage.read(key: 'vehicle');
    final storedDriverPlateNumber = await _storage.read(key: 'plate_number');
    final storedDriverTotalTrips = await _storage.read(key: 'total_trips');

    setState(() {
      _driverId = storedDriverId ?? "";
      _driverName = storedDriverName ?? "Driver";
      _userRole = storedUserRole ?? "";
      _driverVehicle = storedDriverVehicle ?? "";
      _driverPlateNumber = storedDriverPlateNumber ?? "";
      _driverTotalTrips = storedDriverTotalTrips ?? "0";
    });

    if (_driverId.isNotEmpty) {
      _listenForDriverStatus(); // Listen for initial and subsequent status
      _setupFirebaseOnDisconnect(); // Set up onDisconnect for this driver
    }
  }

  Future<void> _loadXpayBalance() async {
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

  void _setupFirebaseOnDisconnect() {
    if (_driverId.isNotEmpty) {
      _driverStatusRef
          .child(_driverId)
          .child('status')
          .onDisconnect()
          .update({'isOnline': false, 'lastSeen': ServerValue.timestamp})
          .then((_) {
            print("Firebase onDisconnect for $_driverId set up successfully.");
          })
          .catchError((error) {
            print("Error setting up onDisconnect for $_driverId: $error");
          });
    }
  }

  void _listenForDriverStatus() {
    FirebaseService.getDatabaseRef()
        .child('drivers')
        .child(_driverId)
        .child('status')
        .onValue
        .listen((event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final Map<String, dynamic> statusData = Map<String, dynamic>.from(
              data,
            );
            bool newOnlineStatus = statusData['isOnline'] ?? false;
            setState(() {
              _isOnlineSwitch = newOnlineStatus;
              _status = _isOnlineSwitch ? "online" : "offline";
            });
            if (newOnlineStatus) {
              _startOrderListeners();
              _checkLocationPermissionAndStartUpdates();
            } else {
              _stopOrderListeners();
              _stopLocationUpdates();
            }
          }
        });
  }

  Future<void> _checkLocationPermissionAndStartUpdates() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showPermissionDeniedDialog(
        "Layanan lokasi dinonaktifkan. Mohon aktifkan layanan lokasi.",
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showPermissionDeniedDialog(
          "Izin lokasi ditolak. Aplikasi tidak dapat berfungsi tanpa izin lokasi.",
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showPermissionDeniedDialog(
        "Izin lokasi ditolak secara permanen. Silakan ubah dari pengaturan aplikasi.",
      );
      return;
    }

    if (_isOnlineSwitch) {
      _startLocationUpdates();
    }
  }

  void _startLocationUpdates() {
    if (_positionStreamSubscription != null) {
      return;
    }
    print("Starting location updates...");
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 10),
      ),
    ).listen(
      (Position position) {
        if (_isOnlineSwitch && _driverId.isNotEmpty) {
          print("Location update: ${position.latitude}, ${position.longitude}");
          FirebaseService.updateDriverLocation(
            _driverId,
            position.latitude,
            position.longitude,
          );
        } else {
          _positionStreamSubscription?.cancel();
          _positionStreamSubscription = null;
          print("Location updates stopped (driver offline).");
        }
      },
      onError: (e) {
        print("Error in location stream: $e");
      },
    );
  }

  void _stopLocationUpdates() {
    print("Stopping location updates...");
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }

  void _startOrderListeners() {
    if (_driverId.isEmpty) return;

    _rideRequestListener?.cancel();
    _foodOrderRequestListener?.cancel();

    print("🏍️🍔 Starting dual order listeners for driver $_driverId");

    Timer.periodic(Duration(seconds: 10), (timer) {
      if (_isOnlineSwitch) {
        FirebaseService.debugCheckDatabase(_driverId);
      } else {
        timer.cancel();
      }
    });

    _rideRequestListener = FirebaseService.listenForNewRideRequests(_driverId, (
      rideData,
    ) {
      print("🏍️ New PENDING Ride Request received: ${rideData['rideId']}");
      print("🏍️ Ride data: $rideData");

      if (!_isRequestPopupShowing && _currentOrderId == null) {
        print("🏍️ Showing ride request screen");
        _showOrderRequestScreen(rideData, 'ride');
      } else {
        print(
          "🏍️ Cannot show request: popup=$_isRequestPopupShowing, currentOrder=$_currentOrderId",
        );
      }
    });

    _foodOrderRequestListener = FirebaseService.listenForNewFoodOrderRequests(
      _driverId,
      (orderData) {
        print("🍔 New PENDING Food Order received: ${orderData['orderId']}");
        print("🍔 Order data: $orderData");

        if (!_isRequestPopupShowing && _currentOrderId == null) {
          print("🍔 Showing food order request screen");
          _showOrderRequestScreen(orderData, 'food');
        } else {
          print(
            "🍔 Cannot show request: popup=$_isRequestPopupShowing, currentOrder=$_currentOrderId",
          );
        }
      },
    );

    print("🏍️🍔 Listeners setup completed for driver $_driverId");
  }

  void _stopOrderListeners() {
    print("🛑 Stopping order listeners");
    _rideRequestListener?.cancel();
    _rideRequestListener = null;
    _foodOrderRequestListener?.cancel();
    _foodOrderRequestListener = null;
  }

  void _showOrderRequestScreen(
    Map<String, dynamic> orderData,
    String orderType,
  ) {
    if (_isRequestPopupShowing) {
      print("⚠️ Request screen is already showing, ignoring new request.");
      return;
    }

    if (_currentOrderId != null) {
      print(
        "⚠️ Driver is busy with order $_currentOrderId, ignoring new request.",
      );
      return;
    }

    setState(() {
      _isRequestPopupShowing = true;
      if (orderType == 'ride') {
        _currentRide = orderData;
        _currentFoodOrder = null;
      } else {
        _currentFoodOrder = orderData;
        _currentRide = null;
      }
    });

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder:
                (context) => OrderRequestScreen(
                  orderData: orderData,
                  orderType: orderType,
                  onAccept: () async {
                    Navigator.of(context).pop();
                    await _handleOrderAcceptance(
                      orderData,
                      orderType,
                      orderType == 'ride'
                          ? orderData['rideId']
                          : orderData['orderId'],
                      orderType == 'ride'
                          ? orderData['passenger']['name']
                          : orderData['user']['name'],
                    );
                  },
                  onReject: () async {
                    Navigator.of(context).pop();
                    await _handleOrderRejection(
                      orderType == 'ride'
                          ? orderData['rideId']
                          : orderData['orderId'],
                      orderType,
                    );
                  },
                ),
          ),
        )
        .then((_) {
          if (_isRequestPopupShowing) {
            setState(() {
              _isRequestPopupShowing = false;
            });
          }
        });
  }

  Future<void> _handleOrderRejection(String orderId, String orderType) async {
    setState(() {
      _isRequestPopupShowing = false;
      if (orderType == 'ride') {
        _currentRide = null;
      } else {
        _currentFoodOrder = null;
      }
    });

    if (orderType == 'ride') {
      await FirebaseService.updateRideStatus(orderId, {
        'status': 'rejected',
        'rejectedBy': _driverId,
        'rejectedAt': ServerValue.timestamp,
      });
    } else {
      await FirebaseService.updateFoodOrderStatus(orderId, {
        'status': 'rejected',
        'rejectedBy': _driverId,
        'rejectedAt': ServerValue.timestamp,
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${orderType == 'ride' ? 'Ride' : 'Food order'} ditolak.',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _handleOrderAcceptance(
    Map<String, dynamic> orderData,
    String orderType,
    String orderId,
    String customerName,
  ) async {
    setState(() {
      _isRequestPopupShowing = false;
      _status = "accepted";
      _currentOrderId = orderId;
      _currentOrderType = orderType;
    });

    _stopOrderListeners();

    final driverDataForFirebase = {
      'id': _driverId,
      'name': _driverName,
      'vehicle': _driverVehicle,
      'plate_number': _driverPlateNumber,
      'total_trips': int.tryParse(_driverTotalTrips) ?? 0,
    };

    try {
      if (orderType == 'ride') {
        await FirebaseService.updateRideStatus(orderId, {
          'status': 'accepted',
          'driver': driverDataForFirebase,
          'acceptedAt': ServerValue.timestamp,
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => RideProgressScreen(
                  rideId: orderId,
                  passengerName: customerName,
                  passengerId: orderData['passenger']['id'].toString(),
                  pickup: orderData['pickup'],
                  destination: orderData['destination'],
                ),
          ),
        ).then((_) {
          _handleOrderCompletion();
        });
      } else {
        await FirebaseService.updateFoodOrderStatus(orderId, {
          'status': 'accepted',
          'driver': driverDataForFirebase,
          'acceptedAt': ServerValue.timestamp,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Food order diterima! ID: $orderId'),
            backgroundColor: Colors.green,
          ),
        );

        print("=== Navigasi ke FoodDeliveryProgressScreen ===");
        print("Order ID                  : $orderId");
        print("Customer Name             : $customerName");
        print("User ID                   : ${orderData['user']['id']}");
        print(
          "User Phone Number         : ${orderData['user']['phone'] ?? ''}",
        );
        print(
          "Pickup Location           : ${Map<String, dynamic>.from(orderData['pickup'])}",
        );
        print(
          "Destination               : ${Map<String, dynamic>.from(orderData['destination'])}",
        );
        print("Order Items               : ${orderData['items']}");
        print("=============================================");

        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder:
                    (context) => FoodDeliveryProgressScreen(
                      orderId: orderId,
                      userName: customerName,
                      userId: orderData['user']['id'].toString(),
                      restaurantLocation: Map<String, dynamic>.from(
                        orderData['pickup'],
                      ),
                      userDestination: Map<String, dynamic>.from(
                        orderData['destination'],
                      ),
                      orderItems: orderData['items'],
                      userPhoneNumber: orderData['user']['phone'] ?? '',
                    ),
              ),
            )
            .then((_) {
              _handleOrderCompletion();
            });
      }
    } catch (e) {
      print("Error accepting order: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error menerima order: $e'),
          backgroundColor: Colors.red,
        ),
      );
      _handleOrderCompletion();
    }
  }

  void _handleOrderCompletion() {
    setState(() {
      _status = _isOnlineSwitch ? "online" : "offline";
      _currentRide = null;
      _currentFoodOrder = null;
      _currentOrderId = null;
      _currentOrderType = "";
    });

    if (_isOnlineSwitch) {
      _startOrderListeners();
    }
    _loadXpayBalance(); // Reload balance after order completion
  }

  void _showPermissionDeniedDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Izin Lokasi"),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                child: const Text("OK"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
    );
  }

  String _getStatusDisplayText() {
    switch (_status) {
      case "online":
        return "Menunggu pesanan...";
      case "accepted":
        return "Menangani ${_currentOrderType == 'ride' ? 'perjalanan' : 'pesanan makanan'}...";
      case "in_progress":
        return "Sedang dalam ${_currentOrderType == 'ride' ? 'perjalanan' : 'pengantaran'}...";
      default:
        return "Kamu sedang offline";
    }
  }

  Color _getStatusColor() {
    switch (_status) {
      case "online":
        return Colors.green;
      case "accepted":
      case "in_progress":
        return Colors.blue;
      default:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case "online":
        return Icons.motorcycle;
      case "accepted":
      case "in_progress":
        return _currentOrderType == 'ride'
            ? Icons.delivery_dining
            : Icons.restaurant;
      default:
        return Icons.offline_bolt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaTop = MediaQuery.of(context).padding.top;

    return WillPopScope(
      onWillPop: () async {
        if (_status == "accepted" ||
            _status == "in_progress" ||
            _isRequestPopupShowing) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selesaikan orderan terlebih dahulu.'),
              backgroundColor: Colors.orange.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: EdgeInsets.all(16),
            ),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: RefreshIndicator(
          onRefresh: () async {
          context.go('/');

            await Future.delayed(Duration(milliseconds: 500));
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Compact App Bar
              SliverAppBar(
                expandedHeight: screenHeight * 0.16,
                floating: true,
                pinned: true,
                elevation: 0,
                backgroundColor: const Color(0xFFF9A825),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFF9A825), Color(0xFFF57F17)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          screenWidth * 0.04,
                          screenHeight * 0.01,
                          screenWidth * 0.04,
                          screenHeight * 0.02,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Driver Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Halo, $_driverName!",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: screenWidth * 0.045,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: screenHeight * 0.005),
                                      Row(
                                        children: [
                                          Container(
                                            width: screenWidth * 0.02,
                                            height: screenWidth * 0.02,
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          SizedBox(width: screenWidth * 0.02),
                                          Text(
                                            _getStatusDisplayText(),
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.9,
                                              ),
                                              fontSize: screenWidth * 0.032,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Online Switch
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: screenWidth * 0.03,
                                    vertical: screenHeight * 0.008,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(
                                      screenWidth * 0.06,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _isOnlineSwitch ? "Online" : "Offline",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: screenWidth * 0.03,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(width: screenWidth * 0.02),
                                      Transform.scale(
                                        scale: 0.7,
                                        child: Switch(
                                          value: _isOnlineSwitch,
                                          onChanged: (newValue) async {
                                            HapticFeedback.lightImpact();
                                            setState(() {
                                              _isOnlineSwitch = newValue;
                                            });
                                            await FirebaseService.updateDriverStatus(
                                              _driverId,
                                              newValue,
                                            );
                                            if (newValue) {
                                              _checkLocationPermissionAndStartUpdates();
                                              _startOrderListeners();
                                            } else {
                                              _stopLocationUpdates();
                                              _stopOrderListeners();
                                              if (_isRequestPopupShowing) {
                                                Navigator.of(context).pop();
                                                _isRequestPopupShowing = false;
                                              }
                                            }
                                          },
                                          activeColor: Colors.white,
                                          activeTrackColor:
                                              Colors.green.shade400,
                                          inactiveThumbColor: Colors.white,
                                          inactiveTrackColor:
                                              Colors.red.shade300,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Content
              SliverPadding(
                padding: EdgeInsets.all(screenWidth * 0.04),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Balance Card - Compact
                    _buildCompactBalanceCard(screenWidth, screenHeight),

                    SizedBox(height: screenHeight * 0.015),

                    // Current Order or Status
                    if (_currentOrderId != null)
                      _buildCompactOrderCard(screenWidth, screenHeight)
                    else
                      _buildCompactStatusCard(screenWidth, screenHeight),

                    SizedBox(height: screenHeight * 0.02),

                    // Quick Actions Grid
                    _buildQuickActionsGrid(screenWidth, screenHeight),

                    SizedBox(height: screenHeight * 0.02),

                    // Driver Stats Card
                    _buildCompactDriverStats(screenWidth, screenHeight),

                    SizedBox(height: screenHeight * 0.03),

                    // Features Section
                    Text(
                      "Layanan Lainnya",
                      style: TextStyle(
                        fontSize: screenWidth * 0.042,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.015),

                    // Feature Grid
                    _buildFeatureGrid(context, screenWidth, screenHeight),

                    SizedBox(height: screenHeight * 0.02),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBalanceCard(double screenWidth, double screenHeight) {
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(screenWidth * 0.03),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Saldo XPay",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: screenWidth * 0.032,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.005),
                  Text(
                    _xpayBalance,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenWidth * 0.055,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _loadXpayBalance();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Saldo diperbarui"),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: EdgeInsets.all(16),
                    ),
                  );
                },
                child: Container(
                  padding: EdgeInsets.all(screenWidth * 0.02),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(screenWidth * 0.02),
                  ),
                  child: Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: screenWidth * 0.045,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: screenHeight * 0.02),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: _buildBalanceAction(
                  icon: Icons.arrow_upward,
                  label: "Tarik Dana",
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => WebviewPage(
                              url: 'https://lhokride.com/driver-withdraw',
                              Title: "Tarik Dana",
                            ),
                      ),
                    );
                  },
                  screenWidth: screenWidth,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: _buildBalanceAction(
                  icon: Icons.add,
                  label: "Isi Saldo",
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => WebviewPage(
                              url: 'https://lhokride.com/driver-topup',
                              Title: "Isi Saldo",
                            ),
                      ),
                    );
                  },
                  screenWidth: screenWidth,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required double screenWidth,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: screenWidth * 0.03,
          horizontal: screenWidth * 0.02,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(screenWidth * 0.02),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: screenWidth * 0.04),
            SizedBox(width: screenWidth * 0.02),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.032,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStatusCard(double screenWidth, double screenHeight) {
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(screenWidth * 0.03),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(screenWidth * 0.025),
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(screenWidth * 0.02),
            ),
            child: Icon(
              _getStatusIcon(),
              color: _getStatusColor(),
              size: screenWidth * 0.05,
            ),
          ),
          SizedBox(width: screenWidth * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusDisplayText(),
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(),
                  ),
                ),
                if (_status == "offline") ...[
                  SizedBox(height: screenHeight * 0.005),
                  Text(
                    "Aktifkan mode Online untuk menerima pesanan",
                    style: TextStyle(
                      fontSize: screenWidth * 0.03,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactOrderCard(double screenWidth, double screenHeight) {
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(screenWidth * 0.03),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(screenWidth * 0.02),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(screenWidth * 0.015),
                ),
                child: Icon(
                  _currentOrderType == 'ride'
                      ? Icons.motorcycle
                      : Icons.restaurant,
                  color: Colors.blue.shade700,
                  size: screenWidth * 0.04,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Pesanan Aktif",
                      style: TextStyle(
                        fontSize: screenWidth * 0.036,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    Text(
                      "ID: $_currentOrderId",
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  if (_currentOrderType == 'ride') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => RideProgressScreen(
                              rideId: _currentOrderId!,
                              passengerName: _passengerName,
                              passengerId: _passengerId ?? '',
                              pickup: _currentRide?['pickup'],
                              destination: _currentRide?['destination'],
                            ),
                      ),
                    ).then((_) => _handleOrderCompletion());
                  } else if (_currentOrderType == 'food') {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder:
                                (context) => FoodDeliveryProgressScreen(
                                  orderId: _currentOrderId!,
                                  userName: _passengerName,
                                  userId: _passengerId ?? '',
                                  restaurantLocation: Map<String, dynamic>.from(
                                    _currentFoodOrder!['pickup'],
                                  ),
                                  userDestination: Map<String, dynamic>.from(
                                    _currentFoodOrder!['destination'],
                                  ),
                                  orderItems: _currentFoodOrder!['items'],
                                  userPhoneNumber:
                                      _currentFoodOrder!['user']['phone'] ?? '',
                                ),
                          ),
                        )
                        .then((_) => _handleOrderCompletion());
                  }
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.03,
                    vertical: screenWidth * 0.02,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(screenWidth * 0.015),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Lihat",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: screenWidth * 0.03,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.01),
                      Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                        size: screenWidth * 0.035,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(double screenWidth, double screenHeight) {
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(screenWidth * 0.03),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Aksi Cepat",
            style: TextStyle(
              fontSize: screenWidth * 0.038,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.bar_chart,
                  label: "Statistik",
                  color: Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => WebviewPage(
                              url: 'https://lhokride.com/driver-stats',
                              Title: "Statistik",
                            ),
                      ),
                    );
                  },
                  screenWidth: screenWidth,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.history,
                  label: "Riwayat",
                  color: Colors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => WebviewPage(
                              url: 'https://lhokride.com/driver-history',
                              Title: "Riwayat",
                            ),
                      ),
                    );
                  },
                  screenWidth: screenWidth,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.card_giftcard,
                  label: "Bonus",
                  color: Colors.purple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => WebviewPage(
                              url: 'https://lhokride.com/driver-bonus',
                              Title: "Bonus",
                            ),
                      ),
                    );
                  },
                  screenWidth: screenWidth,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.help_outline,
                  label: "Bantuan",
                  color: Colors.red,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => WebviewPage(
                              url: 'https://lhokride.com/driver-help',
                              Title: "Bantuan",
                            ),
                      ),
                    );
                  },
                  screenWidth: screenWidth,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required double screenWidth,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: screenWidth * 0.12,
            height: screenWidth * 0.12,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(screenWidth * 0.02),
            ),
            child: Icon(icon, color: color, size: screenWidth * 0.06),
          ),
          SizedBox(height: screenWidth * 0.02),
          Text(
            label,
            style: TextStyle(
              fontSize: screenWidth * 0.028,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDriverStats(double screenWidth, double screenHeight) {
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(screenWidth * 0.03),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Info Pengemudi",
            style: TextStyle(
              fontSize: screenWidth * 0.038,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          Row(
            children: [
              _buildStatItem(
                label: "Kendaraan",
                value: _driverVehicle.isEmpty ? "-" : _driverVehicle,
                screenWidth: screenWidth,
              ),
            ],
          ),
          SizedBox(height: screenHeight * 0.01),
          Row(
            children: [
              _buildStatItem(
                label: "Plat",
                value: _driverPlateNumber.isEmpty ? "-" : _driverPlateNumber,
                screenWidth: screenWidth,
              ),
              _buildStatItem(
                label: "Perjalanan",
                value: _driverTotalTrips == "0" ? "0" : _driverTotalTrips,
                screenWidth: screenWidth,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required double screenWidth,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: screenWidth * 0.03,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: screenWidth * 0.01),
          Text(
            value,
            style: TextStyle(
              fontSize: screenWidth * 0.034,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureGrid(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    final features = [
      {
        'icon': Icons.confirmation_number,
        'title': 'Voucher',
        'url': 'https://lhokride.com/driver-vouchers',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(screenWidth * 0.03),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: features.length,
        separatorBuilder:
            (context, index) => Divider(
              height: 1,
              color: Colors.grey.shade200,
              indent: screenWidth * 0.04,
              endIndent: screenWidth * 0.04,
            ),
        itemBuilder: (context, index) {
          final feature = features[index];
          return ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.04,
              vertical: screenHeight * 0.008,
            ),
            leading: Container(
              width: screenWidth * 0.1,
              height: screenWidth * 0.1,
              decoration: BoxDecoration(
                color: const Color(0xFFE48700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(screenWidth * 0.02),
              ),
              child: Icon(
                feature['icon'] as IconData,
                color: const Color(0xFFE48700),
                size: screenWidth * 0.05,
              ),
            ),
            title: Text(
              feature['title'] as String,
              style: TextStyle(
                fontSize: screenWidth * 0.036,
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: screenWidth * 0.035,
              color: Colors.grey[400],
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => WebviewPage(
                        url: feature['url'] as String,
                        Title: feature['title'] as String,
                      ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
