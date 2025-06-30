// lib/pages/DeliveryMapPage.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lhokride/models/partner.dart';
import 'package:lhokride/models/menu.dart';
import 'package:lhokride/utils/route_utils.dart';
import 'package:lhokride/utils/location_utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'dart:async';
import 'dart:ui' as ui; // Import for ui.Path
import 'dart:math' as math; // For animation timing if needed

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
  static const Color white = Colors.white; // Added white color
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

    // Membuat bentuk segitiga untuk tail marker
    path.moveTo(size.width / 2, size.height); // Titik bawah (ujung tail)
    path.lineTo(0, 0); // Titik kiri atas
    path.lineTo(size.width, 0); // Titik kanan atas
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is MarkerTailPainter && oldDelegate.color != color;
  }
}

class DeliveryMapPage extends StatefulWidget {
  final Partner partner;
  final Map<Menu, int> cart;
  final double totalPrice;

  const DeliveryMapPage({
    Key? key,
    required this.partner,
    required this.cart,
    required this.totalPrice,
  }) : super(key: key);

  @override
  State<DeliveryMapPage> createState() => _DeliveryMapPageState();
}

class _DeliveryMapPageState extends State<DeliveryMapPage>
    with TickerProviderStateMixin {
      late final AnimatedMapController _animatedMapController = AnimatedMapController(vsync: this);

  LatLng? _selectedDeliveryLocation;
  String? _deliveryAddress;
  double? _estimatedDistance;
  int? _estimatedDuration;
  int? _deliveryFee;
  bool _isLoadingAddress = false;
  bool _isCalculatingRoute = false;
  bool _isMapMoving = false; // Track map movement for marker animation

  final MapController _mapController = MapController();
  Timer? _mapMoveDebounce;
  LatLng? _mapCenter;
  LatLng? _currentLocation; // To store the user's current actual location

  // Enhanced marker animation controllers
  late AnimationController _markerScaleController;
  late AnimationController _markerBounceController;
  late AnimationController _markerLoadingController;
  late AnimationController _markerRiseController;
  late AnimationController _markerPulsateController;

  // Enhanced animations
  late Animation<double> _markerScaleAnimation;
  late Animation<double> _markerBounceAnimation;
  late Animation<double> _markerLoadingAnimation;
  late Animation<double> _markerRiseAnimation;
  late Animation<double> _markerPulsateAnimation;

  // Added for the marker's appearance
  Color get _crosshairColor => AppColors.gojekGreen;
  bool get _isPickupStep => false; // Assuming this page is always for delivery

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initMap();
  }

  void _initAnimations() {
    // Scale animation for initial marker appearance
    _markerScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _markerScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _markerScaleController, curve: Curves.elasticOut),
    );

    // Rise animation for marker moving up when map starts moving
    _markerRiseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _markerRiseAnimation = Tween<double>(begin: 0.0, end: -20.0).animate(
      CurvedAnimation(parent: _markerRiseController, curve: Curves.easeOutBack),
    );

    // Bounce animation for marker settling down when map stops moving
    _markerBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _markerBounceAnimation = Tween<double>(begin: -20.0, end: 0.0).animate(
      CurvedAnimation(parent: _markerBounceController, curve: Curves.bounceOut),
    );

    // Loading animation for spinning indicator
    _markerLoadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _markerLoadingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _markerLoadingController, curve: Curves.linear),
    );

    // Pulsate animation for the marker when idle
    _markerPulsateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _markerPulsateAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(
        parent: _markerPulsateController,
        curve: Curves.easeInOut,
      ),
    );
    _markerPulsateController.repeat(
      reverse: true,
    ); // Make it pulsate indefinitely

    // Start with initial scale animation
    _markerScaleController.forward();
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // User denied permission
          print("[LOKASI] Izin lokasi ditolak.");
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        // User denied permission permanently
        print("[LOKASI] Izin lokasi ditolak permanen.");
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        // Added a timeout to prevent indefinite waiting
        // If location is not obtained within this time, it will throw an error
        // and fall into the catch block.
        // It's important for UX that the app doesn't hang.
        timeLimit: const Duration(seconds: 10),
      );

      return position;
    } on TimeoutException catch (e) {
      print("[LOKASI] Timeout mendapatkan lokasi: $e");
      return null;
    } catch (e) {
      print("[LOKASI] Error mendapatkan lokasi awal: $e");
      return null;
    }
  }

  Future<void> _initMap() async {
    setState(() {
      _isLoadingAddress = true;
    });

    LatLng initialCenter;
    String? initialAddress;

    try {
      Position? position = await _getCurrentLocation();

      if (position != null) {
        initialCenter = LatLng(position.latitude, position.longitude);
        _currentLocation = initialCenter; // Set current location
        _mapController.move(initialCenter, 16.0); // Move instantly for initial setup
        // Fetch address for initial location
        final result = await RouteUtils.reverseGeocode(initialCenter);
        initialAddress = result;
      } else {
        // Default to Jakarta if current location cannot be obtained
        initialCenter = LatLng(-6.1753924, 106.8271528); // Default to Jakarta
        initialAddress = "Tidak dapat menemukan lokasi Anda. Gerakkan peta untuk memilih.";
        _mapController.move(initialCenter, 14.0); // Slightly zoomed out for a broader view
      }

      _mapCenter = initialCenter;
      _selectedDeliveryLocation = initialCenter; // Set initial delivery location
      _deliveryAddress = initialAddress;

      // Start loading animation
      _startLoadingAnimation();

      // Trigger route calculation for initial location if we have a partner and initial location.
      if (_selectedDeliveryLocation != null) {
        _calculateRouteAndFee(); //
      }

    } catch (e) {
      print("Error getting current location or initial address: $e");
      initialCenter = LatLng(-6.1753924, 106.8271528); // Fallback to Jakarta
      initialAddress = 'Gagal memuat lokasi awal. Silakan coba lagi.';
      _mapController.move(initialCenter, 14.0);
      _mapCenter = initialCenter;
      _deliveryAddress = initialAddress;
    } finally {
      setState(() {
        _isLoadingAddress = false;
      });
      _stopLoadingAnimation(); // Ensure loading animation stops
    }
  }

  void _startLoadingAnimation() {
    if (!_markerLoadingController.isAnimating) {
      _markerLoadingController.repeat();
    }
  }

  void _stopLoadingAnimation() {
    if (_markerLoadingController.isAnimating) {
      _markerLoadingController.stop();
      _markerLoadingController.reset();
    }
  }

  Future<void> _fetchAddressForLocation(LatLng location) async {
    if (_isLoadingAddress) return; // Prevent multiple simultaneous fetches

    setState(() {
      _isLoadingAddress = true;
      _deliveryAddress = 'Mencari alamat...';
      _estimatedDistance = null; // Reset these when searching for new address
      _estimatedDuration = null;
      _deliveryFee = null;
    });

    try {
      final result = await RouteUtils.reverseGeocode(location); // Use passed location

      String? address = result;
      setState(() {
        _selectedDeliveryLocation = location;
        _deliveryAddress = address ?? 'Alamat tidak ditemukan';
      });

      _calculateRouteAndFee();
    } catch (e) {
      print("Error fetching address: $e");
      setState(() {
        _deliveryAddress = 'Gagal memuat alamat';
      });
    } finally {
      setState(() {
        _isLoadingAddress = false;
      });
      // Stop loading and start bounce animation after address is fetched
      _stopLoadingAnimation();
      await _markerBounceController.forward(from: 0.0);
    }
  }

  Future<void> _calculateRouteAndFee() async {
    if (_selectedDeliveryLocation == null) return;

    setState(() {
      _isCalculatingRoute = true;
    });

    try {
      LatLng partnerLocation = LatLng(
        widget.partner.latitude,
        widget.partner.longitude,
      );

      final routeData = await RouteUtils.calculateRoute(
        partnerLocation,
        _selectedDeliveryLocation!,
      );

      final distance = routeData['distance'] as double;
      final eta = routeData['eta'] as int;

      final price = await RouteUtils.calculateDynamicPrice(distance);

      const foodPreparationTime = Duration(minutes: 10);
      final totalEta = Duration(seconds: eta) + foodPreparationTime;

      setState(() {
        _estimatedDistance = distance;
        _estimatedDuration = totalEta.inMinutes;
        _deliveryFee = price;
      });
    } catch (e) {
      print("Error calculating route or fee: $e");
      setState(() {
        _estimatedDistance = null;
        _estimatedDuration = null;
        _deliveryFee = null;
        // Provide user feedback if route calculation fails
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal menghitung rute dan biaya pengiriman.'),
          ),
        ); //
      });
    } finally {
      setState(() {
        _isCalculatingRoute = false;
      });
    }
  }

  void _onMapMoved(MapCamera camera) {
    // Start rise animation when map starts moving (onMapEvent triggers MoveStart)
    // The debounce timer handles fetching address only after movement stops.
    _mapMoveDebounce?.cancel();
    _mapMoveDebounce = Timer(const Duration(milliseconds: 500), () {
      if (_mapCenter != camera.center) {
        setState(() {
          _mapCenter = camera.center;
          _isMapMoving = false; // Reset moving state after debounce
        });
        // Fetch address after a short delay
        Future.delayed(const Duration(milliseconds: 200), () {
          _fetchAddressForLocation(camera.center);
        });
      } else {
        setState(() {
          _isMapMoving = false; // Reset if map didn't actually move
        });
      }
    });
  }

  void _showLocationConfirmationDialog() {
    if (_selectedDeliveryLocation == null ||
        _deliveryAddress == null ||
        _deliveryFee == null ||
        _isLoadingAddress || // Ensure no background operations are running
        _isCalculatingRoute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mohon tunggu hingga lokasi dan biaya pengiriman terhitung.',
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            'Konfirmasi Lokasi Pengiriman',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alamat: $_deliveryAddress',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              if (_estimatedDistance != null)
                Text(
                  'Jarak: ${(_estimatedDistance!).toStringAsFixed(2)} km',
                  style: const TextStyle(fontSize: 16),
                ),
              const SizedBox(height: 10),
              Text(
                'Biaya Pengiriman: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ').format(_deliveryFee)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryOrange,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Batal',
                style: TextStyle(color: AppColors.greyText),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Konfirmasi'),
              onPressed: () {
                Navigator.of(context).pop();
                context.push(
                  '/order_confirmation',
                  extra: {
                    'partner': widget.partner,
                    'cart': widget.cart,
                    'totalPrice': widget.totalPrice,
                    'deliveryLocation': _selectedDeliveryLocation,
                    'deliveryAddress': _deliveryAddress,
                    'deliveryFee': _deliveryFee,
                    'estimatedDistance': _estimatedDistance,
                    'estimatedDuration': _estimatedDuration,
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  // New function to jump to current location
  Future<void> _jumpToCurrentLocation() async {
    setState(() {
      _isLoadingAddress = true; // Indicate loading
      _isMapMoving = true; // Indicate map is moving
      _startLoadingAnimation(); // Start loading spinner
    });
    try {
      Position? position = await _getCurrentLocation();
      if (position != null) {
        LatLng newLocation = LatLng(position.latitude, position.longitude);
        _currentLocation = newLocation;

        // Animate camera to current location
       _animatedMapController.animateTo(
  dest: newLocation,
  zoom: 16.0,
  curve: Curves.easeInOut,
);


        // Fetch address for the new map center after animation completes
        _fetchAddressForLocation(newLocation);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat menemukan lokasi Anda saat ini.'),
          ),
        );
      }
    } catch (e) {
      print("Error jumping to current location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mendapatkan lokasi Anda saat ini.'),
        ),
      );
    } finally {
      setState(() {
        _isLoadingAddress = false;
        _isMapMoving = false; // Reset map moving state
      });
      // Ensure loading animation stops after process
      _stopLoadingAnimation();
      // Trigger bounce animation as map movement ends
      await _markerBounceController.forward(from: 0.0); //
    }
  }

  @override
  void dispose() {
    _mapMoveDebounce?.cancel();
    _markerScaleController.dispose();
    _markerBounceController.dispose();
    _markerLoadingController.dispose();
    _markerRiseController.dispose();
    _markerPulsateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Lokasi Pengiriman'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _mapCenter ?? LatLng(5.1787, 96.8833), // Lhokseumawe default
              zoom: 15.0,
              minZoom: 10.0,
              maxZoom: 18.0,
              interactiveFlags:
                  InteractiveFlag.drag | InteractiveFlag.pinchZoom,
              onMapEvent: (event) {
                if (event is MapEventMoveStart) {
                  setState(() {
                    _isMapMoving = true;
                    // Start marker rise animation when map starts moving
                    _markerRiseController.forward(from: 0.0); //
                    _markerPulsateController.stop(); // Stop pulsation during move
                  });
                } else if (event is MapEventMoveEnd) {
                  _onMapMoved(event.camera);
                  setState(() {
                    // Reset moving state will be handled by debounce
                    // Re-start pulsation when map movement ends and marker settles
                    if (!_markerPulsateController.isAnimating) {
                      _markerPulsateController.repeat(reverse: true); //
                    }
                  });
                }
              },
              onTap: (_, latlng) {
                // Keep onTap disabled as per original intention, selection is via map center
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              if (_currentLocation != null) // Show current location circle
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentLocation!,
                      radius: 15, // Radius in meters
                      color: Colors.blue.withOpacity(0.3),
                      borderColor: Colors.blueAccent,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              // Add Partner location marker for context
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(widget.partner.latitude, widget.partner.longitude),
                    width: 40.0,
                    height: 40.0,
                    child: Icon(
                      Icons.storefront,
                      color: AppColors.primaryOrange,
                      size: 35.0,
                    ),
                    // anchorPos: AnchorPos.align(AnchorAlign.top), // Anchor to the top of the icon
                  ),
                ],
              ),
            ],
          ),

          // Enhanced Crosshair and Marker
          _buildEnhancedMarker(),

          // Address Display at Top
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: SafeArea(
              child: Card(
                color: Colors.white.withOpacity(0.95),
                elevation: 8,
                shadowColor: AppColors.primaryOrange.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.gojekGreenLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: AppColors.gojekGreen,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _deliveryAddress ??
                                  'Gerakkan peta untuk memilih lokasi...',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (_isLoadingAddress || _isCalculatingRoute)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.gojekGreen,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _isLoadingAddress
                                    ? 'Memuat alamat...'
                                    : 'Menghitung rute...',
                                style: TextStyle(
                                  color: AppColors.greyText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Button to jump to current location
          Positioned(
            bottom: 120, // Adjusted position to be above the confirm button
            right: 20,
            child: FloatingActionButton(
              onPressed: (_isLoadingAddress || _isCalculatingRoute)
                  ? null // Disable if loading
                  : _jumpToCurrentLocation,
              backgroundColor: AppColors.accentBlue,
              foregroundColor: Colors.white,
              child: const Icon(Icons.my_location),
              heroTag: "currentLocationBtn", // Add a unique heroTag
            ),
          ),

          // Bottom confirm button
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gojekGreen.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed:
                    (_selectedDeliveryLocation != null &&
                            _deliveryAddress != null &&
                            _deliveryFee != null &&
                            !_isLoadingAddress &&
                            !_isCalculatingRoute)
                        ? _showLocationConfirmationDialog
                        : null, // Button is disabled until all data is loaded
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gojekGreen, // Use Gojek green
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  disabledBackgroundColor: AppColors.greyText.withOpacity(
                    0.6,
                  ), // Disabled color
                  elevation: 0,
                ),
                child: Text(
                  _selectedDeliveryLocation == null
                      ? 'Gerakkan peta untuk memilih lokasi pengiriman'
                      : (_isLoadingAddress || _isCalculatingRoute)
                      ? 'Memuat informasi...'
                      : 'Konfirmasi Lokasi Pengiriman',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedMarker() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The animated marker itself
          AnimatedBuilder(
            animation: Listenable.merge([
              _markerScaleAnimation,
              _markerRiseAnimation,
              _markerBounceAnimation,
              _markerPulsateAnimation,
              _markerLoadingAnimation,
            ]),
            builder: (context, child) {
              double scale = _markerScaleAnimation.value;
              double offsetY = 0.0;

              // Apply pulsation only when not moving and not loading
              if (!_isMapMoving && !_isLoadingAddress && !_isCalculatingRoute) { //
                scale *= _markerPulsateAnimation.value;
              }

              if (_isMapMoving) {
                // Rise animation when map is moving
                offsetY = _markerRiseAnimation.value;
              } else if (_markerBounceController.isAnimating) {
                // Bounce animation when settling
                offsetY = _markerBounceAnimation.value;
              }

              return Transform.translate(
                offset: Offset(0, offsetY),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 40, // Increased size for better visibility
                    height: 40,
                    decoration: BoxDecoration(
                      color: _crosshairColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child:
                        (_isLoadingAddress || _isCalculatingRoute || _isMapMoving)
                            ? RotationTransition(
                              turns: _markerLoadingAnimation,
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.white,
                                  ),
                                ),
                              ),
                            )
                            : Icon(
                              _isPickupStep // This is always false in this page
                                  ? Icons.person
                                  : Icons
                                      .location_on, // Changed icon for delivery
                              color: AppColors.white,
                              size: 24, // Increased icon size
                            ),
                  ),
                ),
              );
            },
          ),
          // Marker tail
          CustomPaint(
            size: const Size(16, 12), // Adjusted size for the tail
            painter: MarkerTailPainter(_crosshairColor),
          ),
        ],
      ),
    );
  }
}