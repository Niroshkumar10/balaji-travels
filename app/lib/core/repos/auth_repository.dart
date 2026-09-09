import '../auth/session.dart';
import '../models/models.dart';
import '../net/api_client.dart';
import '../net/result.dart';

class OtpRequestResult {
  const OtpRequestResult({this.devCode, this.expiresInSeconds = 300});
  final String? devCode;
  final int expiresInSeconds;
}

class LoginResult {
  const LoginResult({
    required this.token,
    required this.user,
    required this.profileId,
    required this.isNewUser,
  });
  final String token;
  final AuthUser user;
  final int profileId;
  final bool isNewUser;
}

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<Result<OtpRequestResult>> requestOtp({
    required String mobile,
    required AppRole role,
  }) async {
    final res = await _api.post('/auth/otp/request', body: {
      'mobile': mobile,
      'role': role.name,
    });
    return res.when<Result<OtpRequestResult>>(
      ok: (j) => Ok(OtpRequestResult(
        devCode: j['devCode']?.toString(),
        expiresInSeconds: asInt(j['expiresInSeconds'], 300),
      )),
      err: (e) => Err(e),
    );
  }

  Future<Result<LoginResult>> verifyOtp({
    required String mobile,
    required AppRole role,
    required String code,
  }) async {
    final res = await _api.post('/auth/otp/verify', body: {
      'mobile': mobile,
      'role': role.name,
      'code': code,
    });
    return res.when<Result<LoginResult>>(
      ok: (j) {
        final profile = asMap(j['profile']);
        return Ok(LoginResult(
          token: j['token']?.toString() ?? '',
          user: AuthUser.fromJson(asMap(j['user'])),
          profileId: asInt(profile['id']),
          isNewUser: asBool(j['isNewUser']),
        ));
      },
      err: (e) => Err(e),
    );
  }

  Future<Result<void>> logout() async {
    final res = await _api.post('/auth/logout');
    return res.when<Result<void>>(ok: (_) => const Ok(null), err: (e) => Err(e));
  }

  Future<void> registerFcmToken(String token) async {
    await _api.post('/auth/fcm-token', body: {'fcmToken': token});
  }
}
