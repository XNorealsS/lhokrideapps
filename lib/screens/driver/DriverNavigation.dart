import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:lhokride/utils/route_utils.dart';
import 'package:lhokride/services/firebase_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'component/chat_dialog.dart';
import '../../utils/location_utils.dart'; // Ensure this is still relevant or remove if not used
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart'; // Keep if you plan to cluster markers, otherwise can remove
import 'package:flutter_map/flutter_map.dart' show TileLayer;
import 'package:url_launcher/url_launcher.dart';

// Dummy DottedLine widget - replace with an actual package like `dotted_line` if desired for better control.
class DottedLine extends StatelessWidget {
  final Color dashColor;
  final double dashLength;
  final double dashGapLength;
  final double lineThickness;
  final Axis direction;
  final double lineLength;

  const DottedLine({
    Key? key,
    this.dashColor = Colors.black,
    this.dashLength = 4.0,
    this.dashGapLength = 4.0,
    this.lineThickness = 1.0,
    this.direction = Axis.horizontal,
    this.lineLength = 50.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double len =
            direction == Axis.horizontal
                ? constraints.constrainWidth()
                : lineLength;
        final int dashCount = (len / (dashLength + dashGapLength)).floor();
        return Flex(
          direction: direction,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: direction == Axis.horizontal ? dashLength : lineThickness,
              height: direction == Axis.vertical ? dashLength : lineThickness,
              child: DecoratedBox(decoration: BoxDecoration(color: dashColor)),
            );
          }),
        );
      },
    );
  }
}


class RideProgressScreen extends StatefulWidget {
  final String rideId;
  final String passengerName;
  final String passengerId;
  final dynamic pickup;
  final dynamic destination;

  const RideProgressScreen({
    Key? key,
    required this.rideId,
    required this.passengerName,
    required this.passengerId,
    required this.pickup,
    required this.destination,
  }) : super(key: key);

  @override
  _RideProgressScreenState createState() => _RideProgressScreenState();
}

class _RideProgressScreenState extends State<RideProgressScreen>
    with SingleTickerProviderStateMixin {
  // Constants
  static const double _defaultZoom = 15.0;
  static const double _routeLineWidth = 4.0;
  static const Duration _locationUpdateInterval = Duration(seconds: 5);

  static const Color _primaryColor = Color(0xFFFFA726); // Gojek-like orange
  static const Color _accentColor = Color(0xFFFFCC80);
  static const Color _lightGreyColor = Color(0xFFF5F5F5);
  static const Color _textColor = Color(0xFF333333); // Dark grey for text
  static const Color _successColor = Colors.green;
  static const Color _infoColor = Colors.blue;
  static const Color _warningColor = Colors.amber;
  static const Color _errorColor = Colors.red;


  // Services
  final _storage = const FlutterSecureStorage();
  final MapController _mapController = MapController();

  // Ride data
  late LatLng _pickup;
  late LatLng _destination;
  LatLng? _currentDriverLocation;
  String _status = "accepted";
  String _driverId = "";
  String _driverName = "Driver";
  String? _passengerPhoneNumber;

  // Route data
  double _distance = 0;
  int _eta = 0;
  List<LatLng> _routePoints = [];
  bool _isCalculatingRoute = false; // New: for route calculation loading


  // UI state
  bool _isUpdatingStatus = false;
  bool _isCompleting = false;
  bool _isMapReady = false;
  bool _isInitialized = false;

  // DraggableScrollableSheet controller
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _currentSheetExtent = 0.0;
  bool _isSheetFullyExpanded = false;

  // Listeners & Timers
  StreamSubscription<DatabaseEvent>? _rideUpdateListener;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _periodicLocationUpdateTimer;

  // Animation for FAB visibility based on sheet state
  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;

  @override
  void initState() {
    super.initState();
    _initializePickupDestination();
    _initializeScreen();

    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeOut,
    );

    _sheetController.addListener(() {
      if (mounted) {
        setState(() {
          _currentSheetExtent = _sheetController.size;
          // Define what "fully expanded" means for your design
          _isSheetFullyExpanded = _currentSheetExtent >= 0.7;
        });

        // Hide FABs when sheet is expanding, show when collapsing/collapsed
        if (_currentSheetExtent > 0.1 &&
            _fabAnimationController.status != AnimationStatus.reverse) {
          _fabAnimationController.reverse();
        } else if (_currentSheetExtent <= 0.1 &&
            _fabAnimationController.status != AnimationStatus.forward) {
          _fabAnimationController.forward();
        }
      }
    });

    _fabAnimationController.forward(); // Initially show FABs
  }

  @override
  void dispose() {
    _rideUpdateListener?.cancel();
    _positionStreamSubscription?.cancel();
    _periodicLocationUpdateTimer?.cancel();
    _sheetController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  void _initializePickupDestination() {
    try {
      _pickup = _parseLatLng(widget.pickup);
      _destination = _parseLatLng(widget.destination);

      if (_pickup.latitude == 0.0 && _pickup.longitude == 0.0) {
        debugPrint('Warning: Invalid pickup coordinates');
      }
      if (_destination.latitude == 0.0 && _destination.longitude == 0.0) {
        debugPrint('Warning: Invalid destination coordinates');
      }
    } catch (e) {
      debugPrint('Error initializing coordinates: $e');
      _pickup = const LatLng(0.0, 0.0);
      _destination = const LatLng(0.0, 0.0);
    }
  }

  Future<void> _initializeScreen() async {
    try {
      await _loadDriverData();
      await _requestLocationPermission();
      _startListeningToDeviceLocation();
      _startPeriodicFirebaseLocationUpdates();
      _setupRideListener();
      await _fetchRideDetails();
      await _calculateRoute();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fitMapBounds();
          setState(() {
            _isMapReady = true;
            _isInitialized = true;
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing screen: $e');
      if (mounted) {
        _showErrorMessage('Gagal menginisialisasi layar: $e');
      }
    }
  }

  Future<void> _loadDriverData() async {
    try {
      final driverId = await _storage.read(key: 'user_id');
      final driverName = await _storage.read(key: 'name');

      if (mounted) {
        setState(() {
          _driverId = driverId ?? "";
          _driverName = driverName ?? "Driver";
        });
      }
    } catch (e) {
      debugPrint('Error loading driver data: $e');
    }
  }

  Future<void> _fetchRideDetails() async {
    try {
      final rideData = await FirebaseService.getRideDetails(widget.rideId);
      if (rideData != null && mounted) {
        final passengerData = rideData['passenger'];
        String? phoneNumber;
        String? currentStatus;

        if (passengerData is Map) {
          final phone = passengerData['phone'];
          phoneNumber = phone?.toString();
        }

        if (rideData.containsKey('status')) {
          final status = rideData['status'];
          currentStatus = status?.toString();
        }

        setState(() {
          _passengerPhoneNumber = phoneNumber;
          if (currentStatus != null && currentStatus.isNotEmpty) {
            _status = currentStatus;
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching ride details: $e");
      if (mounted) {
        _showErrorMessage("Gagal mengambil detail perjalanan: $e");
      }
    }
  }

  LatLng _parseLatLng(dynamic location) {
    try {
      if (location == null) {
        debugPrint('Warning: Location is null');
        return const LatLng(0.0, 0.0);
      }

      if (location is Map) {
        final lat = location['latitude'] ?? location['lat'];
        final lon = location['longitude'] ?? location['lon'];

        if (lat == null || lon == null) {
          debugPrint('Warning: Latitude or longitude is null');
          return const LatLng(0.0, 0.0);
        }

        final latitude = _parseDouble(lat);
        final longitude = _parseDouble(lon);

        return LatLng(latitude, longitude);
      }

      debugPrint('Warning: Location is not a Map: ${location.runtimeType}');
      return const LatLng(0.0, 0.0);
    } catch (e) {
      debugPrint('Error parsing LatLng: $e');
      return const LatLng(0.0, 0.0);
    }
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Future<void> _requestLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showErrorMessage('Layanan lokasi dinonaktifkan. Mohon aktifkan.');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            _showErrorMessage('Izin lokasi ditolak');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showErrorMessage(
            'Izin lokasi ditolak secara permanen. Mohon ubah di pengaturan aplikasi.',
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      if (mounted) {
        _showErrorMessage('Gagal meminta izin lokasi: $e');
      }
    }
  }

  void _startListeningToDeviceLocation() {
    _positionStreamSubscription?.cancel();

    try {
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (Position position) {
          if (mounted) {
            setState(() {
              _currentDriverLocation = LatLng(
                position.latitude,
                position.longitude,
              );
            });
            // Only recalculate route if not already doing so to avoid spamming API
            if (!_isCalculatingRoute) {
              _calculateRoute();
            }
            // Center map on driver when location updates only if the sheet is not expanded
            if (_currentSheetExtent < 0.2) {
              _centerMapOnDriver();
            }
          }
        },
        onError: (error) {
          debugPrint('Error getting device location: $error');
          if (mounted) {
            _showErrorMessage('Gagal mendapatkan lokasi: $error');
          }
        },
      );
    } catch (e) {
      debugPrint('Error starting location stream: $e');
      if (mounted) {
        _showErrorMessage('Gagal memulai pelacakan lokasi: $e');
      }
    }
  }

  void _startPeriodicFirebaseLocationUpdates() {
    _periodicLocationUpdateTimer?.cancel();

    _periodicLocationUpdateTimer = Timer.periodic(_locationUpdateInterval, (
      timer,
    ) async {
      try {
        if (!mounted ||
            _driverId.isEmpty ||
            _status == 'completed' ||
            _status == 'cancelled') {
          timer.cancel();
          return;
        }

        if (_currentDriverLocation != null) {
          await FirebaseService.updateDriverLocation(
            _driverId,
            _currentDriverLocation!.latitude,
            _currentDriverLocation!.longitude,
          );
        }
      } catch (e) {
        debugPrint("Error sending location to Firebase: $e");
      }
    });
  }

  Future<void> _calculateRoute() async {
    if (_isCalculatingRoute) return;

    setState(() {
      _isCalculatingRoute = true;
      _routePoints = []; // Clear existing route points immediately
      _distance = 0;
      _eta = 0;
    });

    try {
      if (_currentDriverLocation == null) {
        // If driver location is not available, try to get it once
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        if (mounted) {
          setState(() {
            _currentDriverLocation = LatLng(position.latitude, position.longitude);
          });
        }
        if (_currentDriverLocation == null) return; // Still null, exit
      }

      LatLng startPoint;
      LatLng endPoint;

      if (_status == "accepted") {
        startPoint = _currentDriverLocation!;
        endPoint = _pickup;
      } else if (_status == "in_progress") {
        startPoint = _currentDriverLocation!;
        endPoint = _destination;
      } else {
        if (mounted) {
          setState(() {
            _isCalculatingRoute = false; // Reset loading state
          });
        }
        return;
      }

      final result = await RouteUtils.calculateRoute(startPoint, endPoint);

      if (mounted) {
        setState(() {
          _distance = _parseDouble(result['distance']) ?? 0.0;
          _eta = (result['eta'] as int?) ?? 0;
          _routePoints = List<LatLng>.from(result['routePoints'] ?? []);
        });

        if (_isMapReady) {
          _fitMapBounds();
        }
      }
    } catch (e) {
      debugPrint('Error calculating route: $e');
      if (mounted) {
        setState(() {
          _routePoints = [];
          _distance = 0;
          _eta = 0;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCalculatingRoute = false; // Reset loading state
        });
      }
    }
  }


  void _centerMapOnDriver() {
    if (_currentDriverLocation != null && _isMapReady) {
      try {
        _mapController.move(_currentDriverLocation!, _defaultZoom);
      } catch (e) {
        debugPrint('Error centering map on driver: $e');
      }
    }
  }

  void _fitMapBounds() {
    if (!_isMapReady) return;

    try {
      List<LatLng> pointsToFit = [];
      if (_currentDriverLocation != null) {
        pointsToFit.add(_currentDriverLocation!);
      }
      if (_status == 'accepted' &&
          _pickup.latitude != 0.0 &&
          _pickup.longitude != 0.0) {
        pointsToFit.add(_pickup);
      } else if (_status == 'in_progress' &&
          _destination.latitude != 0.0 &&
          _destination.longitude != 0.0) {
        pointsToFit.add(_destination);
      }

      if (_routePoints.isNotEmpty) {
        pointsToFit.addAll(_routePoints);
      }

      if (pointsToFit.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(pointsToFit);
        if (mounted && bounds.northEast != bounds.southWest) {
          _mapController.fitBounds(
            bounds,
            options: const FitBoundsOptions(
              padding: EdgeInsets.all(80),
              maxZoom: _defaultZoom,
            ),
          );
        }
      } else if (_currentDriverLocation != null) {
        _centerMapOnDriver();
      }
    } catch (e) {
      debugPrint('Error fitting map bounds: $e');
    }
  }

  void _setupRideListener() {
    _rideUpdateListener?.cancel();

    try {
      _rideUpdateListener = FirebaseService.listenToRideStatus(widget.rideId, (
        rideData,
      ) {
        if (!mounted || rideData == null) return;

        try {
          final newStatusData = rideData['status'];
          final newStatus = newStatusData?.toString();

          if (newStatus != null &&
              newStatus.isNotEmpty &&
              newStatus != _status) {
            setState(() {
              _status = newStatus;
            });
            _calculateRoute();

            if (newStatus == 'completed' || newStatus == 'cancelled') {
              _handleRideEnd();
            }
          }
        } catch (e) {
          debugPrint('Error processing ride update: $e');
        }
      });
    } catch (e) {
      debugPrint('Error setting up ride listener: $e');
      if (mounted) {
        _showErrorMessage('Gagal mengatur pemantauan status perjalanan: $e');
      }
    }
  }

  Future<void> _updateRideStatus(String newStatus) async {
    if (_isUpdatingStatus) return;

    setState(() => _isUpdatingStatus = true);

    try {
      // Update Firebase first
      await FirebaseService.updateRideStatus(widget.rideId, {
        'status': newStatus,
        'updatedAt': ServerValue.timestamp,
      });

      // Update backend
      final token = await _storage.read(key: 'token');
      if (token == null || token.isEmpty) {
        throw Exception('Token tidak ditemukan');
      }

      final requestBody = {'status': newStatus, 'driverId': _driverId};

      final response = await http
          .post(
            Uri.parse(
              'http://api.lhokride.com/api/rides/${widget.rideId}/status',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() => _status = newStatus);
          _calculateRoute();

          if (newStatus == "in_progress") {
            _showSuccessMessage("Perjalanan dimulai! Menuju tujuan.");
          } else if (newStatus == "accepted") {
            _showSuccessMessage("Menuju lokasi penjemputan.");
          }
        }
      } else {
        throw Exception(
          'Failed to update status: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint("Error updating ride status: $e");
      if (mounted) {
        _showErrorMessage("Gagal mengupdate status: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _completeRide() async {
    if (_isCompleting) return;

    final confirmed = await _showConfirmationDialog(
      "Selesaikan Perjalanan",
      "Apakah Kamu yakin ingin menyelesaikan perjalanan ini?",
    );
    if (!confirmed) return;

    setState(() => _isCompleting = true);

    try {
      final token = await _storage.read(key: 'token');
      if (token == null || token.isEmpty) {
        throw Exception('Token tidak ditemukan');
      }

      final response = await http
          .post(
            Uri.parse(
              'http://api.lhokride.com/api/rides/${widget.rideId}/complete',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'driverId': _driverId,
              'completedAt': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await FirebaseService.updateRideStatus(widget.rideId, {
          'status': 'completed',
          'completedAt': ServerValue.timestamp,
        });

        if (mounted) {
          _showSuccessMessage("Perjalanan berhasil diselesaikan!");
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context, true);
          });
        }
      } else {
        throw Exception(
          'Failed to complete ride: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint("Error completing ride: $e");
      if (mounted) {
        _showErrorMessage("Gagal menyelesaikan perjalanan: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  void _handleRideEnd() {
    _positionStreamSubscription?.cancel();
    _periodicLocationUpdateTimer?.cancel();

    if (mounted) {
      if (_status == 'completed') {
        _showSuccessMessage("Perjalanan telah selesai");
      } else if (_status == 'cancelled') {
        _showErrorMessage("Perjalanan dibatalkan oleh penumpang.");
      }

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message) async {
    if (!mounted) return false;

    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Batal"),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Ya"),
                  ),
                ],
              ),
        ) ??
        false;
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _successColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _errorColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openChatDialog(BuildContext context) {
    try {
      if (widget.passengerId.isEmpty) {
        _showErrorMessage("ID penumpang tidak tersedia.");
        return;
      }
      ChatService.show(
        context,
        rideId: widget.rideId,
        otherUserName: widget.passengerName,
        otherUserId: widget.passengerId,
        isDriver: true,
      );
    } catch (e) {
      debugPrint('Error opening chat dialog: $e');
      _showErrorMessage('Gagal membuka chat: $e');
    }
  }

  void _callPassenger() async {
    try {
      if (_passengerPhoneNumber == null || _passengerPhoneNumber!.isEmpty) {
        _showErrorMessage('Nomor telepon penumpang tidak tersedia.');
        return;
      }
      final url = 'tel:$_passengerPhoneNumber';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        _showErrorMessage('Tidak dapat melakukan panggilan.');
      }
    } catch (e) {
      debugPrint('Error calling passenger: $e');
      _showErrorMessage('Gagal melakukan panggilan: $e');
    }
  }

  List<Marker> _buildMarkers() {
    final List<Marker> markers = [];
    // Driver marker (motorcycle)
    if (_currentDriverLocation != null) {
      markers.add(
        Marker(
          width: 70.0,
          height: 70.0,
          point: _currentDriverLocation!,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.motorcycle,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              // Small triangle pointer
              Container(
                width: 0,
                height: 0,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Colors.transparent, width: 5),
                    right: BorderSide(color: Colors.transparent, width: 5),
                    top: BorderSide(color: _primaryColor, width: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Pickup marker
    markers.add(
      Marker(
        width: 70.0,
        height: 70.0,
        point: _pickup,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_pin_circle,
                color: Colors.white,
                size: 28,
              ),
            ),
            Container(
              width: 0,
              height: 0,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.transparent, width: 5),
                  right: BorderSide(color: Colors.transparent, width: 5),
                  top: BorderSide(color: Colors.green.shade600, width: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Destination marker
    markers.add(
      Marker(
        width: 70.0,
        height: 70.0,
        point: _destination,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.flag, color: Colors.white, size: 28),
            ),
            Container(
              width: 0,
              height: 0,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.transparent, width: 5),
                  right: BorderSide(color: Colors.transparent, width: 5),
                  top: BorderSide(color: Colors.red.shade600, width: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return markers;
  }

  Widget _buildMap() {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _primaryColor),
            SizedBox(height: 16),
            Text("Memuat Peta...", style: TextStyle(color: _textColor)),
          ],
        ),
      );
    }
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentDriverLocation ?? _pickup,
        initialZoom: _defaultZoom,
        onMapReady: () {
          if (mounted) {
            setState(() => _isMapReady = true);
            _fitMapBounds();
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.becak_lhokride.app',
          subdomains: const ['a', 'b', 'c'],
        ),
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: _routeLineWidth,
                color: _primaryColor.withOpacity(0.8),
              ),
            ],
          ),
        MarkerLayer(markers: _buildMarkers()),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    String statusText;
    Color statusColor;
    IconData statusIcon;
    switch (_status) {
      case 'accepted':
        statusText = "Menuju Penjemputan";
        statusColor = _primaryColor;
        statusIcon = Icons.navigation;
        break;
      case 'in_progress':
        statusText = "Dalam Perjalanan";
        statusColor = _infoColor;
        statusIcon = Icons.directions_car;
        break;
      case 'completed':
        statusText = "Selesai";
        statusColor = _successColor;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusText = "Dibatalkan";
        statusColor = _errorColor;
        statusIcon = Icons.cancel;
        break;
      default:
        statusText = "Status Tidak Diketahui";
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
        break;
    }
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenHeight * 0.01,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(screenWidth * 0.06),
        border: Border.all(color: statusColor.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: statusColor, size: screenWidth * 0.045),
          SizedBox(width: screenWidth * 0.02),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: screenWidth * 0.035,
            ),
          ),
        ],
      ),
    );
  }

  String _getAddressFromDynamic(dynamic location) {
    if (location is Map && location.containsKey('address')) {
      return location['address'] as String? ?? 'Alamat tidak diketahui';
    }
    return 'Alamat tidak diketahui';
  }

  Widget _buildPassengerInfoContent() {
    String pickupAddress = _getAddressFromDynamic(widget.pickup);
    String destinationAddress = _getAddressFromDynamic(widget.destination);
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Passenger header with improved design
        Container(
          padding: EdgeInsets.all(screenWidth * 0.04),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor.withOpacity(0.1), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryColor.withOpacity(0.3), width: 1),
          ),
          child: Row(
            children: [
              // Passenger Avatar
              Container(
                width: screenWidth * 0.13,
                height: screenWidth * 0.13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [_primaryColor, _primaryColor.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.person,
                  color: Colors.white,
                  size: screenWidth * 0.07,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.passengerName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.045,
                        color: _textColor,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.005),
                    Text(
                      "Penumpang",
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // Call and Chat buttons
              Row(
                children: [
                  FloatingActionButton.small(
                    heroTag: "callPassenger",
                    onPressed: _callPassenger,
                    backgroundColor: _successColor,
                    child: const Icon(Icons.call, color: Colors.white),
                  ),
                  SizedBox(width: screenWidth * 0.02),
                  FloatingActionButton.small(
                    heroTag: "chatPassenger",
                    onPressed: () => _openChatDialog(context),
                    backgroundColor: _infoColor,
                    child: const Icon(Icons.chat, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: screenHeight * 0.02),
        // Ride details
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.01),
          child: Padding(
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Detail Perjalanan",
                  style: TextStyle(
                    fontSize: screenWidth * 0.045,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
                Divider(height: screenHeight * 0.03, color: Colors.grey[300]),
                _buildInfoRow(
                  context,
                  Icons.location_on,
                  "Penjemputan",
                  pickupAddress,
                  Colors.green,
                ),
                Padding(
                  padding: EdgeInsets.only(left: screenWidth * 0.04),
                  child: DottedLine(
                    direction: Axis.vertical,
                    lineLength: screenHeight * 0.03,
                    lineThickness: 2.0,
                    dashLength: 4.0,
                    dashGapLength: 4.0,
                    dashColor: Colors.grey,
                  ),
                ),
                _buildInfoRow(
                  context,
                  Icons.flag,
                  "Tujuan",
                  destinationAddress,
                  Colors.red,
                ),
                SizedBox(height: screenHeight * 0.02),
                // Route metrics with loading indicators
                _isCalculatingRoute
                    ? _buildMetricsPlaceholder(screenWidth, screenHeight)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMetricChip(
                            context,
                            Icons.map,
                            "${_distance.toStringAsFixed(1)} km",
                            "Jarak",
                          ),
                          _buildMetricChip(
                            context,
                            Icons.access_time,
                            "$_eta mnt",
                            "ETA",
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
        SizedBox(height: screenHeight * 0.02),
        // Action buttons based on status
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildMetricsPlaceholder(double screenWidth, double screenHeight) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildShimmerMetricChip(screenWidth, screenHeight),
        _buildShimmerMetricChip(screenWidth, screenHeight),
      ],
    );
  }

  Widget _buildShimmerMetricChip(double screenWidth, double screenHeight) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.01),
        padding: EdgeInsets.symmetric(
          vertical: screenHeight * 0.01,
          horizontal: screenWidth * 0.01,
        ),
        decoration: BoxDecoration(
          color: _lightGreyColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Container(
              width: screenWidth * 0.06,
              height: screenWidth * 0.06,
              color: Colors.grey.shade300,
            ),
            SizedBox(height: screenHeight * 0.005),
            Container(
              width: screenWidth * 0.15,
              height: screenHeight * 0.02,
              color: Colors.grey.shade300,
            ),
            SizedBox(height: screenHeight * 0.005),
            Container(
              width: screenWidth * 0.1,
              height: screenHeight * 0.015,
              color: Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: screenWidth * 0.055),
        SizedBox(width: screenWidth * 0.03),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: screenWidth * 0.038,
                  color: _textColor,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: screenWidth * 0.035,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildMetricChip(
    BuildContext context,
    IconData icon,
    String value,
    String label,

  ) {
       double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.01),
        padding: EdgeInsets.symmetric(
          vertical: screenHeight * 0.01,
          horizontal: screenWidth * 0.01,
        ),
        decoration: BoxDecoration(
          color: _lightGreyColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(icon, color: _primaryColor, size: screenWidth * 0.06),
            SizedBox(height: screenHeight * 0.005),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: screenWidth * 0.04,
                color: _textColor,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: screenWidth * 0.03,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    return Column(
      children: [
        if (_status == "accepted")
          ElevatedButton.icon(
            onPressed:
                _isUpdatingStatus
                    ? null
                    : () => _updateRideStatus("in_progress"),
            icon:
                _isUpdatingStatus
                    ? SizedBox(
                      width: screenWidth * 0.05,
                      height: screenWidth * 0.05,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                    : Icon(Icons.play_arrow, size: screenWidth * 0.06),
            label: Text(
              _isUpdatingStatus ? "Memulai..." : "Mulai Perjalanan",
              style: TextStyle(fontSize: screenWidth * 0.04),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _successColor, // Use success color
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.04),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.05,
                vertical: screenHeight * 0.015,
              ),
              minimumSize: Size(screenWidth * 0.9, screenHeight * 0.06),
            ),
          )
        else if (_status == "in_progress")
          ElevatedButton.icon(
            onPressed: _isCompleting ? null : _completeRide,
            icon:
                _isCompleting
                    ? SizedBox(
                      width: screenWidth * 0.05,
                      height: screenWidth * 0.05,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                    : Icon(Icons.check_circle, size: screenWidth * 0.06),
            label: Text(
              _isCompleting ? "Menyelesaikan..." : "Selesaikan Perjalanan",
              style: TextStyle(fontSize: screenWidth * 0.04),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.04),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.05,
                vertical: screenHeight * 0.015,
              ),
              minimumSize: Size(screenWidth * 0.9, screenHeight * 0.06),
            ),
          ),
        // Add a "Call Passenger" button that fades in/out with FAB animation
        // This button is always available, but its visibility is animated.
        SizedBox(height: screenHeight * 0.015),
        FadeTransition(
          opacity: _fabAnimation,
          child: ScaleTransition(
            scale: _fabAnimation,
            child: ElevatedButton.icon(
              onPressed: _callPassenger,
              icon: Icon(Icons.phone, size: screenWidth * 0.05),
              label: Text(
                "Telepon Penumpang",
                style: TextStyle(fontSize: screenWidth * 0.038),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade200,
                foregroundColor: _textColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(screenWidth * 0.04),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.04,
                  vertical: screenHeight * 0.012,
                ),
                minimumSize: Size(screenWidth * 0.9, screenHeight * 0.055),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;


    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Map Layer
          SizedBox(
            width: screenWidth,
            height: screenHeight,
            child: _buildMap(),
          ),

          // Status Indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + screenHeight * 0.02,
            left: screenWidth * 0.05,
            right: screenWidth * 0.05,
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildStatusIndicator(),
            ),
          ),

          // Draggable Scrollable Sheet for Ride Details
          Positioned.fill(
            child: DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.25, // Initial collapsed height
              minChildSize: 0.15, // Minimum height when collapsed
              maxChildSize: 0.8, // Maximum height when expanded
              builder: (
                BuildContext context,
                ScrollController scrollController,
              ) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(screenHeight * 0.03),
                      topRight: Radius.circular(screenHeight * 0.03),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Handle bar
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: screenHeight * 0.01,
                        ),
                        child: Container(
                          width: screenWidth * 0.1,
                          height: screenHeight * 0.005,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(
                              screenWidth * 0.01,
                            ),
                          ),
                        ),
                      ),
                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.04,
                          ),
                          child: _buildPassengerInfoContent(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Ensure ChatService and other utility functions are correctly implemented elsewhere
// as they are imported but not provided in the original code snippet for this request.