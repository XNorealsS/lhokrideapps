import 'dart:convert';
import 'dart:async'; // Untuk TimeoutException
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart'; // Untuk fallback jarak lurus

import 'package:shared_preferences/shared_preferences.dart';

// --- Konfigurasi API ---
// GANTI DENGAN API KEY GEOAPIFY Kamu!
// Kamu bisa mendapatkan API Key gratis di https://www.geoapify.com/
const String BACKEND_BASE_URL = 'https://api.lhokride.com/api/geocode';
const String GEOAPIFY_API_KEY =
    '914832abb2ec460ba8e160d980a18ac3'; // <--- GANTI INI
const String GEOAPIFY_ROUTING_BASE_URL = 'https://api.geoapify.com/v1/routing';
const String GEOAPIFY_GEOCODING_BASE_URL =
    'https://api.geoapify.com/v1/geocode';
const String GEOAPIFY_TILE_URL_TEMPLATE =
    'https://maps.geoapify.com/v1/tile/osm-bright/{z}/{x}/{y}.png?apiKey=$GEOAPIFY_API_KEY';

const String LHOKSEUMAWE_BBOX =
    '96.90,5.10,97.20,5.40'; // Contoh, sesuaikan lebih akurat jika perlu

class RouteUtils {
  // --- Routing API ---
  static Future<Map<String, dynamic>> calculateRoute(
    LatLng pickup,
    LatLng destination,
  ) async {
    print("[API Service] Memulai perhitungan rute...");
    print("[API Service] Pickup: $pickup");
    print("[API Service] Tujuan: $destination");

    try {
      print(
        "[API Service] Mencoba rute dengan Geoapify Routing API (timeout 10 detik)...",
      );
      final result = await _fetchGeoapifyRoute(
        pickup,
        destination,
        const Duration(seconds: 10),
      );
      print("[API Service] Rute Geoapify berhasil ditemukan.");
      return result;
    } catch (e) {
      print("[API Service] Rute Geoapify gagal: $e");
      print(
        "[API Service] Menggunakan metode fallback sederhana (jarak lurus)...",
      );
      // Jika Geoapify gagal, segera berikan hasil fallback
      return _fallbackCalculation(pickup, destination);
    }
  }

  static double _parseToDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      // If it's a string, try parsing it
      return double.tryParse(value) ?? 0.0;
    }
    // For null or any other unhandled type, return 0.0
    return 0.0;
  }

  static Future<Map<String, dynamic>> _fetchGeoapifyRoute(
    LatLng pickup,
    LatLng destination,
    Duration timeoutDuration,
  ) async {
    // Round coordinates to 6 decimal places to avoid precision issues
    final pickupLat = double.parse(pickup.latitude.toStringAsFixed(6));
    final pickupLng = double.parse(pickup.longitude.toStringAsFixed(6));
    final destLat = double.parse(destination.latitude.toStringAsFixed(6));
    final destLng = double.parse(destination.longitude.toStringAsFixed(6));

    // Validate coordinates
    if (pickupLat < -90 || pickupLat > 90 || destLat < -90 || destLat > 90) {
      throw Exception('Invalid latitude values');
    }
    if (pickupLng < -180 ||
        pickupLng > 180 ||
        destLng < -180 ||
        destLng > 180) {
      throw Exception('Invalid longitude values');
    }

    // Build waypoints string properly - using lonlat: prefix for longitude,latitude format
    final waypoints = 'lonlat:$pickupLng,$pickupLat|lonlat:$destLng,$destLat';

    // Build URL with proper encoding
    final url = Uri.parse(GEOAPIFY_ROUTING_BASE_URL).replace(
      queryParameters: {
        'waypoints': waypoints,
        'mode': 'motorcycle',
        'details': 'route_details',
        'format': 'geojson',
        'apiKey': GEOAPIFY_API_KEY,
      },
    );

    print("[API Service] Pickup coordinates: $pickupLat, $pickupLng");
    print("[API Service] Destination coordinates: $destLat, $destLng");
    print("[API Service] Waypoints string: $waypoints");
    print("[API Service] Mengirim permintaan rute ke URL: $url");
    print(
      "[API Service] Timeout rute diatur selama ${timeoutDuration.inSeconds} detik...",
    );

    try {
      final response = await http
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'YourAppName/1.0', // Add user agent
            },
          )
          .timeout(
            timeoutDuration,
            onTimeout: () {
              print(
                "[API Service] TIMEOUT: Permintaan rute melebihi durasi ${timeoutDuration.inSeconds} detik.",
              );
              throw TimeoutException(
                'Request to Geoapify routing timed out after $timeoutDuration',
              );
            },
          );

      print(
        "[API Service] Mendapat respons rute dengan status code: ${response.statusCode}",
      );
      print(
        "[API Service] Response body: ${response.body}",
      ); // Add this for debugging

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['features'] != null && (data['features'] as List).isNotEmpty) {
          final route = data['features'][0];
          final geometry = route['geometry'];
          final properties = route['properties'];

          if (geometry == null || geometry['coordinates'] == null) {
            throw Exception('Invalid route geometry in response');
          }

          final coordinates = geometry['coordinates'] as List;
          print("[API Service] Raw Geometry Coordinates: $coordinates");

          final points = <LatLng>[];

          // Handle nested coordinate structure (3-level array)
          if (coordinates.isNotEmpty && coordinates[0] is List) {
            // Check if this is a LineString (2D array) or MultiLineString (3D array)
            if (coordinates[0][0] is List) {
              // MultiLineString (3D array) - flatten to 2D
              for (final lineString in coordinates) {
                for (final coord in lineString as List) {
                  if (coord is List && coord.length >= 2) {
                    final lng = _parseToDouble(coord[0]);
                    final lat = _parseToDouble(coord[1]);
                    points.add(LatLng(lat, lng));
                  }
                }
              }
            } else {
              // LineString (2D array)
              for (final coord in coordinates) {
                if (coord is List && coord.length >= 2) {
                  final lng = _parseToDouble(coord[0]);
                  final lat = _parseToDouble(coord[1]);
                  points.add(LatLng(lat, lng));
                }
              }
            }
          }

          if (points.isEmpty) {
            throw Exception('No valid coordinates found in route');
          }

          final distance = Geolocator.distanceBetween(
            pickup.latitude,
            pickup.longitude,
            destination.latitude,
            destination.longitude,
          );

          const double averageSpeed = 40; // km/h
          final durationMin = (distance / 1000) / averageSpeed * 60;

          print("[API Service] Jarak: ${distance.toStringAsFixed(2)} km");
          print("[API Service] Estimasi waktu: ${durationMin.round()} menit");
          print("[API Service] Titik koordinat rute: ${points.length} titik");

          return {
            'success': true,
            'routePoints': points,
            'distance': (distance / 1000),
            'eta': durationMin.round(),
          };
        } else {
          print(
            "[API Service] Tidak ada rute yang ditemukan dalam respons Geoapify.",
          );
          print("[API Service] Full response: ${response.body}");
          throw Exception('Tidak ada rute tersedia dari Geoapify.');
        }
      } else {
        String errorMessage = 'Unknown error';
        try {
          final errorBody = json.decode(response.body);
          errorMessage =
              errorBody['message'] ??
              errorBody['error'] ??
              'HTTP ${response.statusCode}';
        } catch (e) {
          errorMessage = 'HTTP ${response.statusCode}: ${response.body}';
        }

        print("[API Service] Error HTTP dari Geoapify: ${response.statusCode}");
        print("[API Service] Error body: ${response.body}");
        throw Exception("Gagal mengambil rute dari Geoapify: $errorMessage");
      }
    } catch (e) {
      print("[API Service] Kesalahan saat mengambil rute dari Geoapify: $e");
      rethrow;
    }
  }

  static Map<String, dynamic> _fallbackCalculation(
    LatLng pickup,
    LatLng destination,
  ) {
    print(
      "[API Service] Fallback aktif: Menghitung jarak lurus sebagai cadangan.",
    );

    final distance =
        Geolocator.distanceBetween(
          pickup.latitude,
          pickup.longitude,
          destination.latitude,
          destination.longitude,
        ) /
        1000; // meter -> km

    // Estimasi waktu berdasarkan kecepatan rata-rata 25 km/jam (lebih realistis untuk kota)
    final eta = (distance / 25 * 60).round();

    return {
      'success': false, // MenKamukan ini adalah rute fallback
      'routePoints': [
        pickup,
        destination,
      ], // Hanya dua titik untuk rute garis lurus
      'distance': double.parse(distance.toStringAsFixed(2)),
      'eta': eta,
    };
  }

  static Future<List<Map<String, dynamic>>> smartSearch(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
      '$BACKEND_BASE_URL/searchbyname?q=${Uri.encodeComponent(query)}',
    );

    print("[API Service] Mencari lokasi dengan query: $query");
    print("[API Service] URL Backend: $url");

    try {
      final response = await http.get(
        url,
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final results = data['data']['combined'] as List? ?? [];

          return results.map<Map<String, dynamic>>((item) {
            // Handle koordinat berdasarkan source
            double lat, lon;

            if (item['source'] == 'place') {
              // Untuk places, koordinat dalam format [latitude, longitude]
              lat = (item['coordinates'][0] as num).toDouble();
              lon = (item['coordinates'][1] as num).toDouble();
            } else {
              // Untuk regions, koordinat dalam format [latitude, longitude]
              lat = (item['coordinates'][0] as num).toDouble();
              lon = (item['coordinates'][1] as num).toDouble();
            }

            return {
              'name': item['fullName'] ?? item['name'] ?? 'Unnamed Location',
              'lat': lat,
              'lon': lon,
              'type': item['type'] ?? 'unknown',
              'source': item['source'] ?? 'unknown',
              'score': item['score'] ?? 1.0,
            };
          }).toList();
        }
      }

      print(
        "[API Service] Tidak ada hasil ditemukan untuk query: '$query' (Status: ${response.statusCode})",
      );
      return [];
    } catch (e) {
      print("[API Service] Error saat mencari lokasi: $e");
      return [];
    }
  }

  // --- Reverse Geocoding API ---
  static Future<String> reverseGeocode(LatLng location) async {
    final url = Uri.parse(
      '$BACKEND_BASE_URL/srchbycoordinates?lat=${location.latitude}&lon=${location.longitude}',
    );

    print("[API Service] Mengambil alamat dari koordinat: $location");
    print("[API Service] URL Backend: $url");

    try {
      final response = await http.get(
        url,
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final locationData = data['data'];

          // Buat alamat berdasarkan type dan data yang tersedia
          String address = '';

          switch (locationData['type']) {
            case 'place':
              address =
                  locationData['fullName'] ??
                  '${locationData['name']} - ${locationData['address']}';
              break;
            case 'village':
              address =
                  locationData['fullName'] ??
                  '${locationData['name']}, ${locationData['district']}, ${locationData['regency']}';
              break;
            case 'district':
              address =
                  locationData['fullName'] ??
                  '${locationData['name']}, ${locationData['regency']}';
              break;
            case 'regency':
              address = locationData['fullName'] ?? locationData['name'];
              break;
            default:
              address =
                  locationData['fullName'] ??
                  locationData['name'] ??
                  'Lokasi Tidak Dikenali';
          }

          return address.isNotEmpty ? address : "Alamat Tidak Dikenali";
        }
      }

      print(
        "[API Service] Tidak ada alamat ditemukan untuk koordinat: $location (Status: ${response.statusCode})",
      );
      return "Alamat Tidak Ditemukan";
    } catch (e) {
      print("[API Service] Error saat reverse geocoding: $e");
      return "Gagal Mengambil Alamat";
    }
  }

  // --- Fungsi untuk mendapatkan lokasi berdasarkan koordinat dengan detail ---
  static Future<Map<String, dynamic>?> getLocationByCoordinates(
    double lat,
    double lon,
  ) async {
    final url = Uri.parse(
      '$BACKEND_BASE_URL/srchbycoordinates?lat=$lat&lon=$lon',
    );

    try {
      final response = await http.get(
        url,
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final locationData = data['data'];

          return {
            'name': locationData['name'],
            'fullName': locationData['fullName'],
            'type': locationData['type'],
            'coordinates': locationData['coordinates'],
            'distance': locationData['distance'],
            'regency': locationData['regency'],
            'district': locationData['district'],
            'address': locationData['address'],
          };
        }
      }

      return null;
    } catch (e) {
      print(
        "[API Service] Error saat mendapatkan lokasi berdasarkan koordinat: $e",
      );
      return null;
    }
  }

  // --- Utility Harga ---
  static Future<int> calculateDynamicPrice(double distanceKm) async {
    final prefs = await SharedPreferences.getInstance();

    final pricePerKm =
        double.tryParse(prefs.getString('price_per_km') ?? '2000') ?? 2000;
    final basePrice =
        double.tryParse(prefs.getString('base_price') ?? '8000') ?? 8000;
    final appFeePercent =
        double.tryParse(prefs.getString('app_fee') ?? '0') ?? 0; // persen

    int roundToNearestTen(int number) {
      int remainder = number % 10;
      if (remainder >= 5) {
        return number + (10 - remainder);
      } else {
        return number - remainder;
      }
    }

    if (distanceKm < 2.0) {
      final baseFare = 5000;
      final fee = baseFare * (appFeePercent / 100);
      final total = (baseFare + fee).round();
      return roundToNearestTen(total);
    }

    final estimatedPrice = distanceKm * pricePerKm;
    final baseFare = estimatedPrice > basePrice ? estimatedPrice : basePrice;

    final fee = baseFare * (appFeePercent / 100);
    final total = baseFare + fee;

    return roundToNearestTen(total.round());
  }
}

// Helper untuk parsing double yang aman
extension LatLngParser on Map<String, dynamic> {
  double? parseDouble(String key) {
    final value = this[key];
    if (value is num) {
      return value.toDouble();
    } else if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
