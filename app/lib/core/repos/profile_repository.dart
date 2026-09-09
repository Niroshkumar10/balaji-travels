import '../models/models.dart';
import '../net/api_client.dart';
import '../net/result.dart';

class ProfileRepository {
  ProfileRepository(this._api);
  final ApiClient _api;

  Future<Result<CustomerProfile>> getCustomer() async {
    final res = await _api.get('/customers/me');
    return res.when<Result<CustomerProfile>>(
      ok: (j) => Ok(CustomerProfile.fromProfileJson(asMap(j['profile']))),
      err: (e) => Err(e),
    );
  }

  Future<Result<CustomerProfile>> updateCustomer(Map<String, dynamic> patch) async {
    final res = await _api.patch('/customers/me', body: patch);
    return res.when<Result<CustomerProfile>>(
      ok: (j) => Ok(CustomerProfile.fromProfileJson(asMap(j['profile']))),
      err: (e) => Err(e),
    );
  }

  Future<Result<DriverProfile>> getDriver() async {
    final res = await _api.get('/drivers/me');
    return res.when<Result<DriverProfile>>(
      ok: (j) => Ok(DriverProfile.fromProfileJson(asMap(j['profile']))),
      err: (e) => Err(e),
    );
  }

  Future<Result<DriverProfile>> updateDriver(Map<String, dynamic> patch) async {
    final res = await _api.patch('/drivers/me', body: patch);
    return res.when<Result<DriverProfile>>(
      ok: (j) => Ok(DriverProfile.fromProfileJson(asMap(j['profile']))),
      err: (e) => Err(e),
    );
  }

  Future<Result<Vehicle>> addVehicle(Map<String, dynamic> body) async {
    final res = await _api.post('/drivers/me/vehicle', body: body);
    return res.when<Result<Vehicle>>(
      ok: (j) => Ok(Vehicle.fromJson(asMap(j['vehicle']))),
      err: (e) => Err(e),
    );
  }

  // ── driver presence (socket is primary; REST fallback) ──
  Future<Result<void>> goOnline({required double lat, required double lng}) async {
    final res = await _api.post('/drivers/me/online', body: {'lat': lat, 'lng': lng});
    return res.when<Result<void>>(ok: (_) => const Ok(null), err: (e) => Err(e));
  }

  Future<Result<void>> goOffline() async {
    final res = await _api.post('/drivers/me/offline');
    return res.when<Result<void>>(ok: (_) => const Ok(null), err: (e) => Err(e));
  }

  /// Keep-alive ping so dispatch keeps seeing the driver even when the socket
  /// stream is quiet (parked / stationary). Fire-and-forget.
  Future<Result<void>> heartbeat({
    required double lat,
    required double lng,
    double? bearing,
    double? speedKmph,
  }) async {
    final res = await _api.post('/drivers/me/heartbeat', body: {
      'lat': lat,
      'lng': lng,
      if (bearing != null) 'bearing': bearing,
      if (speedKmph != null) 'speedKmph': speedKmph,
    });
    return res.when<Result<void>>(ok: (_) => const Ok(null), err: (e) => Err(e));
  }
}
