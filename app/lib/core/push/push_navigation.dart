import '../auth/session.dart';

/// Maps a push notification's `data` payload (see every
/// `notifyService.notify({ type, data: { rideId } })` call server-side) to
/// the in-app route it should open on tap.
///
/// Kept as a pure function (data + current role in, a path or null out) so
/// it's independent of navigation/widget plumbing — [PushService] and
/// `main.dart` only need to call [router.push] with whatever this returns.
///
/// Returns null when the type is unroutable (unknown, or missing rideId) —
/// the caller should just leave the app where it already is rather than
/// guessing a destination.
String? routeForNotification(Map<String, dynamic> data, AppRole? role) {
  final type = data['type']?.toString();
  final rideId = data['rideId']?.toString();
  if (type == null) return null;

  switch (type) {
    // Driver-only — dispatch sends this straight to the driver's socket/push,
    // never the customer.
    case 'ride_offer':
      return rideId == null ? null : '/d/offer/$rideId';

    // Sent once a driver is confirmed on the ride — 'ride_assigned' for an
    // admin-panel booking (no offer/accept step of its own), 'ride_confirmed'
    // right after the driver accepts a normal dispatch offer.
    case 'ride_assigned':
    case 'ride_confirmed':
      return rideId == null ? null : '/d/ride/$rideId';

    // Customer-only — driver_assigned/no_drivers/driver_arrived/ride_started/
    // booking_accepted are only ever notified to the customer (see
    // dispatchService.js, rideService.js, adminBookingAnnouncer.js) — the
    // driver already has the ride open via ride:assigned/ride:status sockets,
    // no push needed there.
    case 'booking_accepted':
    case 'driver_assigned':
    case 'no_drivers':
    case 'driver_arrived':
    case 'ride_started':
      return rideId == null ? null : '/c/ride/$rideId';

    case 'payment_pending':
      return rideId == null ? null : '/c/pay/$rideId';

    // Sent to whichever side DIDN'T cause the cancellation — the ride is
    // gone by the time this arrives, so there's nothing to open; just get
    // that role back to their home/dashboard instead of a dead ride screen.
    case 'ride_cancelled':
      return role == AppRole.driver ? '/d/dashboard' : '/c/home';

    // Sent to both sides — route each to what they'd naturally do next.
    case 'ride_completed':
      if (rideId == null) return null;
      return role == AppRole.driver ? '/d/rate/$rideId' : '/c/rate/$rideId';

    default:
      return null;
  }
}
