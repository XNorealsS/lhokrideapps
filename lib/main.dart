// main.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart'; // Though not directly used for FCM, keep if needed elsewhere
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lhokride/app_router.dart'; // Assuming this defines your GoRouter instance
import 'package:lhokride/services/fcm_listener.dart'; // Your FCMService
import 'package:go_router/go_router.dart';

import 'package:lhokride/models/partner.dart'; // Keep if you use Hive for these models
import 'package:lhokride/models/menu.dart'; // Keep if you use Hive for these models

// Hive imports
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'firebase_options.dart';

// Global router instance - must be initialized
late GoRouter appRouter;

// Handler when a local notification (displayed by flutter_local_notifications) is tapped
@pragma('vm:entry-point')
void onDidReceiveNotificationResponse(
  NotificationResponse notificationResponse,
) {
  final payload = notificationResponse.payload;
  if (payload != null) {
    // Decode the payload to get the original data sent from FCM
    final Map<String, dynamic> data = jsonDecode(payload);
    _handleNotificationNavigation(data);
  }
}

// Handler for background FCM messages (when app is in background or terminated)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for background processes
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
  print('Background message data: ${message.data}');

  // If the message contains a 'notification' payload, display it using local notifications
  // This is crucial for showing notifications when the app is in the background/terminated.
  if (message.notification != null) {
    FCMService.instance.showNotification(
      message.notification!.title,
      message.notification!.body,
      jsonEncode(message.data), // Pass message.data as payload for navigation
    );
  }
  // If it's a data-only message in the background, you could process message.data here
  // without necessarily showing a visible notification.
}

void _handleNotificationNavigation(Map<String, dynamic> data) {
  final type = data['type'];
  final rideId = data['rideId'];
  final orderId = data['orderId'];

  // Navigate based on the 'type' field in the notification data
  if (type == 'ride_request' && rideId != null) {
    appRouter.go('/ride_request/$rideId');
  } else if (type == 'ride_accepted' && rideId != null) {
    appRouter.go('/on-ride-tracking/$rideId');
  } else if (type == 'ride_cancelled' && rideId != null) {
    appRouter.go('/ride-cancelled/$rideId');
  } else if (type == 'ride_completed' && rideId != null) {
    appRouter.go('/ride-completed/$rideId');
  } else if (type == 'food_order' && orderId != null) {
    appRouter.go('/new-order-request/$orderId');
  } else {
    // Default navigation if type is unknown or missing
    appRouter.go('/dashboard');
  }
}

void main() async {
  // Ensure all Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Hive (for local data storage)
  Directory appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);

  // Register Hive Adapters for your models
  // Ensure PartnerAdapter and MenuAdapter classes exist and are correctly generated
  Hive.registerAdapter(PartnerAdapter());
  Hive.registerAdapter(MenuAdapter());

  // Open Hive boxes
  await Hive.openBox<Partner>('partnersBox');
  await Hive.openBox('appMetadata');

  print("✅ Hive initialized and boxes opened.");

  // Initialize GoRouter
  // 'router' should be the GoRouter instance defined in your app_router.dart
  appRouter = router;

  // Initialize FCM service and set up foreground message handling
  await FCMService.instance.initialize();

  // Set the background message handler for Firebase Messaging
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Set preferred screen orientation
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) => runApp(const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  DateTime? _lastPressedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Handle initial message (if app was opened by tapping a notification
    // from a terminated state)
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        print('App opened from terminated state by tapping notification!');
        print('Initial message data: ${message.data}');
        // Delay to ensure router is ready if app is launching
        Future.delayed(const Duration(milliseconds: 500), () {
          _handleNotificationNavigation(message.data);
        });
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📩 [FOREGROUND] Notifikasi diterima:');
      print('Title: ${message.notification?.title}');
      print('Body: ${message.notification?.body}');
      print('Data: ${message.data}');

      // Tampilkan notifikasi lokal agar muncul pop-up saat foreground
      if (message.notification != null) {
        FCMService.instance.showNotification(
          message.notification!.title,
          message.notification!.body,
          jsonEncode(message.data),
        );
      }
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        print('📲 [TERMINATED TAP NOTIF]');
        print('Data: ${message.data}');
      }
    });

    // Handle messages when the app is in the background/terminated and opened by tapping the notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('App opened from background/terminated by tapping notification!');
      print('Message data: ${message.data}');
      _handleNotificationNavigation(message.data);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // You can add data synchronization or other logic when app resumes
      print('App resumed from background.');
    }
  }

  // Double-tap back button to exit app
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    const duration = Duration(seconds: 2);
    final isWarning =
        _lastPressedAt == null || now.difference(_lastPressedAt!) > duration;

    if (isWarning) {
      _lastPressedAt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tekan sekali lagi untuk keluar'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
      return false; // Prevent pop
    }
    SystemNavigator.pop(); // Exit app
    return true; // Allow pop (will exit)
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent default back button behavior
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await _onWillPop();
        }
      },
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'LhokRide+',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          // Define other theme properties here
        ),
        routerConfig: appRouter, // Assign the GoRouter instance?
      ),
    );
  }
}
