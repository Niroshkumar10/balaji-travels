import '../models/models.dart';
import '../net/api_client.dart';
import '../net/result.dart';

/// Fare config, places, promos, ratings, notifications, earnings — the smaller
/// domains, one repository.
class MiscRepository {
  MiscRepository(this._api);
  final ApiClient _api;

  // ── fare ──
  Future<Result<List<Map<String, dynamic>>>> fareConfig() async {
    final res = await _api.get('/fare/config');
    return res.when<Result<List<Map<String, dynamic>>>>(
      ok: (j) => Ok(asList(j['configs'])),
      err: (e) => Err(e),
    );
  }

  // ── places ──
  Future<Result<List<PlacePrediction>>> autocomplete(
    String q, {
    double? lat,
    double? lng,
  }) async {
    final res = await _api.get('/places/autocomplete', query: {
      'q': q,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return res.when<Result<List<PlacePrediction>>>(
      ok: (j) => Ok(asList(j['predictions']).map(PlacePrediction.fromJson).toList()),
      err: (e) => Err(e),
    );
  }

  Future<Result<LatLngPoint>> placeDetails(String placeId) async {
    final res = await _api.get('/places/details', query: {'placeId': placeId});
    return res.when<Result<LatLngPoint>>(
      ok: (j) => Ok(LatLngPoint.fromJson(asMap(j['place']))),
      err: (e) => Err(e),
    );
  }

  Future<Result<LatLngPoint>> reverseGeocode(double lat, double lng) async {
    final res = await _api.get('/places/reverse', query: {'lat': lat, 'lng': lng});
    return res.when<Result<LatLngPoint>>(
      ok: (j) => Ok(LatLngPoint.fromJson(asMap(j['place']))),
      err: (e) => Err(e),
    );
  }

  Future<Result<List<SavedPlace>>> savedPlaces() async {
    final res = await _api.get('/places/saved');
    return res.when<Result<List<SavedPlace>>>(
      ok: (j) => Ok(asList(j['places']).map(SavedPlace.fromJson).toList()),
      err: (e) => Err(e),
    );
  }

  Future<Result<void>> addSavedPlace(Map<String, dynamic> body) async {
    final res = await _api.post('/places/saved', body: body);
    return res.when<Result<void>>(ok: (_) => const Ok(null), err: (e) => Err(e));
  }

  Future<Result<void>> removeSavedPlace(int id) async {
    final res = await _api.delete('/places/saved/$id');
    return res.when<Result<void>>(ok: (_) => const Ok(null), err: (e) => Err(e));
  }

  // ── promos ──
  Future<Result<List<Map<String, dynamic>>>> promos() async {
    final res = await _api.get('/promos');
    return res.when<Result<List<Map<String, dynamic>>>>(
      ok: (j) => Ok(asList(j['promos'])),
      err: (e) => Err(e),
    );
  }

  Future<Result<Map<String, dynamic>>> applyPromo(String code, double fare) async {
    final res = await _api.post('/promos/apply', body: {'code': code, 'fare': fare});
    return res.when<Result<Map<String, dynamic>>>(ok: (j) => Ok(j), err: (e) => Err(e));
  }

  // ── ratings ──
  Future<Result<void>> rate(
    int rideId, {
    required int stars,
    String? comment,
    List<String>? tags,
  }) async {
    final res = await _api.post('/ratings/rides/$rideId', body: {
      'stars': stars,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
    });
    return res.when<Result<void>>(ok: (_) => const Ok(null), err: (e) => Err(e));
  }

  // ── notifications ──
  Future<Result<({List<NotificationItem> items, int unread})>> notifications({
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await _api.get('/notifications', query: {'limit': limit, 'offset': offset});
    return res.when<Result<({List<NotificationItem> items, int unread})>>(
      ok: (j) => Ok((
        items: asList(j['notifications']).map(NotificationItem.fromJson).toList(),
        unread: asInt(j['unread']),
      )),
      err: (e) => Err(e),
    );
  }

  Future<void> markNotificationRead(int id) => _api.post('/notifications/$id/read');
  Future<void> markAllNotificationsRead() => _api.post('/notifications/read-all');

  // ── earnings (driver) ──
  Future<Result<EarningsSummary>> earningsSummary(String period) async {
    final res = await _api.get('/earnings/summary', query: {'period': period});
    return res.when<Result<EarningsSummary>>(
      ok: (j) => Ok(EarningsSummary.fromJson(asMap(j['summary']))),
      err: (e) => Err(e),
    );
  }

  Future<Result<List<LedgerEntry>>> earningsLedger({int limit = 30, int offset = 0}) async {
    final res = await _api.get('/earnings/ledger', query: {'limit': limit, 'offset': offset});
    return res.when<Result<List<LedgerEntry>>>(
      ok: (j) => Ok(asList(j['ledger']).map(LedgerEntry.fromJson).toList()),
      err: (e) => Err(e),
    );
  }

  Future<Result<List<Payout>>> payouts() async {
    final res = await _api.get('/earnings/payouts');
    return res.when<Result<List<Payout>>>(
      ok: (j) => Ok(asList(j['payouts']).map(Payout.fromJson).toList()),
      err: (e) => Err(e),
    );
  }

  Future<Result<Map<String, dynamic>>> requestPayout(double amount) async {
    final res = await _api.post('/earnings/payout', body: {'amount': amount});
    return res.when<Result<Map<String, dynamic>>>(ok: (j) => Ok(j), err: (e) => Err(e));
  }
}
