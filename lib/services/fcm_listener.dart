// lib/services/fcm_listener.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart'; // Still needed for AndroidNotificationDetails icon
import 'package:flutter/foundation.dart'; // For defaultTargetPlatform
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';

// Import main.dart untuk mengakses navigatorKey dan onDidReceiveNotificationResponse
import 'package:lhokride/main.dart'; // <<< PASTIKAN PATH INI SESUAI DENGAN main.dart Kamu
import 'package:firebase_core/firebase_core.dart'; // <<< IMPORT INI DITAMBAHKAN UNTUK FirebaseException

class FCMService {
  static final FCMService _instance = FCMService._internal();
  static FCMService get instance => _instance;
  FCMService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final String _baseUrl =
      'http://api.lhokride.com/api/auth'; // Adjust this to your API base URL

  bool _isEmulator = false;
  bool _fcmAvailable = true;
  Timer? _retryTimer;

  // Stream controller to emit foreground messages to widgets
  final StreamController<RemoteMessage> _messageStreamController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get onMessage => _messageStreamController.stream;

  // Method to add messages to the stream
  void addMessageToStream(RemoteMessage message) {
    _messageStreamController.add(message);
  }

  Future<void> initialize() async {
    print("✅ FCM Service initialized");
    _detectEmulator();
    await _initLocalNotifications();
    _requestPermissions();
    _getToken(); // This will get the token and store it locally
    _setupForegroundMessageHandling();
    _setupMessageOpenedAppHandling();
    _checkForInitialMessage(); // Handle app opened from terminated state
  }

  Future<void> _initLocalNotifications() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(android: android, iOS: ios);

      await _localNotifications.initialize(
        settings,
        // Use the top-level function from main.dart for both foreground and background responses
        onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            onDidReceiveNotificationResponse,
      );

      // Create a notification channel for Android (required for Android 8.0+)
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel', // id: IMPORTANT - this ID must match the one used in the backend's FCM message and in _firebaseMessagingBackgroundHandler
        'LhokRide+ Notifications', // title
        description:
            'This channel is used for important LhokRide+ notifications.', // description
        importance:
            Importance.max, // High importance to make heads-up notifications
        playSound: true,
        enableVibration: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      print("✅ Local notifications initialized and channel created.");
    } catch (e) {
      print("❌ Error initializing local notifications: $e");
    }
  }

  Future<void> _requestPermissions() async {
    NotificationSettings settings = await FirebaseMessaging.instance
        .requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
    print("✅ User granted permission: ${settings.authorizationStatus}");
  }

  Future<String?> _getToken() async {
    if (_isEmulator) {
      print("📴 Running on emulator, skipping FCM token generation.");
      _fcmAvailable = false;
      return null;
    }
    

     await registerTokenAfterLogin();
        print("✅ FCM token generated after splash.");


    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 10),
        onTimeout:
            () => throw TimeoutException('FCM token generation timed out.'),
      );
      if (token != null) {
        print("✅ FCM token received.");
        await _storage.write(key: 'fcm_token', value: token);
        return token;
      } else {
        print("❌ FCM token is null.");
        _fcmAvailable = false;
        return null;
      }
    } catch (e) {
      print("❌ Error getting FCM token: $e");
      _fcmAvailable = false;
      return null;
    }
  }

  void _setupForegroundMessageHandling() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Received a foreground message: ${message.messageId}");
      print("Message data: ${message.data}");
      print("Message notification: ${message.notification?.title}");

      _messageStreamController.add(message); // Add to stream for UI updates

      // Show notification if it's not a data-only message OR if you want to explicitly show data-only messages
      if (message.notification != null) {
        showNotification(
          message.notification!.title,
          message.notification!.body,
          jsonEncode(message.data),
        );
      } else if (message.data.isNotEmpty) {
        // Handle data-only messages in foreground
        // You can decide whether to show a generic notification or parse data for specific display
        showNotification(
          message.data['title'] ?? 'New Message',
          message.data['body'] ?? 'You have a new update.',
          jsonEncode(message.data),
        );
      }
    });
  }

  void _setupMessageOpenedAppHandling() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('A message was opened from app: ${message.messageId}');
      // Handle navigation when app is opened from a terminated state via a notification
      onDidReceiveNotificationResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: jsonEncode(message.data),
        ),
      );
    });
  }

  Future<void> _checkForInitialMessage() async {
    // Get any messages which caused the application to open from a terminated state.
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      print(
        'App opened from terminated state by message: ${initialMessage.messageId}',
      );
      onDidReceiveNotificationResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: jsonEncode(initialMessage.data),
        ),
      );
    }
  }

  // --- THIS IS THE CRUCIAL METHOD FOR DISPLAYING NOTIFICATIONS ---
  Future<void> showNotification(
    String? title,
    String? body,
    String? payload,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel', // Must match the channel ID created earlier
      'LhokRide+ Notifications',
      channelDescription:
          'This channel is used for important LhokRide+ notifications.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon:
          '@mipmap/ic_launcher', // Ensure you have this icon in your Android project
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      0, // Notification ID
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
    print("✅ Notification shown: Title='$title', Body='$body'");
  }

  Future<void> registerTokenAfterLogin() async {
    try {
      if (!_fcmAvailable) {
        print("🟡 FCM not available, attempting to register without token.");
        await _registerWithoutToken();
        return;
      }

      final token = await _getTokenWithRetry();
      if (token == null) {
        print(
          "🟡 Failed to get FCM token, attempting to register without token.",
        );
        await _registerWithoutToken();
        return;
      }

      final userId = await _storage.read(key: 'user_id');
      final role = await _storage.read(key: 'role');

      if (userId == null || role == null) {
        print("⚠️ User ID or Role not found, cannot register FCM token.");
        return;
      }

      final success = await _sendTokenToServer(token, userId, role);
      if (success) {
        await _storage.write(key: 'fcm_token', value: token);
        await _storage.write(key: 'fcm_registered', value: 'true');
        print("✅ FCM token registered successfully to backend.");
      } else {
        print("❌ Failed to send FCM token to backend, attempting fallback.");
        await _registerWithoutToken();
      }
    } catch (e) {
      print("❌ Error in registerTokenAfterLogin: $e");
      await _registerWithoutToken(); // Fallback on any error
    }
  }

  Future<void> _registerWithoutToken() async {
    try {
      final userId = await _storage.read(key: 'user_id');
      final role = await _storage.read(key: 'role');

      if (userId == null || role == null) {
        print("⚠️ User ID or Role not found for fallback registration.");
        return;
      }

      final success = await _sendTokenToServer('EMULATOR_MODE', userId, role);
      if (success) {
        await _storage.write(key: 'fcm_registered', value: 'fallback');
        print("✅ Registered with fallback FCM token (EMULATOR_MODE).");
      } else {
        print("❌ Failed to send fallback FCM token to backend.");
      }
    } catch (e) {
      print("❌ Error in _registerWithoutToken: $e");
    }
  }

  Future<String?> _getTokenWithRetry({int maxRetries = 3}) async {
    if (!_fcmAvailable) {
      print("🟡 FCM is not available, skipping token retrieval.");
      return null;
    }

    for (int i = 0; i < maxRetries; i++) {
      try {
        final timeout =
            _isEmulator
                ? const Duration(seconds: 5)
                : const Duration(seconds: 10);

        final token = await FirebaseMessaging.instance.getToken().timeout(
          timeout,
        );

        if (token != null && token.isNotEmpty) {
          print(
            "✅ FCM token retrieved on attempt ${i + 1}: ${token.substring(0, 20)}...",
          );
          return token;
        }
      } on TimeoutException catch (e) {
        print("❌ Token retrieval timed out on attempt ${i + 1}: $e");
      } on FirebaseException catch (e) {
        // <<< FirebaseException sudah teratasi
        print(
          "❌ FirebaseException on token retrieval attempt ${i + 1}: ${e.code} - ${e.message}",
        );
        if (e.code.contains('SERVICE_NOT_AVAILABLE') ||
            e.code.contains('NETWORK_ERROR') ||
            e.code.contains('Unavailable')) {
          _fcmAvailable = false;
          return null;
        }
      } catch (e) {
        print("❌ Error getting FCM token on attempt ${i + 1}: $e");
      }

      if (i < maxRetries - 1) {
        final delay = Duration(seconds: (i + 1) * 2);
        print("Retrying token retrieval in ${delay.inSeconds} seconds...");
        await Future.delayed(delay);
      }
    }

    print("❌ Failed to retrieve FCM token after $maxRetries retries.");
    _fcmAvailable = false;
    return null;
  }

  Future<void> _clearLocalTokenData() async {
    await _storage.delete(key: 'fcm_token');
    await _storage.delete(key: 'fcm_registered');
    print("🗑️ Local FCM token data cleared.");
  }

  Future<bool> _sendTokenToServer(
    String token,
    String userId,
    String role,
  ) async {
    try {
      final payload = {
        'userId': userId,
        'fcmToken': token,
        'role': role,
        'platform':
            Platform.isAndroid
                ? 'android'
                : (Platform.isIOS ? 'ios' : 'unknown'),
        'is_emulator': _isEmulator,
        'fcm_available': _fcmAvailable,
      };
      print("📤 Sending FCM token to server: $payload");

      final response = await http
          .post(
            Uri.parse('$_baseUrl/fcm-token'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        print(
          "✅ FCM token successfully sent to backend. Response: ${response.body}",
        );
        return true;
      } else {
        print(
          "❌ Failed to send FCM token to backend. Status: ${response.statusCode}, Body: ${response.body}",
        );
        return false;
      }
    } catch (e) {
      print("❌ Error sending FCM token to server: $e");
      return false;
    }
  }

  // Debugging methods (keep as is)
  Future<Map<String, String>> getStatus() async {
    final Map<String, String> status = {};
    try {
      final NotificationSettings settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      status['authorizationStatus'] = settings.authorizationStatus.toString();
      status['alert'] = settings.alert.toString();
      status['badge'] = settings.badge.toString();
      status['sound'] = settings.sound.toString();
      status['fcm_token'] = await _storage.read(key: 'fcm_token') ?? 'N/A';
      status['is_emulator'] = _isEmulator.toString();
      status['fcm_available'] = _fcmAvailable.toString();
    } catch (e) {
      status['error_get_status'] = e.toString();
    }
    return status;
  }

  Future<void> _detectEmulator() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final props = await getDeviceProperties();
        _isEmulator =
            props.containsKey('ro.build.characteristics') &&
            (props['ro.build.characteristics']!.contains('emulator') ||
                props['ro.build.characteristics']!.contains('goldfish'));
        print("Emulator detected: $_isEmulator");
      } catch (e) {
        print("Error detecting emulator: $e");
        _isEmulator = false;
      }
    } else {
      _isEmulator = false; // Assume not emulator for other platforms
    }
  }

  Future<Map<String, String>> getDeviceProperties() async {
    final Map<String, String> properties = {};
    if (Platform.isAndroid) {
      final List<String> checks = [
        'ro.build.characteristics',
        'ro.product.model',
        'ro.product.brand',
        'ro.product.manufacturer',
        'ro.product.cpu.abi',
        'ro.build.version.release',
        'ro.build.version.sdk',
      ];

      for (final prop in checks) {
        try {
          final result = await Process.run('getprop', [prop]);
          properties[prop] = result.stdout.toString().trim();
        } catch (e) {
          properties[prop] = 'ERROR: $e';
        }
      }
    } else {
      properties['platform'] = 'Not Android';
    }
    return properties;
  }

  Future<void> debugFCMStatus() async {
    print("\n--- FCM Debug Status ---");
    print("Device Properties:");
    final props = await getDeviceProperties();
    props.forEach((key, value) {
      print('  $key: $value');
    });

    print("\nFCM Status Summary:");
    final status = await getStatus();
    status.forEach((key, value) {
      print(
        '  $key: ${value.toString().substring(0, value.toString().length > 100 ? 100 : value.toString().length)}',
      ); // Handle long tokens
    });

    if (_fcmAvailable) {
      try {
        final token = await FirebaseMessaging.instance.getToken().timeout(
          const Duration(seconds: 10),
        );
        print('  Current FCM Token: $token');
      } catch (e) {
        print('  Failed to get current FCM token: $e');
      }
    }
    print("--- End FCM Debug Status ---\n");
  }

  void dispose() {
    _messageStreamController.close();
    _retryTimer?.cancel();
  }
}
