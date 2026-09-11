import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import '../core/location/location_service.dart';
import '../core/net/api_client.dart';
import '../core/realtime/socket_client.dart';
import '../core/repos/auth_repository.dart';
import '../core/repos/misc_repository.dart';
import '../core/repos/payment_repository.dart';
import '../core/repos/profile_repository.dart';
import '../core/repos/ride_repository.dart';
import 'auth_controller.dart';

// Explicit types on every provider: apiClient → authController → authRepo →
// apiClient forms a lazy runtime cycle (the 401 callback), which Dart can't
// type-infer through, so we annotate to break it.

/// Overridden in main() with the instance loaded before runApp().
final Provider<Session> sessionProvider = Provider<Session>(
  (_) => throw StateError('sessionProvider must be overridden'),
);

final Provider<SocketClient> socketClientProvider = Provider<SocketClient>((ref) {
  final c = SocketClient()
    // Handshake refused for an auth reason (token superseded / expired) →
    // reconnecting can't help, so drop the session and send the user to login.
    // Same lazy apiClient↔authController cycle as `onUnauthorized` above.
    ..onAuthFailure = () => ref.read(authControllerProvider.notifier).forceLogout();
  ref.onDispose(c.dispose);
  return c;
});

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(sessionProvider),
    onUnauthorized: () => ref.read(authControllerProvider.notifier).forceLogout(),
  );
});

final Provider<AuthRepository> authRepoProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiClientProvider)));
final Provider<ProfileRepository> profileRepoProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(apiClientProvider)));
final Provider<RideRepository> rideRepoProvider =
    Provider<RideRepository>((ref) => RideRepository(ref.watch(apiClientProvider)));
final Provider<PaymentRepository> paymentRepoProvider =
    Provider<PaymentRepository>((ref) => PaymentRepository(ref.watch(apiClientProvider)));
final Provider<MiscRepository> miscRepoProvider =
    Provider<MiscRepository>((ref) => MiscRepository(ref.watch(apiClientProvider)));

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((_) => LocationService());

final StateNotifierProvider<AuthController, AuthState> authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    session: ref.watch(sessionProvider),
    authRepo: ref.watch(authRepoProvider),
    socket: ref.watch(socketClientProvider),
    ref: ref,
  );
});
