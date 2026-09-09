import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/session.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/auth/role_pick_screen.dart';
import 'features/customer/history/ride_detail_screen.dart';
import 'features/customer/history/ride_history_screen.dart';
import 'features/customer/home/customer_home_screen.dart';
import 'features/customer/notifications/notifications_screen.dart';
import 'features/customer/offers/offers_screen.dart';
import 'features/customer/payment/payment_screen.dart';
import 'features/customer/profile/customer_profile_screen.dart';
import 'features/customer/rating/rating_screen.dart';
import 'features/customer/ride_request/where_to_screen.dart';
import 'features/customer/saved_places/saved_places_screen.dart';
import 'features/customer/support/support_screen.dart';
import 'features/customer/tracking/ride_tracking_screen.dart';
import 'features/driver/driver_shell.dart';
import 'features/driver/earnings/wallet_screen.dart';
import 'features/driver/notifications/driver_notifications_screen.dart';
import 'features/driver/offer/ride_offer_screen.dart';
import 'features/driver/ride/driver_ride_screen.dart';
import 'features/driver/setup/driver_setup_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/permission/location_permission_screen.dart';
import 'features/splash/splash_screen.dart';
import 'state/auth_controller.dart';
import 'state/providers.dart';

/// Bridges the AuthController status stream into a Listenable GoRouter can watch.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthStatus> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final dynamic _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

const _authRoutes = {'/splash', '/onboarding', '/role', '/login', '/otp'};

final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authControllerProvider.notifier);
  final refresh = _AuthRefresh(auth.statusStream);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, gstate) {
      final st = ref.read(authControllerProvider);
      final loc = gstate.matchedLocation;

      if (st.status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }

      final onAuthRoute = _authRoutes.contains(loc);

      if (st.status == AuthStatus.unauthenticated) {
        // allow the pre-login funnel; anything else → role picker
        if (loc == '/onboarding' || loc == '/role' || loc == '/login' || loc == '/otp') {
          return null;
        }
        return '/role';
      }

      // authenticated
      final home = st.role == AppRole.driver ? '/d/dashboard' : '/c/home';
      if (onAuthRoute) return home;
      // keep customers out of /d/* and vice-versa
      if (st.role == AppRole.driver && loc.startsWith('/c/')) return home;
      if (st.role == AppRole.customer && loc.startsWith('/d/')) return home;
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/role', builder: (_, __) => const RolePickScreen()),
      GoRoute(
        path: '/login',
        builder: (_, s) => LoginScreen(role: _roleFromExtra(s.extra)),
      ),
      GoRoute(
        path: '/otp',
        builder: (_, s) {
          final m = s.extra as Map<String, dynamic>? ?? const {};
          return OtpScreen(
            mobile: m['mobile'] as String? ?? '',
            role: m['role'] as AppRole? ?? AppRole.customer,
            devCode: m['devCode'] as String?,
          );
        },
      ),
      GoRoute(path: '/permission', builder: (_, __) => const LocationPermissionScreen()),

      // ── customer ──
      GoRoute(path: '/c/home', builder: (_, __) => const CustomerHomeScreen()),
      GoRoute(path: '/c/where-to', builder: (_, __) => const WhereToScreen()),
      GoRoute(
        path: '/c/ride/:id',
        builder: (_, s) => RideTrackingScreen(rideId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/c/pay/:id',
        builder: (_, s) => PaymentScreen(rideId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/c/rate/:id',
        builder: (_, s) => RatingScreen(rideId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(path: '/c/history', builder: (_, __) => const RideHistoryScreen()),
      GoRoute(
        path: '/c/ride-detail/:id',
        builder: (_, s) => RideDetailScreen(rideId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(path: '/c/offers', builder: (_, __) => const OffersScreen()),
      GoRoute(path: '/c/saved-places', builder: (_, __) => const SavedPlacesScreen()),
      GoRoute(path: '/c/profile', builder: (_, __) => const CustomerProfileScreen()),
      GoRoute(path: '/c/support', builder: (_, __) => const SupportScreen()),
      GoRoute(path: '/c/notifications', builder: (_, __) => const NotificationsScreen()),

      // ── driver ──
      GoRoute(path: '/d/setup', builder: (_, __) => const DriverSetupScreen()),
      GoRoute(path: '/d/dashboard', builder: (_, __) => const DriverShell()),
      GoRoute(path: '/d/earnings', builder: (_, __) => const DriverShell(initialTab: 1)),
      GoRoute(path: '/d/history', builder: (_, __) => const DriverShell(initialTab: 2)),
      GoRoute(path: '/d/profile', builder: (_, __) => const DriverShell(initialTab: 3)),
      GoRoute(
        path: '/d/offer/:id',
        builder: (_, s) => RideOfferScreen(rideId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/d/ride/:id',
        builder: (_, s) => DriverRideScreen(rideId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(path: '/d/wallet', builder: (_, __) => const WalletScreen()),
      GoRoute(path: '/d/notifications', builder: (_, __) => const DriverNotificationsScreen()),
    ],
  );
});

AppRole _roleFromExtra(Object? extra) =>
    extra is AppRole ? extra : AppRole.customer;
