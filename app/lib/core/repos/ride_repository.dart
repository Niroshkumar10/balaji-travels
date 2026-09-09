import '../models/models.dart';
import '../net/api_client.dart';
import '../net/result.dart';

class RideRepository {
  RideRepository(this._api);
  final ApiClient _api;

  Future<Result<RideEstimate>> estimate({
    required LatLngPoint pickup,
    required LatLngPoint drop,
    List<String>? categories,
  }) async {
    final res = await _api.post('/rides/estimate', body: {
      'pickup': pickup.toJson(),
      'drop': drop.toJson(),
      if (categories != null) 'categories': categories,
    });
    return res.when<Result<RideEstimate>>(
      ok: (j) => Ok(RideEstimate.fromJson(j)),
      err: (e) => Err(e),
    );
  }

  Future<Result<Ride>> create({
    required LatLngPoint pickup,
    required LatLngPoint drop,
    required String vehicleCategory,
    String rideType = 'local',
    String paymentMethod = 'cash',
    String? promoCode,
  }) async {
    final res = await _api.post('/rides', body: {
      'pickup': pickup.toJson(),
      'drop': drop.toJson(),
      'vehicleCategory': vehicleCategory,
      'rideType': rideType,
      'paymentMethod': paymentMethod,
      if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
    });
    return _ride(res);
  }

  Future<Result<Ride?>> active() async {
    final res = await _api.get('/rides/active');
    return res.when<Result<Ride?>>(
      ok: (j) => Ok(j['ride'] == null ? null : Ride.fromJson(asMap(j['ride']))),
      err: (e) => Err(e),
    );
  }

  Future<Result<Ride>> get(int id) async => _ride(await _api.get('/rides/$id'));

  Future<Result<List<Ride>>> list({int limit = 20, int offset = 0}) async {
    final res = await _api.get('/rides', query: {'limit': limit, 'offset': offset});
    return res.when<Result<List<Ride>>>(
      ok: (j) => Ok(asList(j['rides']).map(Ride.fromJson).toList()),
      err: (e) => Err(e),
    );
  }

  Future<Result<List<Map<String, dynamic>>>> history(int id) async {
    final res = await _api.get('/rides/$id/history');
    return res.when<Result<List<Map<String, dynamic>>>>(
      ok: (j) => Ok(asList(j['history'])),
      err: (e) => Err(e),
    );
  }

  Future<Result<Ride>> cancel(int id, {String? reason}) async =>
      _ride(await _api.post('/rides/$id/cancel', body: {if (reason != null) 'reason': reason}));

  // ── driver intents (socket is primary; REST fallback) ──
  Future<Result<Ride>> enroute(int id) => _ride0('/rides/$id/enroute');
  Future<Result<Ride>> arrived(int id) => _ride0('/rides/$id/arrived');
  Future<Result<Ride>> start(int id, String otp) =>
      _post('/rides/$id/start', {'otp': otp});
  Future<Result<Ride>> complete(int id, {int waitingMinutes = 0}) =>
      _post('/rides/$id/complete', {'waitingMinutes': waitingMinutes});
  Future<Result<Map<String, dynamic>>> offerResponse(int id, bool accept) async {
    final res = await _api.post('/rides/$id/offer-response', body: {'accept': accept});
    return res.when<Result<Map<String, dynamic>>>(
      ok: (j) => Ok(j),
      err: (e) => Err(e),
    );
  }

  Future<Result<Ride>> _ride0(String path) => _post(path, const {});
  Future<Result<Ride>> _post(String path, Map<String, dynamic> body) async =>
      _ride(await _api.post(path, body: body));

  Result<Ride> _ride(Result<Map<String, dynamic>> res) => res.when<Result<Ride>>(
        ok: (j) => Ok(Ride.fromJson(asMap(j['ride']))),
        err: (e) => Err(e),
      );
}
