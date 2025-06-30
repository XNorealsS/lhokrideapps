import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:url_launcher/url_launcher.dart';

class LocationUtils {
  static List<Map<String, dynamic>> _locationData = [];

  static final Map<String, String> _smartMappings = {
    'rumahsakit':
        'rumah sakit, rs, hospital, klinik, puskesmas, posyandu, balai pengobatan',
    'sekolah':
        'sdk, smp, sma, smk, sd, universitas, kampus, institut, akademi, pondok pesantren, madrasah, tk, paud',
    'masjid':
        'mushola, musholla, surau, langgar, islamic center, meunasah, baitul',
    'kantor':
        'perkantoran, office, gedung, balai, dinas, instansi, pemda, bupati, camat, lurah',
    'pasar':
        'market, toko, mall, plaza, supermarket, minimarket, warung, kedai, took',
    'stasiun': 'terminal, bKamura, airport, pelabuhan, dermaga, pangkalan',
    'hotel': 'penginapan, losmen, guest house, resort, homestay, wisma',
    'cafe':
        'warung, restoran, restaurant, kedai, kopi, rumah makan, warung kopi',
    'bank': 'atm, bri, bca, mandiri, bni, btn, mega, danamon, cimb, permata',
    'jalan': 'jl, jln, street, road, lr, lorong',
    'gang': 'gg, alley, aly',
    'komplek': 'kompleks, complex, perumahan, cluster, residence',
    'desa': 'dusun, kampung, gampong, mukim, kecamatan',
    'pantai': 'beach, laut, pesisir, tepi laut',
    'taman': 'park, lapangan, alun, plaza',
    'spbu': 'pom bensin, stasiun pengisian, pertamina, shell',
  };

  static Future<void> loadLocationData() async {
    try {
      final String data = await rootBundle.loadString(
        'assets/maps/alamat_lengkap_aceh_utara_lhokseumawe.json',
      );
      final Map<String, dynamic> jsonData = json.decode(data);

      // Sesuaikan dengan struktur data baru
      if (jsonData.containsKey('daftar_tempat')) {
        _locationData =
            (jsonData['daftar_tempat'] as List<dynamic>)
                .map((e) => e as Map<String, dynamic>)
                .toList();
      } else {
        // Fallback untuk struktur lama
        _locationData =
            (jsonData as List<dynamic>)
                .map((e) => e as Map<String, dynamic>)
                .toList();
      }

      print('Data lokasi dimuat: ${_locationData.length} tempat');
    } catch (e) {
      print('Error memuat data lokasi: $e');
    }
  }

  static Future<LatLng?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      ).timeout(const Duration(seconds: 15));

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Error mendapatkan lokasi: $e');
      return null;
    }
  }

  static Map<String, dynamic>? findNearestPlace(
    LatLng latlng, {
    double maxDistance = 300,
  }) {
    Map<String, dynamic>? nearest;
    double minDistance = double.infinity;

    for (var place in _locationData) {
      // Sesuaikan field name dengan struktur baru
      final lat = parseDouble(place['lat']);
      final lon = parseDouble(place['lon']);
      if (lat == null || lon == null) continue;

      final distance = Geolocator.distanceBetween(
        latlng.latitude,
        latlng.longitude,
        lat,
        lon,
      );
      if (distance < maxDistance && distance < minDistance) {
        minDistance = distance;
        nearest = place;
        nearest['distance'] = minDistance; // Tambahkan jarak untuk referensi
      }
    }

    return nearest;
  }

  static List<Map<String, dynamic>> smartSearch(
    String query, {
    int limit = 15,
  }) {
    final normalizedQuery = _normalizeText(query);
    final List<Map<String, dynamic>> results = [];
    final Set<String> addedNames = {};

    // Prioritas 1: Exact match
    for (final location in _locationData) {
      final name =
          location['nama']?.toString() ?? location['name']?.toString() ?? '';
      final normalizedName = _normalizeText(name);

      if (addedNames.contains(name) || name.isEmpty) continue;

      if (normalizedName == normalizedQuery) {
        results.add({...location, 'priority': 1});
        addedNames.add(name);
        if (results.length >= limit) break;
      }
    }

    // Prioritas 2: Starts with query
    if (results.length < limit) {
      for (final location in _locationData) {
        final name =
            location['nama']?.toString() ?? location['name']?.toString() ?? '';
        final normalizedName = _normalizeText(name);

        if (addedNames.contains(name) || name.isEmpty) continue;

        if (normalizedName.startsWith(normalizedQuery)) {
          results.add({...location, 'priority': 2});
          addedNames.add(name);
          if (results.length >= limit) break;
        }
      }
    }

    // Prioritas 3: Contains query
    if (results.length < limit) {
      for (final location in _locationData) {
        final name =
            location['nama']?.toString() ?? location['name']?.toString() ?? '';
        final kategori =
            location['kategori']?.toString() ??
            location['category']?.toString() ??
            '';
        final normalizedName = _normalizeText(name);
        final normalizedKategori = _normalizeText(kategori);

        if (addedNames.contains(name) || name.isEmpty) continue;

        if (normalizedName.contains(normalizedQuery) ||
            normalizedKategori.contains(normalizedQuery)) {
          results.add({...location, 'priority': 3});
          addedNames.add(name);
          if (results.length >= limit) break;
        }
      }
    }

    // Prioritas 4: Smart mapping
    if (results.length < limit) {
      for (final location in _locationData) {
        final name =
            location['nama']?.toString() ?? location['name']?.toString() ?? '';
        final kategori =
            location['kategori']?.toString() ??
            location['category']?.toString() ??
            '';
        final normalizedName = _normalizeText(name);
        final normalizedKategori = _normalizeText(kategori);

        if (addedNames.contains(name) || name.isEmpty) continue;

        bool found = false;
        for (final key in _smartMappings.keys) {
          if (normalizedQuery.contains(key)) {
            final synonyms = _smartMappings[key]!.split(', ');
            for (final synonym in synonyms) {
              if (normalizedName.contains(synonym) ||
                  normalizedKategori.contains(synonym)) {
                results.add({...location, 'priority': 4});
                addedNames.add(name);
                found = true;
                break;
              }
            }
            if (found) break;
          }
        }

        if (results.length >= limit) break;
      }
    }

    // Urutkan berdasarkan prioritas
    results.sort((a, b) {
      final priorityA = a['priority'] ?? 5;
      final priorityB = b['priority'] ?? 5;
      if (priorityA != priorityB) return priorityA.compareTo(priorityB);

      // Jika prioritas sama, urutkan alfabetis
      final nameA = a['nama']?.toString() ?? a['name']?.toString() ?? '';
      final nameB = b['nama']?.toString() ?? b['name']?.toString() ?? '';
      return nameA.compareTo(nameB);
    });

    // Hapus field priority sebelum return
    return results.map((item) {
      item.remove('priority');
      return item;
    }).toList();
  }

  // Pencarian berdasarkan kategori
  static List<Map<String, dynamic>> searchByCategory(
    String category, {
    int limit = 20,
  }) {
    final normalizedCategory = _normalizeText(category);
    final List<Map<String, dynamic>> results = [];

    for (final location in _locationData) {
      final kategori =
          location['kategori']?.toString() ??
          location['category']?.toString() ??
          '';
      final normalizedKategori = _normalizeText(kategori);

      if (normalizedKategori.contains(normalizedCategory)) {
        results.add(location);
        if (results.length >= limit) break;
      }
    }

    return results;
  }

  // Pencarian dalam radius tertentu
  static List<Map<String, dynamic>> searchNearby(
    LatLng center,
    double radiusInMeters, {
    String? filter,
  }) {
    final List<Map<String, dynamic>> results = [];

    for (var place in _locationData) {
      final lat = parseDouble(place['lat']);
      final lon = parseDouble(place['lon']);
      if (lat == null || lon == null) continue;

      final distance = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        lat,
        lon,
      );

      if (distance <= radiusInMeters) {
        final name =
            place['nama']?.toString() ?? place['name']?.toString() ?? '';

        if (filter == null ||
            _normalizeText(name).contains(_normalizeText(filter))) {
          results.add({...place, 'distance': distance});
        }
      }
    }

    // Urutkan berdasarkan jarak
    results.sort(
      (a, b) => (a['distance'] as double).compareTo(b['distance'] as double),
    );

    return results;
  }

  static String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double? parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  // Helper untuk mendapatkan statistik data
  static Map<String, int> getLocationStats() {
    final Map<String, int> stats = {};

    for (final location in _locationData) {
      final kategori =
          location['kategori']?.toString() ??
          location['category']?.toString() ??
          'Tidak Diketahui';
      stats[kategori] = (stats[kategori] ?? 0) + 1;
    }

    return stats;
  }

  static Future<void> launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Could not launch $url';
    }
  }

  // Helper untuk mendapatkan total data
  static int getTotalLocations() => _locationData.length;

}