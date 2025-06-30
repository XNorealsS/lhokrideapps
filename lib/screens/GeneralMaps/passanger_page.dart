import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:lhokride/services/firebase_service.dart';
import 'package:lhokride/utils/location_utils.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import '../driver/component/chat_dialog.dart';

import '../../utils/route_utils.dart';

// --- AppColors and MarkerTailPainter (No change, good as is) ---
class AppColors {
  static const Color primaryOrange = Color(0xFFFF8C00); // Main orange
  static const Color lightOrange = Color(0xFFFFE0B2); // Very light orange
  static const Color darkerOrange = Color(0xFFE67E22); // Slightly darker orange
  static const Color accentBlue = Color(0xFF2196F3); // Blue for accents/links
  static const Color mutedGreen = Color(0xFF4CAF50); // Green for success/info
  static const Color destinationRed = Color(
    0xFFF44336,
  ); // Red for destination/cancel
  static const Color lightGrey = Color(0xFFF5F5F5); // Very light grey
  static const Color mediumGrey = Color(0xFFBDBDBD); // Medium grey
  static const Color darkGrey = Color(0xFF616161); // Dark grey for text
  static const Color textBlack = Color(
    0xFF333333,
  ); // Near black for primary text
  static const Color white = Color(0xFFFFFFFF); // White
}

class MarkerTailPainter extends CustomPainter {
  final Color color;

  MarkerTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    final path = ui.Path();

    path.moveTo(size.width / 2, size.height);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is MarkerTailPainter && oldDelegate.color != color;
  }
}

// Retained for future potential, but only 'ride' is used
// User requested ride-only page, so food, send, mart modes are removed from UI.
enum RideMode {
  ride,
  // food,
  // send,
  // mart,
}

enum RideRequestStep {
  selectPickup,
  selectDestination,
  confirmRide,
  selectPayment,
  inRide,
}

class PassengerPage extends StatefulWidget {
  final RideMode mode;
  final LatLng? initialPickup;
  final LatLng? initialDestination;

  const PassengerPage({
    Key? key,
    required this.mode,
    this.initialPickup,
    this.initialDestination,
  }) : super(key: key);

  @override
  _PassengerPageState createState() => _PassengerPageState();
}

class _PassengerPageState extends State<PassengerPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _destinationFocusNode = FocusNode();

  bool _showMapInstructions = true;
  Color _crosshairColor = AppColors.mutedGreen;

  late AnimationController _crosshairController;

  LatLng? _currentLocation;
  LatLng? _pickupLocation;
  String? _selectedPickupAddress; // This now holds the resolved address
  LatLng? _destinationLocation;
  String? _selectedDestinationAddress; // This now holds the resolved address

  String _passengerId = "";
  String _token = "";
  String _passengerName = "Penumpang";
  String _rideStatus = "idle";
  String? _rideId;
  String? _driverId;
  String? _driverName;
  String? _driverPlateNumber; // Added for driver details
  String? _driverVehicle; // Added for driver details
  double? _driverRating; // Placeholder for driver rating
  int? _driverTotalTrips; // Placeholder for driver total trips

  // Driver Location State
  LatLng? _driverLocation;
  double? _driverBearing; // To store driver's bearing for marker rotation

  MapController _mapController = MapController();
  List<LatLng> _routePoints = [];
  double _distance = 0;
  int _eta = 0;
  int _price = 0;

  bool _isMapReady = false;
  bool _isMapMoving = false;
  Timer? _mapMoveDebounce;
  bool _showPickupDropdown = false;
  bool _showDestinationDropdown = false;
  bool _isInitialized = false;
  bool _isSearchingAddress =
      false; // NEW: State to indicate if an address search is active

  List<Map<String, dynamic>> _pickupSuggestions = [];
  List<Map<String, dynamic>> _destinationSuggestions = [];

  Timer? _searchDebounce;
  Timer? _addressLookupDebounce; // New: Debounce for reverse geocoding

  double _bottomPanelSize = 0.2; // Default size for initial idle state

  RideRequestStep _currentStep = RideRequestStep.selectPickup;

  StreamSubscription? _rideStatusListener;
  StreamSubscription?
  _driverLocationListener; // New: Listener for driver location

  // New: Payment related states
  String _selectedPaymentMethod = 'cash'; // 'cash' or 'xpay'
  double _userBalance = 0.0;
  bool _isLoadingBalance = false;
  bool _isLookingUpAddress = false; // New: State for address lookup

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _getCurrentLocation();
      _fetchWalletBalance(); // Fetch balance on resume
    }
  }

@override
void didChangeMetrics() {
  final viewInsets = MediaQuery.of(context).viewInsets;
  final isKeyboardOpen = viewInsets.bottom > 0;

  setState(() {
    if (isKeyboardOpen && _isSearchingAddress) {
      // Keyboard is open AND user is actively searching,
      // shrink panel to a minimal size (e.g., 15% of screen height)
      // to make space for suggestions and prevent it from covering them.
      _bottomPanelSize = 0.15; //
    } else {
      // Keyboard is closed OR not in active search mode.
      // Return panel to size appropriate for the current step.
      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep); //

      // Optional: check route if not yet calculated
      if (_currentStep == RideRequestStep.confirmRide &&
          _pickupLocation != null &&
          _destinationLocation != null &&
          _routePoints.isEmpty) {
        _calculateRoute(); //
      }
    }
  });
}

  // UPDATED: Adjusted panel sizes for the new UI
  double _getDefaultBottomPanelSizeForStep(RideRequestStep step) {
    switch (step) {
      case RideRequestStep.selectPickup:
      case RideRequestStep.selectDestination:
        return 0.25;
      case RideRequestStep.confirmRide:
        return 0.48; // Increased size for the new Gojek-style panel
      case RideRequestStep.selectPayment:
        return 0.45;
      case RideRequestStep.inRide:
        return 0.35;
      default:
        return 0.25;
    }
  }

  Future<LatLng?> getCurrentUserLocation() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return LatLng(position.latitude, position.longitude);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAnimations();
    _initializeApp();
    _pickupFocusNode.addListener(_onPickupFocusChanged);
    _destinationFocusNode.addListener(_onDestinationFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Handle initial deep links or pre-selected locations
      if (widget.initialPickup != null) {
        setState(() {
          _pickupLocation = widget.initialPickup;
          _currentStep = RideRequestStep.selectDestination; // Move to next step
        });
        _reverseGeocodeAndSetAddress(_pickupLocation!, isPickup: true);
      }
      if (widget.initialDestination != null) {
        setState(() {
          _destinationLocation = widget.initialDestination;
          _currentStep = RideRequestStep.confirmRide; // Move to confirm step
        });
        _reverseGeocodeAndSetAddress(_destinationLocation!, isPickup: false);
        // If both are initially set, calculate route
        if (widget.initialPickup != null && widget.initialDestination != null) {
          _calculateRoute();
        }
      }

      if (_rideId != null) {
        _listenForRideUpdates();
      }
    });
  }

void _onPickupFocusChanged() {
  setState(() {
    _showPickupDropdown = _pickupFocusNode.hasFocus;
    _showDestinationDropdown = false; // Hide other dropdown
    _isSearchingAddress = _pickupFocusNode.hasFocus; // Set search state
    if (_pickupFocusNode.hasFocus) {
      _currentStep = RideRequestStep.selectPickup;
      _crosshairColor = AppColors.mutedGreen;
      _showMapInstructions = true;
      _bottomPanelSize = 0.15; // <<< CHANGE THIS LINE
    } else {
      _showMapInstructions = false;
      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep);
    }
  });
}

void _onDestinationFocusChanged() {
  setState(() {
    _showDestinationDropdown = _destinationFocusNode.hasFocus;
    _showPickupDropdown = false; // Hide other dropdown
    _isSearchingAddress = _destinationFocusNode.hasFocus; // Set search state
    if (_destinationFocusNode.hasFocus) {
      _currentStep = RideRequestStep.selectDestination;
      _crosshairColor = AppColors.destinationRed;
      _showMapInstructions = true;
      _bottomPanelSize = 0.15; // <<< CHANGE THIS LINE
    } else {
      _showMapInstructions = false;
      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep);
    }
  });
}

  void _initializeAnimations() {
    _crosshairController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  Future<void> _initializeApp() async {
    await _loadUserData();
    await _getCurrentLocation();
    await LocationUtils.loadLocationData();
    await _initializeFirebase();
    await _fetchWalletBalance(); // Fetch wallet balance on app start

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp();
      // Only initialize FirebaseService once after Firebase.initializeApp()
      await FirebaseService.initialize();
    } catch (e) {
      print('Firebase initialization error: $e');
      // Potentially show a user-friendly error message
    }
  }

  Future<void> _loadUserData() async {
    final userId = await _storage.read(key: 'user_id');
    final name = await _storage.read(key: 'name');
    final token = await _storage.read(key: 'token');

    if (mounted) {
      setState(() {
        _token = token ?? "";
        _passengerId = userId ?? "";
        _passengerName = name ?? "Penumpang";
      });
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
      _showInstructionSnackbar(
        'Gagal memuat saldo: ${e.toString()}',
        color: AppColors.destinationRed,
      );
    } finally {
      if (mounted) setState(() => _isLoadingBalance = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showInstructionSnackbar(
            "Izin lokasi ditolak. Aplikasi tidak bisa berfungsi.",
            color: AppColors.destinationRed,
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showInstructionSnackbar(
          "Izin lokasi ditolak permanen. Silakan ubah di pengaturan.",
          color: AppColors.destinationRed,
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        if (_isMapReady) {
          _mapController.move(_currentLocation!, 15.0);
        }
      });
      print("[LOKASI] Lokasi awal ditemukan: $_currentLocation");
    } catch (e) {
      print("[LOKASI] Error mendapatkan lokasi awal: $e");
      _showInstructionSnackbar(
        "Gagal mendapatkan lokasi Kamu. Pastikan GPS aktif.",
        color: AppColors.destinationRed,
      );
    }
  }

  void _onMapMoveStart() {
    _mapMoveDebounce?.cancel();
    setState(() {
      _isMapMoving = true;
      _crosshairController.forward(from: 0.0);
    });
  }

  void _onMapMoveEnd() async {
    print("Peta berhenti bergerak");
    setState(() {
      _isMapMoving = false;
    });

    if (_currentStep == RideRequestStep.selectPickup ||
        _currentStep == RideRequestStep.selectDestination) {
      _selectLocationFromMapCenter();
    }
    _crosshairController.reverse();
  }

  void _calculateRoute() async {
    if (_pickupLocation == null || _destinationLocation == null) {
      setState(() {
        _routePoints.clear();
        _distance = 0.0;
        _eta = 0;
        _price = 0;
      });
      return;
    }

    if (_selectedPickupAddress == "Mencari alamat..." ||
        _selectedDestinationAddress == "Mencari alamat...") {
      _showInstructionSnackbar(
        "Mohon tunggu, sedang mencari alamat lengkap lokasi jemput/tujuan.",
        color: AppColors.primaryOrange,
      );
      return;
    }

    print("[APP] Memulai _calculateRoute...");
    setState(() {
      _currentStep = RideRequestStep.confirmRide;
      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep);
    });

    try {
      final routeData = await RouteUtils.calculateRoute(
        _pickupLocation!,
        _destinationLocation!,
      );

      final distance = routeData['distance'] as double;
      final eta = routeData['eta'] as int;
      final routePoints = routeData['routePoints'] as List<LatLng>;
      final price = await RouteUtils.calculateDynamicPrice(distance);

      setState(() {
        _routePoints = routePoints;
        _distance = distance;
        _eta = eta;
        _price = price;
      });

      print("[APP] Rute berhasil dihitung dan diperbarui. Harga: Rp $_price");
      _fitMapToBounds();
    } catch (e) {
      print("[APP] Gagal menghitung rute: $e");
      _showInstructionSnackbar(
        "Gagal menghitung rute: ${e.toString().split(':').last}",
        color: AppColors.destinationRed,
      );
      setState(() {
        _routePoints.clear();
        _distance = 0.0;
        _eta = 0;
        _price = 0;
      });
    }
  }

  Future<void> _requestRide() async {
    if (_pickupLocation == null || _destinationLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Silakan pilih lokasi jemput dan tujuan"),
          ),
        );
      }
      return;
    }

    if (_selectedPaymentMethod == 'xpay' && _userBalance < _price) {
      _showInstructionSnackbar(
        "Saldo XPay tidak cukup untuk perjalanan ini. Silakan top up atau pilih Tunai.",
        color: AppColors.destinationRed,
      );
      return;
    }

    setState(() {
      _rideStatus = "searching";
      _currentStep = RideRequestStep.inRide;
      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep);
    });

    try {
      final response = await http.post(
        Uri.parse('http://api.lhokride.com/api/rides/request'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'passengerId': _passengerId,
          'passengerName': _passengerName,
          'pickup': {
            'latitude': _pickupLocation!.latitude,
            'longitude': _pickupLocation!.longitude,
            'address': _selectedPickupAddress,
          },
          'destination': {
            'latitude': _destinationLocation!.latitude,
            'longitude': _destinationLocation!.longitude,
            'address': _selectedDestinationAddress,
          },
          'distance': _distance,
          'estimatedPrice': _price,
          'paymentMethod': _selectedPaymentMethod, // Include payment method
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        if (data['success'] == false) {
          if (mounted) {
            setState(() {
              _rideStatus = "idle";
              _currentStep = RideRequestStep.confirmRide;
              _bottomPanelSize = _getDefaultBottomPanelSizeForStep(
                _currentStep,
              );
            });
          }

          _showInstructionSnackbar(
            data['message'] ?? "Tidak ada driver dalam jangkauan.",
            color: AppColors.destinationRed,
          );
        } else {
          if (mounted) {
            setState(() {
              if (data['ride'] != null && data['ride']['rideId'] != null) {
                _rideId =
                    data['ride']['rideId']; // Case: successful with drivers
              } else if (data['rideId'] != null) {
                _rideId = data['rideId'];
              } else {
                print(
                  "Peringatan: rideId tidak ditemukan di respons yang diharapkan.",
                );
                _rideId = null; // Or handle as an error
              }

              print('Permintaan perjalanan dikirim... $_rideId');

              if (data['success'] == false) {
                _showInstructionSnackbar(
                  data['message'] ?? "Tidak ada driver dalam jangkauan.",
                  color: AppColors.destinationRed,
                );
                _currentStep =
                    RideRequestStep.confirmRide; 
                _bottomPanelSize = _getDefaultBottomPanelSizeForStep(
                  _currentStep,
                );
              }
            });
          }
          if (_rideId != null &&
              (data['success'] == null || data['success'] == true)) {
            _listenForRideUpdates();
          } else if (_rideId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Gagal mendapatkan ID perjalanan. Coba lagi."),
                backgroundColor: AppColors.destinationRed,
              ),
            );
          }
        }
      } else {
        throw Exception(
          'Gagal memesan perjalanan: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _rideStatus = "idle";
          _currentStep = RideRequestStep.confirmRide; // Go back to confirm ride
          _routePoints.clear();
          _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Gagal memesan perjalanan: $e")));
      }
    }
  }

  void _listenForRideUpdates() {
    if (_rideId == null) {
      print('rideId masih null, tidak bisa mendengarkan update.');
      return;
    }

    _rideStatusListener?.cancel(); 
    _driverLocationListener
        ?.cancel();

    _rideStatusListener = FirebaseService.listenToRideStatus(_rideId!, (ride) {
      if (mounted) {
        setState(() {
          final status = ride['status'] ?? "idle";

          if (status == 'requested')
            return;

          _rideStatus = status;
          _driverId = ride['driver']?['id'];
          _driverName = ride['driver']?['name'];
          _driverPlateNumber = ride['driver']?['plate_number'];
          _driverVehicle = ride['driver']?['vehicle'];
          _driverTotalTrips =
              ride['driver']?['total_trips'];
          _driverRating =
              (ride['driver']?['rating'] as num?)?.toDouble();

          if (status == 'accepted' ||
              status == 'driver_arrived' ||
              status == 'in_progress') {
            _showInstructionSnackbar(
              'Perjalanan diterima oleh ${ride['driver']['name'] ?? "pengemudi"}!',
              color: AppColors.mutedGreen,
            );
            if (_driverId != null && _driverLocationListener == null) {
              _listenToDriverLocation(_driverId!);
            }
          } else if (status == 'completed') {
            _showInstructionSnackbar('Perjalanan selesai. Terima kasih!');
            _resetToInitialState();
            _fetchWalletBalance(); 
            context.go('/'); 
          } else if (status == 'cancelled') {
            _showInstructionSnackbar(
              'Perjalanan dibatalkan.',
              color: AppColors.destinationRed,
            );
            _resetToInitialState();
            _fetchWalletBalance();
          }
        });
      }
    });
  }

  void _listenToDriverLocation(String driverId) {
    _driverLocationListener
        ?.cancel(); 

    _driverLocationListener = FirebaseService.listenToDriverLocation(driverId, (
      data,
    ) {
      if (mounted && data != null) {
        final lat = data['latitude'] as double?;
        final lon = data['longitude'] as double?;
        final bearing = data['bearing'] as double?;

        if (lat != null && lon != null) {
          setState(() {
            _driverLocation = LatLng(lat, lon);
            _driverBearing = bearing;
          });
        }
      }
    });
  }

  Future<void> _cancelRide() async {
    if (_rideId == null) {
      _resetToInitialState();
      return;
    }
    try {
      final response = await http.post(
        Uri.parse('http://api.lhokride.com/api/rides/$_rideId/cancel'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'passengerId': _passengerId,
          'reason': 'Dibatalkan oleh penumpang',
        }),
      );

      print('Cancel Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        setState(() {
          _rideStatus = "cancelled";
          _resetToInitialState();
        });
      }
      _resetToInitialState(); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Gagal membatalkan perjalanan: $e"),
          backgroundColor: AppColors.destinationRed,
        ),
      );
      _resetToInitialState();
    }
  }

  void _onSearchChanged(String value, bool isPickup) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        if (isPickup) {
          _showPickupDropdown = value.isNotEmpty;
          _pickupSuggestions = [];
        } else {
          _showDestinationDropdown = value.isNotEmpty;
          _destinationSuggestions = [];
        }
        _isSearchingAddress =
            value.isNotEmpty; 
      });
      if (value.isNotEmpty) {
        try {
          final suggestions = await RouteUtils.smartSearch(value);
          if (mounted &&
              ((isPickup && value == _pickupController.text) ||
                  (!isPickup && value == _destinationController.text))) {
            setState(() {
              if (isPickup) {
                _pickupSuggestions = suggestions;
              } else {
                _destinationSuggestions = suggestions;
              }
            });
          }
        } catch (e) {
          print("Error fetching suggestions: $e");
        }
      }
    });
  }

  Future<void> _reverseGeocodeAndSetAddress(
    LatLng location, {
    required bool isPickup,
  }) async {
    setState(() {
      _isLookingUpAddress = true;
      if (isPickup) {
        _selectedPickupAddress = "Mencari alamat...";
        _pickupController.text = "Mencari alamat...";
      } else {
        _selectedDestinationAddress = "Mencari alamat...";
        _destinationController.text = "Mencari alamat...";
      }
    });

    _addressLookupDebounce?.cancel(); 
    _addressLookupDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final result = await RouteUtils.reverseGeocode(location);
        final address = result ?? "Alamat tidak ditemukan";

        if (mounted) {
          setState(() {
            if (isPickup) {
              _selectedPickupAddress = address;
              _pickupController.text = address;
            } else {
              _selectedDestinationAddress = address;
              _destinationController.text = address;
            }
          });
        }
      } catch (e) {
        print("Error reverse geocoding: $e");
        if (mounted) {
          setState(() {
            if (isPickup) {
              _selectedPickupAddress = "Gagal mendapatkan alamat";
              _pickupController.text = "Gagal mendapatkan alamat";
            } else {
              _selectedDestinationAddress = "Gagal mendapatkan alamat";
              _destinationController.text = "Gagal mendapatkan alamat";
            }
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLookingUpAddress = false;
          });
        }
      }
    });
  }

void _selectLocationFromSuggestion(
  Map<String, dynamic> location,
  bool isPickup,
) {
  final lat = location.parseDouble('lat');
  final lon = location.parseDouble('lon');
  if (lat != null && lon != null) {
    final newLocation = LatLng(lat, lon);
    final address =
        location['fullName'] ?? location['name'] ?? "Lokasi Dipilih";

    setState(() {
      if (isPickup) {
        _pickupLocation = newLocation; 
        _selectedPickupAddress = address; 
        _pickupController.text = address; 
        _showPickupDropdown = false; 
        _currentStep = RideRequestStep.selectDestination; 
        _crosshairColor = AppColors.destinationRed; 
        _showMapInstructions = true;
      } else {
        _destinationLocation = newLocation; 
        _selectedDestinationAddress = address;
        _destinationController.text = address; 
        _showDestinationDropdown = false; 
        if (_pickupLocation != null) { 
          _currentStep = RideRequestStep.confirmRide; 
          _showMapInstructions = false;
        }
      }
      _isSearchingAddress = false; 
      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep); 
    });
    _mapController.move(newLocation, 16); 
    FocusScope.of(context).unfocus(); 
    _updateCrosshairAndInstructions(); 
    if (_currentStep == RideRequestStep.confirmRide) {
      _calculateRoute();
    }
  }
}

  void _handleMapTap(TapPosition tapPosition, LatLng latlng) {
    if (!_isMapReady || _rideStatus != "idle") return;

    if (_currentStep == RideRequestStep.confirmRide ||
        _currentStep == RideRequestStep.inRide ||
        _currentStep == RideRequestStep.selectPayment) {
      return;
    }
    _crosshairController.forward().then((_) => _crosshairController.reverse());

    if (_currentStep == RideRequestStep.selectPickup) {
      _pickupLocation = latlng;
    } else if (_currentStep == RideRequestStep.selectDestination) {
      _destinationLocation = latlng;
    }
    _reverseGeocodeAndSetAddress(latlng, isPickup: isPickupStep);

    setState(() {
      _showMapInstructions = false; 
    });
    _updateCrosshairAndInstructions();
  }

  void _selectLocationFromMapCenter() async {
    if (!_isMapReady || _mapController.center == null) return;

    final center = _mapController.center!;
    print("Memilih lokasi dari pusat peta: $center");

    if (_currentStep == RideRequestStep.selectPickup) {
      _pickupLocation = center;
    } else if (_currentStep == RideRequestStep.selectDestination) {
      _destinationLocation = center;
    }
    _reverseGeocodeAndSetAddress(center, isPickup: isPickupStep);

    setState(() {
      _showMapInstructions =
          (isPickupStep && _pickupLocation == null) ||
          (isDestinationStep && _destinationLocation == null);
    });

    _updateCrosshairAndInstructions();
    FocusScope.of(context).unfocus();
  }

  bool get isPickupStep => _currentStep == RideRequestStep.selectPickup;
  bool get isDestinationStep =>
      _currentStep == RideRequestStep.selectDestination;

  void _updateCrosshairAndInstructions() {
    setState(() {
      if (isPickupStep) {
        _crosshairColor = AppColors.mutedGreen;
        _showMapInstructions = _pickupLocation == null;
      } else if (isDestinationStep) {
        _crosshairColor = AppColors.destinationRed;
        _showMapInstructions = _destinationLocation == null;
      } else {
        _showMapInstructions = false;
      }
      print("Current step: $_currentStep");
    });
  }

  void _fitMapToBounds() {
    if (_pickupLocation != null &&
        _destinationLocation != null &&
        _routePoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(_routePoints);
      bounds.extend(_pickupLocation!);
      bounds.extend(_destinationLocation!);

      final padding = MediaQuery.of(context).size.width * 0.15;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.only(
            left: padding,
            right: padding,
            top: MediaQuery.of(context).padding.top + kToolbarHeight,
            bottom:
                _bottomPanelSize * MediaQuery.of(context).size.height + padding,
          ),
          maxZoom: 16.0,
        ),
      );
    } else if (_pickupLocation != null) {
      _mapController.move(_pickupLocation!, 16.0);
    } else if (_destinationLocation != null) {
      _mapController.move(_destinationLocation!, 16.0);
    }
  }

  void _showInstructionSnackbar(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color ?? AppColors.primaryOrange,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _resetToInitialState() {
    setState(() {
      _pickupLocation = null;
      _selectedPickupAddress = null;
      _destinationLocation = null;
      _selectedDestinationAddress = null;
      _pickupController.clear();
      _destinationController.clear();
      _routePoints.clear();
      _distance = 0.0;
      _eta = 0;
      _price = 0;
      _rideStatus = "idle";
      _currentStep = RideRequestStep.selectPickup;
      _crosshairColor = AppColors.mutedGreen;
      _showMapInstructions = true;
      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(
        _currentStep,
      );
      _pickupSuggestions.clear();
      _destinationSuggestions.clear();
      _showPickupDropdown = false;
      _showDestinationDropdown = false;
      _isMapMoving = false;
      _selectedPaymentMethod = 'cash'; 
      _isLookingUpAddress = false; 
      _isSearchingAddress = false;

      _driverId = null;
      _driverName = null;
      _driverPlateNumber = null;
      _driverVehicle = null;
      _driverRating = null;
      _driverTotalTrips = null;
      _driverLocation = null; 
      _driverBearing = null;
    });
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    }
    _searchDebounce?.cancel();
    _mapMoveDebounce?.cancel();
    _addressLookupDebounce?.cancel(); 
    _driverLocationListener?.cancel(); 
    _rideStatusListener?.cancel();
  }

  @override
  void dispose() {
    _crosshairController.dispose();
    _rideStatusListener?.cancel();
    _driverLocationListener?.cancel();
    _pickupController.dispose();
    _destinationController.dispose();
    _searchDebounce?.cancel();
    _mapMoveDebounce?.cancel();
    _addressLookupDebounce?.cancel();
    _pickupFocusNode.removeListener(_onPickupFocusChanged);
    _destinationFocusNode.removeListener(_onDestinationFocusChanged);
    _pickupFocusNode.dispose();
    _destinationFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),
          if (!_isMapReady)
            Positioned.fill(
              child: Container(
                color: AppColors.primaryOrange,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      SizedBox(height: 16),
                      Text(
                        "Menyiapkan Peta...",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _buildSearchAndSuggestions(),
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndSuggestions() {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    double maxSuggestionHeight =
        screenHeight * 0.8 - topPadding - kToolbarHeight;
    if (keyboardHeight > 0) {
      maxSuggestionHeight =
          screenHeight - topPadding - keyboardHeight - 100;
    }

    return Positioned(
      top: topPadding + 12, 
      left: 12, 
      right: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          if ((_showPickupDropdown && _pickupSuggestions.isNotEmpty) ||
              (_showDestinationDropdown && _destinationSuggestions.isNotEmpty))
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSuggestionHeight),
              child: _buildSuggestionList(
                suggestions:
                    isPickupStep ? _pickupSuggestions : _destinationSuggestions,
                isPickup: isPickupStep,
                showDropdown: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            center: _currentLocation ?? LatLng(5.1787, 96.8833),
            zoom: 15.0,
            minZoom: 10.0,
            maxZoom: 18.0,
            interactiveFlags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
            onTap: _handleMapTap,
            onPositionChanged: (position, hasGesture) {
              if (_rideStatus == "idle" &&
                  (isPickupStep || isDestinationStep)) {
                if (hasGesture) {
                  if (!_isMapMoving) {
                    _onMapMoveStart();
                  }
                  _mapMoveDebounce?.cancel();
                  _mapMoveDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      if (mounted && _isMapMoving) {
                        _onMapMoveEnd();
                      }
                    },
                  );
                }
              }
            },
            onMapReady: () {
              setState(() => _isMapReady = true);
              if (_currentLocation != null) {
                _mapController.move(_currentLocation!, 15.0);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.lhokrideplus.lsm',
              additionalOptions: const {
                'attribution': '© OpenStreetMap contributors',
              },
            ),
            if (_routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    color: AppColors.accentBlue,
                    strokeWidth: 5,
                  ),
                ],
              ),
            MarkerLayer(markers: _buildMarkers()),
            if (_rideStatus == "idle" && (isPickupStep || isDestinationStep))
              _buildCrosshair(),
          ],
        ),
        if (_showMapInstructions &&
            _rideStatus == "idle") 
          Positioned(
            top: 150,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isPickupStep
                        ? AppColors.mutedGreen
                        : AppColors.primaryOrange)
                    .withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app,
                    color: AppColors.white,
                    size: 18,
                  ), 
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isPickupStep
                          ? "Geser peta & tap untuk pilih lokasi jemput"
                          : "Geser peta & tap untuk pilih lokasi tujuan",
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 13, 
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.white,
                      size: 16,
                    ),
                    onPressed: () {
                      setState(() => _showMapInstructions = false);
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          bottom: _bottomPanelSize * MediaQuery.of(context).size.height + 13,
          right: 16,
          child: FloatingActionButton(
            heroTag: "currentLocationBtn",
            onPressed: () {
              if (_currentLocation != null) {
                _mapController.move(_currentLocation!, 15.0);
              } else {
                _showInstructionSnackbar(
                  "Lokasi Kamu belum ditemukan.",
                  color: AppColors.destinationRed,
                );
              }
            },
            mini: true,
            backgroundColor: AppColors.white,
            child: const Icon(Icons.my_location, color: AppColors.accentBlue),
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_currentLocation != null) {
      markers.add(
        Marker(
          width: 32.0,
          height: 32.0,
          point: _currentLocation!,
          child: Container(
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.accentBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_pickupLocation != null) {
      markers.add(
        Marker(
          point: _pickupLocation!,
          width: 36,
          height: 45,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.mutedGreen,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.white,
                    width: 2.5,
                  ), 
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 5, 
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person,
                  color: AppColors.white,
                  size: 16,
                ),
              ),
              Positioned(
                bottom: 0,
                child: CustomPaint(
                  size: const Size(10, 7),
                  painter: MarkerTailPainter(AppColors.mutedGreen),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_destinationLocation != null) {
      markers.add(
        Marker(
          point: _destinationLocation!,
          width: 36, 
          height: 45, 
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 28, 
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.destinationRed,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.white,
                    width: 2.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 5,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.flag,
                  color: AppColors.white,
                  size: 16,
                ),
              ),
              Positioned(
                bottom: 0,
                child: CustomPaint(
                  size: const Size(10, 7), 
                  painter: MarkerTailPainter(AppColors.destinationRed),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_driverLocation != null &&
        (_rideStatus == 'accepted' ||
            _rideStatus == 'in_progress' ||
            _rideStatus == 'driver_arrived')) {
      markers.add(
        Marker(
          width: 50.0, 
          height: 50.0,
          point: _driverLocation!,
          rotate: true, 
          child: Transform.rotate(
            angle:
                (_driverBearing ?? 0) *
                (math.pi / 180),
            child: Image.asset(
              'assets/icons/car_top_down.png',
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _buildCrosshair() {
    final color = _crosshairColor;
    final icon = isPickupStep ? Icons.person : Icons.flag;
    return Center(
      child: AnimatedBuilder(
        animation: _crosshairController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + _crosshairController.value * 0.15,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.white,
                      width: 2.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        offset: Offset(0, 3), 
                      ),
                    ],
                  ),
                  child:
                      _isMapMoving ||
                              _isLookingUpAddress 
                          ? const Padding(
                            padding: EdgeInsets.all(7.0), 
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.white,
                              ),
                            ),
                          )
                          : Icon(
                            icon,
                            color: AppColors.white,
                            size: 18,
                          ),
                ),
                CustomPaint(
                  size: const Size(10, 7),
                  painter: MarkerTailPainter(color),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomPanel() {
    // NEW: Added a flexible bottom padding to respect the safe area
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: _bottomPanelSize * screenHeight + bottomPadding,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: bottomPadding > 0 ? bottomPadding : 16, // Respect safe area
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.mediumGrey.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: SingleChildScrollView(child: _buildPanelContent())),
        ],
      ),
    );
  }

  Widget _buildPanelContent() {
    switch (_currentStep) {
      case RideRequestStep.selectPickup:
        return _buildPickupSelectionPanel();
      case RideRequestStep.selectDestination:
        return _buildDestinationSelectionPanel();
      case RideRequestStep.confirmRide:
        // --- NEW --- This is the major UI change
        return _buildGojekStyleConfirmPanel();
      case RideRequestStep.selectPayment:
        return _buildPaymentSelection();
      case RideRequestStep.inRide:
        return _buildRideStatus();
      default:
        return _buildPickupSelectionPanel();
    }
  }
  
  // --- NEW WIDGET ---
  // The new Gojek-style confirmation panel.
  Widget _buildGojekStyleConfirmPanel() {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isLoading = _routePoints.isEmpty;

    // Helper for currency formatting
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    );
    
    // Placeholder for a discounted price, you can hook your logic here
    final discountedPrice = _price;
    final originalPrice = (_price * 1.25).toInt(); // Example: 25% more

    // Shows placeholder UI while calculating route
    if (isLoading) {
      return _buildConfirmationPanelPlaceholder(screenWidth);
    }
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Ride Options List ---
        _buildRideOptionTile(
          iconAsset: 'assets/icons/motor.png', // <-- TODO: Add this asset
          serviceName: 'GoRide',
          eta: '$_eta mins',
          capacity: '1',
          price: currencyFormatter.format(discountedPrice),
          originalPrice: currencyFormatter.format(originalPrice),
          isSelected: true, // Assuming GoRide is the only/selected option
          screenWidth: screenWidth,
        ),
        SizedBox(height: screenWidth * 0.03),
        _buildRideOptionTile(
          iconAsset: 'assets/icons/car.png', // <-- TODO: Add this asset
          serviceName: 'GoCar',
          eta: '${(_eta * 1.5).ceil()} mins', // Example ETA
          capacity: '2-4',
          price: currencyFormatter.format((discountedPrice * 1.8).ceil()), // Example Price
          originalPrice: currencyFormatter.format((originalPrice * 1.8).ceil()),
          isSelected: false, // This is not selectable in this example
          screenWidth: screenWidth,
        ),
        
        Padding(
          padding: EdgeInsets.symmetric(vertical: screenWidth * 0.04),
          child: Divider(color: AppColors.lightGrey, thickness: 2),
        ),

        // --- Payment Method Section ---
        _buildPaymentSummary(screenWidth, currencyFormatter),

        SizedBox(height: screenWidth * 0.05),

        // --- Order Button ---
        _buildOrderButton(
          "Pesan GoRide",
          currencyFormatter.format(discountedPrice),
          () {
            // Updated to go to payment selection first, then request ride
             setState(() {
              _currentStep = RideRequestStep.selectPayment;
              _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep);
            });
          },
        ),
      ],
    );
  }
  
  // --- NEW HELPER WIDGET ---
  // Builds a single row for a ride option (like GoRide or GoCar)
  Widget _buildRideOptionTile({
    required String iconAsset,
    required String serviceName,
    required String eta,
    required String capacity,
    required String price,
    required String? originalPrice,
    required bool isSelected,
    required double screenWidth,
  }) {
    return Opacity(
      opacity: isSelected ? 1.0 : 0.5, // Dims non-selected options
      child: Container(
        padding: EdgeInsets.all(screenWidth * 0.02),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.lightOrange.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryOrange : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Image.asset(iconAsset, width: screenWidth * 0.12, errorBuilder: (c, o, s) => Icon(Icons.motorcycle, size: screenWidth * 0.12, color: AppColors.darkGrey)),
            SizedBox(width: screenWidth * 0.03),
            
            // Service Info
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: screenWidth * 0.04,
                    color: AppColors.textBlack,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      eta,
                      style: TextStyle(
                        fontSize: screenWidth * 0.032,
                        color: AppColors.darkGrey,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.person, size: screenWidth * 0.035, color: AppColors.darkGrey),
                    SizedBox(width: 4),
                    Text(
                      capacity,
                       style: TextStyle(
                        fontSize: screenWidth * 0.032,
                        color: AppColors.darkGrey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Spacer(),

            // Price Info
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: screenWidth * 0.04,
                    color: AppColors.textBlack,
                  ),
                ),
                if (originalPrice != null) ...[
                  SizedBox(height: 2),
                  Text(
                    originalPrice,
                    style: TextStyle(
                      fontSize: screenWidth * 0.032,
                      color: AppColors.mediumGrey,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW HELPER WIDGET ---
  // Builds the payment summary row
  Widget _buildPaymentSummary(double screenWidth, NumberFormat currencyFormatter) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentStep = RideRequestStep.selectPayment;
          _bottomPanelSize = _getDefaultBottomPanelSizeForStep(_currentStep);
        });
      },
      child: Container(
        color: Colors.transparent, // Makes the whole area tappable
        child: Row(
          children: [
            Icon(
              _selectedPaymentMethod == 'xpay' ? Icons.account_balance_wallet : Icons.money,
              color: AppColors.primaryOrange,
              size: screenWidth * 0.06,
            ),
            SizedBox(width: screenWidth * 0.03),
            Text(
              _selectedPaymentMethod == 'xpay' ? 'XPay' : 'Tunai',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: screenWidth * 0.038,
              ),
            ),
            SizedBox(width: screenWidth * 0.02),
            Icon(Icons.expand_more, color: AppColors.darkGrey, size: screenWidth * 0.04),
            Spacer(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lightOrange.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6)
              ),
              child: Text(
                'Promo applied!',
                style: TextStyle(
                  color: AppColors.darkerOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: screenWidth * 0.03,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW HELPER WIDGET ---
  // Builds the final order button
  Widget _buildOrderButton(String title, String price, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.mutedGreen,
        minimumSize: Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 4,
        shadowColor: AppColors.mutedGreen.withOpacity(0.4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- NEW HELPER WIDGET ---
  // Placeholder shown while loading/calculating the route.
  Widget _buildConfirmationPanelPlaceholder(double screenWidth) {
    // Helper to create a single placeholder box
    Widget placeholderBox(double width, double height, {double radius = 8}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black, // Shimmer base color
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }
    
    // Using a simple Fade animation instead of a new dependency for lightness
    return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.3, end: 1.0),
        duration: const Duration(milliseconds: 800),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: child,
          );
        },
        child: Column(
            children: List.generate(2, (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  placeholderBox(screenWidth * 0.12, screenWidth * 0.12, radius: screenWidth * 0.06),
                  SizedBox(width: screenWidth * 0.03),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      placeholderBox(screenWidth * 0.2, 16),
                      SizedBox(height: 8),
                      placeholderBox(screenWidth * 0.3, 12),
                    ],
                  ),
                  Spacer(),
                  Column(
                     crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      placeholderBox(screenWidth * 0.2, 16),
                      SizedBox(height: 8),
                      placeholderBox(screenWidth * 0.15, 12),
                    ],
                  )
                ],
              ),
            )),
          ),
    );
  }


  Widget _buildPickupSelectionPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pickupLocation == null)
          Text(
            "Pilih lokasi jemputmu di peta atau cari alamat di atas.",
            style: TextStyle(fontSize: 16, color: AppColors.darkGrey),
            textAlign: TextAlign.center,
          )
        else
          Column(
            children: [
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _currentStep = RideRequestStep.selectDestination;
                      _crosshairColor = AppColors.destinationRed;
                      _showMapInstructions = true;
                      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(
                        _currentStep,
                      );
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    "Lanjut Pilih Tujuan",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildDestinationSelectionPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pickupLocation == null)
          _buildPickupSelectionPanel()
        else if (_destinationLocation == null)
          Text(
            "Pilih lokasi tujuanmu di peta atau cari alamat di atas.",
            style: TextStyle(fontSize: 16, color: AppColors.darkGrey),
            textAlign: TextAlign.center,
          )
        else
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_pickupLocation != null &&
                        _destinationLocation != null) {
                      _calculateRoute(); 
                    } else {
                      _showInstructionSnackbar(
                        "Mohon pilih lokasi jemput dan tujuan.",
                        color: AppColors.destinationRed,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    "Konfirmasi Destinasi & Hitung Rute", 
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _resetToInitialState,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryOrange,
              side: const BorderSide(color: AppColors.primaryOrange),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "Batal",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationDisplayRow({
    required String label,
    required String address,
    required IconData icon,
    required Color color,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.mediumGrey.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 6,
                    color: AppColors.darkGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppColors.textBlack,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: onClear,
            color: AppColors.mediumGrey,
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionList({
    required List<Map<String, dynamic>> suggestions,
    required bool isPickup,
    required bool showDropdown,
  }) {
    if (!showDropdown || suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12, 
            offset: Offset(0, 3), 
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(
          vertical: 6,
        ),
        itemCount: math.min(suggestions.length, 6),
        separatorBuilder:
            (context, index) =>
                const Divider(height: 1, indent: 48),
        itemBuilder: (context, index) {
          final location = suggestions[index];
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 2,
            ),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: AppColors.primaryOrange,
              ),
            ),
            title: Text(
              location['name'] ?? '',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle:
                location['fullName'] != null
                    ? Text(
                      location['fullName'].split(', ').skip(1).join(', '),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                    : (location['address'] != null
                        ? Text(
                          location['address'],
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                        : null),
            onTap: () {
              _selectLocationFromSuggestion(location, isPickup);
              FocusScope.of(context).unfocus();
            },
          );
        },
      ),
    );
  }

  Widget _buildPaymentSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Pilih Metode Pembayaran",
          style: TextStyle(
            fontSize: 18, 
            fontWeight: FontWeight.bold,
            color: AppColors.textBlack,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildPaymentOption(
                icon: Icons.money,
                title: "Tunai",
                subtitle: "Bayar langsung ke pengemudi",
                value: 'cash',
              ),
              const Divider(height: 18),
              _buildPaymentOption(
                icon: Icons.account_balance_wallet,
                title: "XPay",
                subtitle:
                    _isLoadingBalance
                        ? "Memuat saldo..."
                        : "Saldo: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_userBalance)}",
                value: 'xpay',
                isEnabled: _userBalance >= _price,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18), 
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _requestRide,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              padding: const EdgeInsets.symmetric(
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
            child: Text(
              "Pesan Sekarang • ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_price)}",
              style: const TextStyle(
                fontSize: 15, 
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _currentStep = RideRequestStep.confirmRide;
                _bottomPanelSize = _getDefaultBottomPanelSizeForStep(
                  _currentStep,
                );
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryOrange,
              side: const BorderSide(color: AppColors.primaryOrange),
              padding: const EdgeInsets.symmetric(
                vertical: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "Kembali",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ), 
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    bool isEnabled = true,
  }) {
    final bool isSelected = _selectedPaymentMethod == value;
    final Color textColor =
        isEnabled ? AppColors.textBlack : AppColors.mediumGrey;
    final Color subtitleColor =
        isEnabled ? AppColors.darkGrey : AppColors.mediumGrey;

    return GestureDetector(
      onTap:
          isEnabled
              ? () {
                setState(() {
                  _selectedPaymentMethod = value;
                });
              }
              : null,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.lightOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:
                isSelected
                    ? Border.all(color: AppColors.primaryOrange, width: 1.5)
                    : null,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ), 
          child: Row(
            children: [
              Icon(
                icon,
                color: AppColors.primaryOrange,
                size: 24,
              ),
              const SizedBox(width: 14), 
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.primaryOrange,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRideStatus() {
    String statusMessage;
    Widget statusContent;

    switch (_rideStatus) {
      case "searching":
        statusMessage = "Mencari pengemudi terdekat...";
        statusContent = Column(
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.primaryOrange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              statusMessage,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.darkGrey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cancelRide,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.destinationRed,
                  side: const BorderSide(color: AppColors.destinationRed),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "Batalkan Pencarian",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
        break;
      case "accepted":
      case "driver_arrived":
      case "in_progress":
        statusMessage =
            _rideStatus == "accepted"
                ? "Pengemudi ditemukan!"
                : (_rideStatus == "driver_arrived"
                    ? "Pengemudi telah tiba!"
                    : "Perjalanan sedang berlangsung");
        statusContent = Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              statusMessage,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textBlack,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_driverName != null)
              _buildDriverInfoCard(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cancelRide,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.destinationRed,
                  side: const BorderSide(color: AppColors.destinationRed),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "Batalkan Perjalanan",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
        break;
      case "completed":
        statusMessage = "Perjalanan selesai!";
        statusContent = Column(
          children: [
            const Icon(
              Icons.check_circle,
              color: AppColors.mutedGreen,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              statusMessage,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textBlack,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _resetToInitialState,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "Selesai",
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
        break;
      case "cancelled":
        statusMessage = "Perjalanan dibatalkan.";
        statusContent = Column(
          children: [
            const Icon(Icons.cancel, color: AppColors.destinationRed, size: 60),
            const SizedBox(height: 16),
            Text(
              statusMessage,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textBlack,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _resetToInitialState,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "Kembali ke Awal",
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
        break;
      default:
        statusMessage = "Status tidak dikenal.";
        statusContent = Text(statusMessage);
        break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: statusContent),
    );
  }

  Widget _buildDriverInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primaryOrange,
                child: Icon(Icons.person, color: AppColors.white, size: 35),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _driverName ?? "Pengemudi",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textBlack,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_driverVehicle ?? "Kendaraan"} - ${_driverPlateNumber ?? "Nomor Plat"}',
                      style: TextStyle(fontSize: 14, color: AppColors.darkGrey),
                    ),
                    const SizedBox(height: 4),
      
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDriverActionIcon(
                Icons.chat,
                'Chat',
                AppColors.accentBlue,
                () {
                    ChatService.show(
                      context,
                      rideId: _rideId!,
                      otherUserName: _driverName!,
                      otherUserId: _driverId!,
                      isDriver: false,
                    );
                  
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverActionIcon(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 13, color: AppColors.darkGrey)),
      ],
    );
  }

  Widget _buildAddressInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: AppColors.mediumGrey),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textBlack,
            ),
            onChanged: onChanged,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (_pickupLocation != null && _destinationLocation != null) {
                _calculateRoute();
              }
              FocusScope.of(context).unfocus();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final bool showInputFields =
        _isSearchingAddress ||
        _pickupLocation == null ||
        _destinationLocation == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.circle, color: AppColors.mutedGreen, size: 10),
              const SizedBox(width: 12),
              Expanded(
                child:
                    showInputFields && _currentStep != RideRequestStep.inRide
                        ? _buildAddressInputField(
                          controller: _pickupController,
                          focusNode: _pickupFocusNode,
                          hintText: "Lokasi Jemput",
                          onChanged: (value) => _onSearchChanged(value, true),
                          onClear: () {
                            _pickupController.clear();
                            setState(() {
                              _pickupLocation = null;
                              _selectedPickupAddress = null;
                              _pickupSuggestions.clear();
                              _showPickupDropdown = false;
                              _isSearchingAddress = false;
                              _currentStep = RideRequestStep.selectPickup;
                              _bottomPanelSize =
                                  _getDefaultBottomPanelSizeForStep(
                                    _currentStep,
                                  );
                            });
                            FocusScope.of(context).unfocus();
                          },
                        )
                        : Text(
                          _selectedPickupAddress ?? "Pilih Lokasi Jemput",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textBlack,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
              ),
              if (_pickupLocation != null &&
                  _rideStatus == "idle" &&
                  !showInputFields)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _pickupController.clear();
                    setState(() {
                      _pickupLocation = null;
                      _selectedPickupAddress = null;
                      _pickupSuggestions.clear();
                      _showPickupDropdown = false;
                      _isSearchingAddress = false;
                      _currentStep = RideRequestStep.selectPickup;
                      _bottomPanelSize = _getDefaultBottomPanelSizeForStep(
                        _currentStep,
                      );
                    });
                    FocusScope.of(context).unfocus();
                  },
                  color: AppColors.mediumGrey,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: SizedBox(
              height: 20,
              child: CustomPaint(painter: DottedLinePainter()),
            ),
          ),
          Row(
            children: [
              Icon(Icons.square, color: AppColors.destinationRed, size: 10),
              const SizedBox(width: 12),
              Expanded(
                child:
                    showInputFields && _currentStep != RideRequestStep.inRide
                        ? _buildAddressInputField(
                          controller: _destinationController,
                          focusNode: _destinationFocusNode,
                          hintText: "Lokasi Tujuan",
                          onChanged: (value) => _onSearchChanged(value, false),
                          onClear: () {
                            _destinationController.clear();
                            setState(() {
                              _destinationLocation = null;
                              _selectedDestinationAddress = null;
                              _destinationSuggestions.clear();
                              _showDestinationDropdown = false;
                              _isSearchingAddress = false;
                              if (_pickupLocation != null) {
                                _currentStep =
                                    RideRequestStep.selectDestination;
                                _bottomPanelSize =
                                    _getDefaultBottomPanelSizeForStep(
                                      _currentStep,
                                    );
                              }
                            });
                            FocusScope.of(context).unfocus();
                          },
                        )
                        : Text(
                          _selectedDestinationAddress ?? "Pilih Lokasi Tujuan",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textBlack,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
              ),
              if (_destinationLocation != null &&
                  _rideStatus == "idle" &&
                  !showInputFields)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18), 
                  onPressed: () {
                    _destinationController.clear();
                    setState(() {
                      _destinationLocation = null;
                      _selectedDestinationAddress = null;
                      _destinationSuggestions.clear();
                      _showDestinationDropdown = false;
                      _isSearchingAddress = false;
                      if (_pickupLocation != null) {
                        _currentStep = RideRequestStep.selectDestination;
                        _bottomPanelSize = _getDefaultBottomPanelSizeForStep(
                          _currentStep,
                        );
                      }
                    });
                    FocusScope.of(context).unfocus();
                  },
                  color: AppColors.mediumGrey,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DottedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppColors.mediumGrey
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    const double dashWidth = 3;
    const double dashSpace = 3;
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashWidth),
        paint,
      );
      startY += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}