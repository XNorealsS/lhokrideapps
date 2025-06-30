// firebase_service.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

class FirebaseService {
  static FirebaseDatabase? _database;
  static bool _initialized = false;
  static final Map<String, StreamSubscription> _activeListeners = {};

  // Initialize Firebase Database
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
      _database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://lhokrideplus-548c0-default-rtdb.asia-southeast1.firebasedatabase.app',
      );

      // Enable offline persistence
      _database!.setPersistenceEnabled(true);
      _initialized = true;

      print('Firebase initialized successfully');
    } catch (e) {
      print('Firebase initialization error: $e');
      throw e;
    }
  }

  // New method to get ride details
  static Future<Map<String, dynamic>?> getRideDetails(String rideId) async {
    if (!_initialized || _database == null) return null;
    try {
      final rideRef = _database!.ref('rides/$rideId');
      final DataSnapshot snapshot = await rideRef.get();
      if (snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      print('Error fetching ride details: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getFoodOrderDetails(
    String orderId,
  ) async {
    if (!_initialized || _database == null) return null;
    try {
      final orderRef = _database!.ref('food_orders/$orderId');
      final DataSnapshot snapshot = await orderRef.get();
      if (snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      print('Error fetching food order details: $e');
      return null;
    }
  }

 static Future<void> debugCheckDatabase(String driverId) async {
    print("🔍 === DEBUG DATABASE CHECK ===");
    print("🔍 Checking for driver: $driverId");
    
    try {
      // Check rides
      final ridesSnapshot = await getDatabaseRef()
          .child('rides')
          .orderByChild('status')
          .equalTo('pending')
          .once();
      
      if (ridesSnapshot.snapshot.value != null) {
        final ridesData = Map<dynamic, dynamic>.from(
            ridesSnapshot.snapshot.value as Map);
        print("🔍 Found ${ridesData.length} pending rides");
        
        for (final entry in ridesData.entries) {
          final rideId = entry.key.toString();
          final rideData = Map<String, dynamic>.from(entry.value as Map);
          print("🔍 Ride $rideId: currentDriverAttempt=${rideData['currentDriverAttempt']}, status=${rideData['status']}");
        }
      } else {
        print("🔍 No pending rides found");
      }
      
      // Check food orders
      final ordersSnapshot = await getDatabaseRef()
          .child('food_orders')
          .orderByChild('status')
          .equalTo('pending')
          .once();
      
      if (ordersSnapshot.snapshot.value != null) {
        final ordersData = Map<dynamic, dynamic>.from(
            ordersSnapshot.snapshot.value as Map);
        print("🔍 Found ${ordersData.length} pending food orders");
        
        for (final entry in ordersData.entries) {
          final orderId = entry.key.toString();
          final orderData = Map<String, dynamic>.from(entry.value as Map);
          print("🔍 Order $orderId: currentDriverAttempt=${orderData['currentDriverAttempt']}, status=${orderData['status']}");
        }
      } else {
        print("🔍 No pending food orders found");
      }
      
    } catch (e) {
      print("🔍 ❌ Error checking database: $e");
    }
    
    print("🔍 === END DEBUG CHECK ===");
  }


  // OPTIMIZED: Listen to food order status with better error handling and real-time updates
  static StreamSubscription<DatabaseEvent>? listenToFoodStatus(
    String orderId,
    Function(Map<String, dynamic>) onStatusChange,
  ) {
    if (!_initialized || _database == null) return null;

    // Cancel existing listener for this order if any
    _cancelListener('food_status_$orderId');

    try {
      final orderRef = _database!.ref('food_orders/$orderId');
      final subscription = orderRef.onValue.listen(
        (DatabaseEvent event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final orderData = Map<String, dynamic>.from(data);
            // Always call callback with latest data for real-time updates
            print('📦 Food order $orderId updated: ${orderData['status']}');
            onStatusChange(orderData);
          } else {
            print('📦 Food order $orderId: No data found');
          }
        },
        onError: (error) {
          print('❌ Error listening to food order $orderId: $error');
          // Attempt to reconnect after error
          Timer(Duration(seconds: 3), () {
            listenToFoodStatus(orderId, onStatusChange);
          });
        },
      );

      // Store listener reference
      _activeListeners['food_status_$orderId'] = subscription;
      return subscription;
    } catch (e) {
      print('❌ Error setting up listener for food status: $e');
      return null;
    }
  }

  // OPTIMIZED: Listen to ride status with better error handling and real-time updates
  static StreamSubscription<DatabaseEvent>? listenToRideStatus(
    String rideId,
    Function(Map<String, dynamic>) onStatusChange,
  ) {
    if (!_initialized || _database == null) return null;

    // Cancel existing listener for this ride if any
    _cancelListener('ride_status_$rideId');

    try {
      final rideRef = _database!.ref('rides/$rideId');
      final subscription = rideRef.onValue.listen(
        (DatabaseEvent event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final rideData = Map<String, dynamic>.from(data);
            // Always call callback with latest data for real-time updates
            print('🚗 Ride $rideId updated: ${rideData['status']}');
            onStatusChange(rideData);
          } else {
            print('🚗 Ride $rideId: No data found');
          }
        },
        onError: (error) {
          print('❌ Error listening to ride $rideId: $error');
          // Attempt to reconnect after error
          Timer(Duration(seconds: 3), () {
            listenToRideStatus(rideId, onStatusChange);
          });
        },
      );

      // Store listener reference
      _activeListeners['ride_status_$rideId'] = subscription;
      return subscription;
    } catch (e) {
      print('❌ Error setting up listener for ride status: $e');
      return null;
    }
  }

  // OPTIMIZED: Listen for active rides with real-time filtering
  static StreamSubscription<DatabaseEvent>? listenForActiveRides(
    Function(List<Map<String, dynamic>>) onRideReceived,
  ) {
    if (!_initialized || _database == null) return null;

    // Cancel existing listener
    _cancelListener('active_rides');

    try {
      final ridesRef = _database!.ref('rides');
      final subscription = ridesRef.onValue.listen(
        (DatabaseEvent event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final allRides = Map<String, dynamic>.from(data);
            final activeRides = <Map<String, dynamic>>[];

            allRides.forEach((rideId, rideData) {
              if (rideData is Map) {
                final ride = Map<String, dynamic>.from(rideData);
                // Include multiple active statuses for better filtering
                if ([
                  'requested',
                  'accepted',
                  'driver_arrived',
                  'in_progress',
                ].contains(ride['status'])) {
                  ride['rideId'] = rideId; // Ensure rideId is included
                  activeRides.add(ride);
                }
              }
            });

            // Sort by creation time (most recent first)
            activeRides.sort((a, b) {
              final aTime = a['createdAt'] ?? 0;
              final bTime = b['createdAt'] ?? 0;
              return bTime.compareTo(aTime);
            });

            print('📍 Active rides updated: ${activeRides.length} rides');
            onRideReceived(activeRides);
          } else {
            onRideReceived([]);
          }
        },
        onError: (error) {
          print('❌ Error listening for active rides: $error');
          // Attempt to reconnect after error
          Timer(Duration(seconds: 3), () {
            listenForActiveRides(onRideReceived);
          });
        },
      );

      // Store listener reference
      _activeListeners['active_rides'] = subscription;
      return subscription;
    } catch (e) {
      print('❌ Error setting up active rides listener: $e');
      return null;
    }
  }

  // OPTIMIZED: Listen for new ride requests with better filtering
  static StreamSubscription<DatabaseEvent>? listenForNewRideRequests(
    String driverId,
    Function(Map<String, dynamic>) onNewRideRequest,
  ) {
    if (!_initialized || _database == null) return null;

    // Cancel existing listener
    _cancelListener('new_ride_requests_$driverId');

    try {
      final ridesRef = _database!.ref('rides');
      final subscription = ridesRef.onChildAdded.listen(
        (DatabaseEvent event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final rideData = Map<String, dynamic>.from(data);
            rideData['rideId'] = event.snapshot.key; // Add rideId from key

            // Check if this is a new ride request without driver assigned
            if (rideData['status'] == 'requested' &&
                (rideData['driverId'] == null ||
                    rideData['driverId'] == '' ||
                    rideData['driverId'] == driverId)) {
              // Check if ride is recent (within last 5 minutes to avoid old rides)
              final createdAt = rideData['createdAt'] ?? 0;
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - createdAt < 300000) {
                // 5 minutes
                print('🚗 New ride request detected: ${rideData['rideId']}');
                onNewRideRequest(rideData);
              }
            }
          }
        },
        onError: (error) {
          print('❌ Error listening for new ride requests: $error');
          // Attempt to reconnect after error
          Timer(Duration(seconds: 3), () {
            listenForNewRideRequests(driverId, onNewRideRequest);
          });
        },
      );

      // Store listener reference
      _activeListeners['new_ride_requests_$driverId'] = subscription;
      return subscription;
    } catch (e) {
      print('❌ Error setting up new ride requests listener: $e');
      return null;
    }
  }

  // OPTIMIZED: Get order details with better error handling
  Future<Map<String, dynamic>?> getOrderDetails(String orderId) async {
    if (!_initialized || _database == null) return null;
    try {
      final orderRef = _database!.ref('orders/$orderId');
      final DataSnapshot snapshot = await orderRef.get();
      if (snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      print('Error getting order details for $orderId: $e');
      return null;
    }
  }

  // OPTIMIZED: Listen for new food order requests with better filtering
  static StreamSubscription<DatabaseEvent>? listenForNewFoodOrderRequests(
    String driverId,
    Function(Map<String, dynamic>) onNewFoodOrder,
  ) {
    if (!_initialized || _database == null) return null;

    // Cancel existing listener
    _cancelListener('new_food_orders_$driverId');

    try {
      final foodOrdersRef = _database!.ref('food_orders');
      final subscription = foodOrdersRef.onChildAdded.listen(
        (DatabaseEvent event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final orderData = Map<String, dynamic>.from(data);
            orderData['orderId'] = event.snapshot.key; // Add orderId from key

            // Check if this is a new food order without driver assigned
            if (orderData['status'] == 'pending' &&
                (orderData['driverId'] == null ||
                    orderData['driverId'] == '' ||
                    orderData['driverId'] == driverId)) {
              // Check if order is recent (within last 5 minutes to avoid old orders)
              final createdAt = orderData['createdAt'] ?? 0;
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - createdAt < 300000) {
                // 5 minutes
                print('🍔 New food order detected: ${orderData['orderId']}');
                onNewFoodOrder(orderData);
              }
            }
          }
        },
        onError: (error) {
          print('❌ Error listening for new food orders: $error');
          // Attempt to reconnect after error
          Timer(Duration(seconds: 3), () {
            listenForNewFoodOrderRequests(driverId, onNewFoodOrder);
          });
        },
      );

      // Store listener reference
      _activeListeners['new_food_orders_$driverId'] = subscription;
      return subscription;
    } catch (e) {
      print('❌ Error setting up new food orders listener: $e');
      return null;
    }
  }

  // OPTIMIZED: Listen for active food orders
  static StreamSubscription<DatabaseEvent>? listenForActiveFoodOrders(
    Function(List<Map<String, dynamic>>) onOrdersReceived,
  ) {
    if (!_initialized || _database == null) return null;

    // Cancel existing listener
    _cancelListener('active_food_orders');

    try {
      final ordersRef = _database!.ref('food_orders');
      final subscription = ordersRef.onValue.listen(
        (DatabaseEvent event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final allOrders = Map<String, dynamic>.from(data);
            final activeOrders = <Map<String, dynamic>>[];

            allOrders.forEach((orderId, orderData) {
              if (orderData is Map) {
                final order = Map<String, dynamic>.from(orderData);
                // Include multiple active statuses for better filtering
                if ([
                  'pending',
                  'accepted',
                  'preparing',
                  'ready',
                  'picked_up',
                  'in_delivery',
                ].contains(order['status'])) {
                  order['orderId'] = orderId; // Ensure orderId is included
                  activeOrders.add(order);
                }
              }
            });

            // Sort by creation time (most recent first)
            activeOrders.sort((a, b) {
              final aTime = a['createdAt'] ?? 0;
              final bTime = b['createdAt'] ?? 0;
              return bTime.compareTo(aTime);
            });

            print(
              '🍔 Active food orders updated: ${activeOrders.length} orders',
            );
            onOrdersReceived(activeOrders);
          } else {
            onOrdersReceived([]);
          }
        },
        onError: (error) {
          print('❌ Error listening for active food orders: $error');
          // Attempt to reconnect after error
          Timer(Duration(seconds: 3), () {
            listenForActiveFoodOrders(onOrdersReceived);
          });
        },
      );

      // Store listener reference
      _activeListeners['active_food_orders'] = subscription;
      return subscription;
    } catch (e) {
      print('❌ Error setting up active food orders listener: $e');
      return null;
    }
  }

  // OPTIMIZED: Listen to driver location updates
  static StreamSubscription<DatabaseEvent>? listenToDriverLocation(
    String driverId,
    Function(Map<String, dynamic>) onLocationUpdate,
  ) {
    if (!_initialized || _database == null) return null;

    // Cancel existing listener
    _cancelListener('driver_location_$driverId');

    try {
      final locationRef = _database!.ref('drivers/$driverId/Location');
      final subscription = locationRef.onValue.listen(
        (DatabaseEvent event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final locationData = Map<String, dynamic>.from(data);
            print('📍 Driver $driverId location updated');
            onLocationUpdate(locationData);
          }
        },
        onError: (error) {
          print('❌ Error listening to driver location: $error');
          // Attempt to reconnect after error
          Timer(Duration(seconds: 3), () {
            listenToDriverLocation(driverId, onLocationUpdate);
          });
        },
      );

      // Store listener reference
      _activeListeners['driver_location_$driverId'] = subscription;
      return subscription;
    } catch (e) {
      print('❌ Error setting up driver location listener: $e');
      return null;
    }
  }

  // OPTIMIZED: Listen to driver status updates
  static StreamSubscription<DatabaseEvent>? listenToDriverStatus(
    String driverId,
    Function(Map<String, dynamic>) onStatusUpdate,
  ) {
    if (!_initialized || _database == null) return null;

    // Cancel existing listener
    _cancelListener('driver_status_$driverId');

    try {
      final statusRef = _database!.ref('drivers/$driverId/status');
      final subscription = statusRef.onValue.listen(
        (DatabaseEvent event) {
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final statusData = Map<String, dynamic>.from(data);
            print(
              '👤 Driver $driverId status updated: ${statusData['isOnline']}',
            );
            onStatusUpdate(statusData);
          }
        },
        onError: (error) {
          print('❌ Error listening to driver status: $error');
          // Attempt to reconnect after error
          Timer(Duration(seconds: 3), () {
            listenToDriverStatus(driverId, onStatusUpdate);
          });
        },
      );

      // Store listener reference
      _activeListeners['driver_status_$driverId'] = subscription;
      return subscription;
    } catch (e) {
      print('❌ Error setting up driver status listener: $e');
      return null;
    }
  }

  // Helper method to cancel specific listener
  static void _cancelListener(String listenerId) {
    if (_activeListeners.containsKey(listenerId)) {
      _activeListeners[listenerId]?.cancel();
      _activeListeners.remove(listenerId);
      print('🔄 Cancelled listener: $listenerId');
    }
  }

  // Cancel specific listener by ID (public method)
  static void cancelListener(String listenerId) {
    _cancelListener(listenerId);
  }

  // Cancel all listeners
  static void cancelAllListeners() {
    _activeListeners.forEach((key, subscription) {
      subscription.cancel();
    });
    _activeListeners.clear();
    print('🔄 All listeners cancelled');
  }

  // Update ride status - SUDAH BENAR, data selalu di rides/{rideId}
  static Future<void> updateRideStatus(
    String rideId,
    Map<String, dynamic> updates,
  ) async {
    if (!_initialized || _database == null) {
      throw Exception('Firebase not initialized');
    }

    try {
      final rideRef = _database!.ref('rides/$rideId');
      await rideRef.update({...updates, 'lastUpdated': ServerValue.timestamp});

      print('Ride status updated successfully: $updates');
    } catch (e) {
      print('Error updating ride: $e');
      throw e;
    }
  }

  // Create a new ride in Firebase - SUDAH BENAR
  static Future<void> createRide(
    String rideId,
    Map<String, dynamic> rideData,
  ) async {
    if (!_initialized || _database == null) {
      throw Exception('Firebase not initialized');
    }

    try {
      final rideRef = _database!.ref('rides/$rideId');
      await rideRef.set({
        ...rideData,
        'createdAt': ServerValue.timestamp,
        'lastUpdated': ServerValue.timestamp,
      });

      print('Ride created successfully: $rideId');
    } catch (e) {
      print('Error creating ride: $e');
      throw e;
    }
  }

  // OPTIMIZED: Update driver location with batch updates
  static Future<void> updateDriverLocation(
    String driverId,
    double lat,
    double lng,
  ) async {
    if (!_initialized || _database == null) return;

    try {
      await _database!.ref('drivers/$driverId/Location').set({
        'latitude': lat,
        'longitude': lng,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      print('Error updating driver location: $e');
    }
  }

  // Update driver status (online/offline)
  static Future<void> updateDriverStatus(String driverId, bool isOnline) async {
    if (!_initialized || _database == null) {
      throw Exception('Firebase not initialized');
    }

    try {
      final statusRef = _database!.ref('drivers/$driverId/status');
      await statusRef.set({
        'isOnline': isOnline,
        'updatedAt': ServerValue.timestamp,
      });

      print(
        'Driver status updated: $driverId -> ${isOnline ? "online" : "offline"}',
      );
    } catch (e) {
      print('Error updating driver status: $e');
      throw e;
    }
  }

  // Update food order status
  static Future<void> updateFoodOrderStatus(
    String orderId,
    Map<String, dynamic> updates,
  ) async {
    if (!_initialized || _database == null) {
      throw Exception('Firebase not initialized');
    }

    try {
      final orderRef = _database!.ref('food_orders/$orderId');
      await orderRef.update({...updates, 'lastUpdated': ServerValue.timestamp});
      print('Food order status updated successfully: $updates');
    } catch (e) {
      print('Error updating food order: $e');
      throw e;
    }
  }

  // ****************************** OPTIMIZED CHAT METHODS ******************************

  // Send a message
  static Future<void> sendMessage(
    String rideId,
    String senderId,
    String senderName,
    String message,
  ) async {
    if (!_initialized || _database == null) return;
    try {
      final newMessageRef = _database!.ref('rides/$rideId/messages').push();
      await newMessageRef.set({
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      print('Error sending message: $e');
      throw e;
    }
  }

  // OPTIMIZED: Listen to messages for a specific ride
  static StreamSubscription<DatabaseEvent> listenToMessages(
    String rideId,
    Function(List<Map<String, dynamic>>) onMessagesChanged,
  ) {
    if (!_initialized || _database == null) {
      throw Exception("Firebase not initialized");
    }

    // Cancel existing listener
    _cancelListener('messages_$rideId');

    final subscription = _database!
        .ref('rides/$rideId/messages')
        .orderByChild('timestamp')
        .onValue
        .listen(
          (event) {
            final List<Map<String, dynamic>> messages = [];
            if (event.snapshot.value != null) {
              final data = event.snapshot.value as Map<dynamic, dynamic>;
              data.forEach((key, value) {
                if (value is Map) {
                  final message = Map<String, dynamic>.from(value);
                  message['messageId'] = key; // Add message ID
                  messages.add(message);
                }
              });
            }
            // Sort messages by timestamp
            messages.sort(
              (a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0),
            );
            onMessagesChanged(messages);
          },
          onError: (error) {
            print("Error listening to messages: $error");
            onMessagesChanged([]); // Return empty list on error
            // Attempt to reconnect after error
            Timer(Duration(seconds: 3), () {
              listenToMessages(rideId, onMessagesChanged);
            });
          },
        );

    // Store listener reference
    _activeListeners['messages_$rideId'] = subscription;
    return subscription;
  }

  // Clean up resources
  static Future<void> dispose() async {
    try {
      // Cancel all active listeners
      cancelAllListeners();
      print('Firebase service disposed');
    } catch (e) {
      print('Error disposing Firebase service: $e');
    }
  }

  // Check connection status
  static Future<bool> isConnected() async {
    if (!_initialized || _database == null) {
      return false;
    }

    try {
      final connectedRef = _database!.ref('.info/connected');
      final snapshot = await connectedRef.get();
      return snapshot.value == true;
    } catch (e) {
      print('Error checking connection: $e');
      return false;
    }
  }

  static DatabaseReference getDatabaseRef() {
    if (_database == null) {
      throw Exception(
        "Firebase Database not initialized. Call FirebaseService.initialize() first.",
      );
    }
    return _database!.ref();
  }

  // OPTIMIZED: Listen for connection status changes
  static StreamSubscription<DatabaseEvent>? listenForConnectionChanges(
    Function(bool isConnected) onConnectionChanged,
  ) {
    if (!_initialized || _database == null) {
      return null;
    }

    // Cancel existing listener
    _cancelListener('connection_status');

    try {
      final connectedRef = _database!.ref('.info/connected');
      final subscription = connectedRef.onValue.listen(
        (DatabaseEvent event) {
          final isConnected = event.snapshot.value == true;
          print(
            '🌐 Connection status: ${isConnected ? "Connected" : "Disconnected"}',
          );
          onConnectionChanged(isConnected);
        },
        onError: (error) {
          print('Connection listener error: $error');
          onConnectionChanged(false);
        },
      );

      // Store listener reference
      _activeListeners['connection_status'] = subscription;
      return subscription;
    } catch (e) {
      print('Error setting up connection listener: $e');
      return null;
    }
  }

  // Get active listeners count (for debugging)
  static int getActiveListenersCount() {
    return _activeListeners.length;
  }

  // Get active listeners list (for debugging)
  static List<String> getActiveListenersList() {
    return _activeListeners.keys.toList();
  }
}
