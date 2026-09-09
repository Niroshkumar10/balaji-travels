# RedTaxi app (Flutter)

Single Flutter app, `com.redtaxi.redtaxi`. The user picks **Ride** or **Drive**
at login; the same phone number can hold both identities separately.

## Layout

```
app/lib/
  main.dart              boot: load Session, init push, ProviderScope
  app.dart               MaterialApp.router
  router.dart            go_router + auth/role redirect guard
  state/                 Riverpod: providers.dart, auth_controller.dart
  core/
    config/              AppConfig (all values from --dart-define)
    net/                 ApiClient (dio), ApiException, Result<T>
    auth/                Session (SharedPreferences)
    realtime/            SocketClient (socket_io_client, JWT handshake, reconnect)
    location/            LocationService (geolocator)
    push/                PushService (FCM + local notifications, no-op w/o Firebase)
    models/              typed models + fromJson (ride, fare, vehicle, profiles, …)
    repos/               auth / profile / ride / payment / misc repositories
    theme/               AppColors, AppTheme (M3, light+dark)
    widgets/             PrimaryButton, MapView, OtpInput, RatingStars, …
  features/
    splash/ onboarding/ auth/ permission/
    customer/  home  ride_request  tracking  payment  rating  history
               offers  saved_places  profile  support  notifications
               ride_session_controller.dart   (live ride state + socket)
    driver/    setup  dashboard  offer  ride  earnings  history  profile  notifications
               driver_controller.dart         (presence + job + location stream)
    shared/    notifications_list.dart
```

State: **Riverpod**. Routing: **go_router** with a redirect that sends an
authenticated `customer` to `/c/home` and `driver` to `/d/dashboard`, and blocks
cross-role routes.

## Run (dev)

Backend must be running first (see `server/`). Then:

```bash
cd app
flutter pub get
flutter run \
  --dart-define=RT_API_BASE_URL=http://10.0.2.2:4000 \
  --dart-define=RT_SOCKET_URL=http://10.0.2.2:4000
```

`10.0.2.2` = the Android emulator's alias for your host machine. Use your LAN IP
for a physical device.

## Native config

- **Maps key** — put `MAPS_API_KEY=AIza...` in `app/android/local.properties`
  (git-ignored). `build.gradle.kts` injects it as the manifest placeholder. On
  iOS, set it in `AppDelegate` / an xcconfig. Restrict the key by package + SHA.
- **Push** — drop `google-services.json` in `android/app/`, add the
  `com.google.gms.google-services` plugin (steps are commented in
  `build.gradle.kts`), and `GoogleService-Info.plist` on iOS. Without these the
  app still builds and runs; push is just disabled.
- **Permissions** are declared in `AndroidManifest.xml` / `Info.plist`
  (fine + background location, foreground service, notifications).

## Status

`flutter analyze` → clean. Screens for all Phase 2–9 flows are wired to the
backend REST + Socket.IO contract in `docs/BACKEND.md`. Not yet exercised
end-to-end against a live DB — that's Phase 10.
