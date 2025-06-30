// services/rtdb_service.dart
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';

class RTDBService {
  static final RTDBService _instance = RTDBService._internal();
  static RTDBService get instance => _instance;
  RTDBService._internal();

  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Timer? _locationTimer;

  Future<void> initialize() async {
    try {
      // Set up database rules and offline settings
      await _database.goOnline();
    } catch (e) {
      print("RTDB initialization error: $e");
    }
  }
}