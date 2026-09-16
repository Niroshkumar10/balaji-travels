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

  /// docType: 'license' | 'id_proof' | 'photo' — see server drivers.routes.js.
  Future<Result<DriverProfile>> uploadDriverDocument({
    required String docType,
    required List<int> fileBytes,
    required String filename,
    String? number,
    String? idProofType,
    DateTime? expiry,
  }) async {
    final res = await _api.postMultipart(
      '/drivers/me/documents',
      fileField: 'file',
      fileBytes: fileBytes,
      filename: filename,
      fields: {
        'docType': docType,
        if (number != null) 'number': number,
        if (idProofType != null) 'idProofType': idProofType,
        if (expiry != null) 'expiry': expiry.toIso8601String().split('T').first,
      },
    );
    return res.when<Result<DriverProfile>>(
      ok: (j) => Ok(DriverProfile.fromProfileJson(asMap(j['profile']))),
      err: (e) => Err(e),
    );
  }

  /// docType: 'rc' | 'insurance' | 'permit' | 'fitness' | 'puc'.
  Future<Result<Vehicle>> uploadVehicleDocument({
    required String docType,
    required List<int> fileBytes,
    required String filename,
    String? number,
    DateTime? expiry,
  }) async {
    final res = await _api.postMultipart(
      '/drivers/me/vehicle/documents',
      fileField: 'file',
      fileBytes: fileBytes,
      filename: filename,
      fields: {
        'docType': docType,
        if (number != null) 'number': number,
        if (expiry != null) 'expiry': expiry.toIso8601String().split('T').first,
      },
    );
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
