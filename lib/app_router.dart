import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Auth Pages
import 'screens/auth/auth_page.dart';
import 'screens/auth/login_page.dart';
import 'screens/auth/login_otp_page.dart';
import 'screens/auth/register_page.dart';

// User Pages
import 'screens/profile_page.dart';

// Screens
import 'screens/auth_checker.dart';
import 'screens/dashboard_page.dart';
import 'screens/history_page.dart';
import 'screens/onboarding_page.dart';
import 'screens/terms_page.dart';

// Wrapper / Others
import 'widgets/splash_wrap.dart';

import 'screens/driver/driver_page.dart';
import 'screens/GeneralMaps/passanger_page.dart';
import 'screens/GeneralMaps/foodmaps_page.dart';
import 'screens/xpays/xpaystopup.dart';

// auth verif ststus
import 'screens/authveriv/blocked.dart';
import 'screens/authveriv/update.dart';

// FOOD
import 'package:lhokride/screens/Lhokfood/FoodDashboard.dart';
import 'package:lhokride/screens/Lhokfood/DetailsMerchant.dart';
import 'package:lhokride/screens/Lhokfood/foodProcessed.dart';
import 'package:lhokride/screens/Lhokfood/OrderTracking.dart';

// Models
import 'package:lhokride/models/partner.dart';
import 'package:lhokride/models/menu.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

final GoRouter router = GoRouter(
  // Remove navigatorKey to avoid conflicts with MaterialApp.router
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AuthChecker()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(path: '/auth', builder: (context, state) => const LandingPage()),
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardPage(),
    ),
    GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
    GoRoute(
      path: '/users/profile',
      builder: (context, state) => const ProfilePage(),
    ),
    GoRoute(
      path: '/terms',
      builder: (context, state) => const TermsAndConditionsPage(),
    ),

    // ============== RIDE =========
    GoRoute(
      path: '/Lhokride',
      builder: (context, state) => PassengerPage(mode: RideMode.ride),
    ),
    GoRoute(
      path: '/dashboard/driver',
      builder: (context, state) => DriverPage(),
    ),

    // ============== FOOD =========
    GoRoute(
      path: '/Lhokfood',
      builder: (context, state) => const LhokfoodPage(),
    ),

    GoRoute(
      path: '/partnerDetail',
      builder: (context, state) {
        final Partner partner = state.extra as Partner;
        return PartnerDetailPage(partner: partner);
      },
    ),
    GoRoute(
      path: '/delivery_map',
      name: 'delivery_map',
      builder: (context, state) {
        final Map<String, dynamic> args = state.extra as Map<String, dynamic>;
        final Partner partner = args['partner'] as Partner;
        final Map<Menu, int> cart = args['cart'] as Map<Menu, int>;
        final double totalPrice = args['totalPrice'] as double;
        return DeliveryMapPage(
          partner: partner,
          cart: cart,
          totalPrice: totalPrice,
        );
      },
    ),
    GoRoute(
      path: '/order_confirmation',
      name: 'order_confirmation',
      builder: (context, state) {
        // Retrieve all necessary arguments from state.extra
        final Map<String, dynamic> args = state.extra as Map<String, dynamic>;
        final Partner partner = args['partner'] as Partner;
        final Map<Menu, int> cart = args['cart'] as Map<Menu, int>;
        final double totalPrice = args['totalPrice'] as double;
        final LatLng deliveryLocation = args['deliveryLocation'] as LatLng;

        // New parameters from enhanced DeliveryMapPage
        final String? deliveryAddress = args['deliveryAddress'] as String?;
        final int deliveryFee = args['deliveryFee'] as int? ?? 0;
        final double? estimatedDistance = args['estimatedDistance'] as double?;
        final int? estimatedDuration = args['estimatedDuration'] as int?;

        return OrderConfirmationPage(
          partner: partner,
          cart: cart,
          totalPrice: totalPrice,
          deliveryLocation: deliveryLocation,
          deliveryAddress: deliveryAddress,
          deliveryFee: deliveryFee,
          estimatedDistance: estimatedDistance,
          estimatedDuration: estimatedDuration,
        );
      },
    ),

    GoRoute(
      path: '/order-tracking/:orderId', // Define the new route with parameter
      builder: (BuildContext context, GoRouterState state) {
        final orderId = state.pathParameters['orderId']!;
        return OrderTrackingPage(orderId: orderId);
      },
    ),

    // ========== TOPUP ==========
    GoRoute(path: '/xpaytopup', builder: (context, state) => TopUpPage()),

    // ========= AUTH ========
    GoRoute(path: '/blocked', builder: (context, state) => BlockedScreen()),
    GoRoute(
      path: '/login-otp',
      builder: (context, state) {
        final phone = state.extra as String;
        return LoginOTPPage(phone: phone);
      },
    ),
  ],
);
