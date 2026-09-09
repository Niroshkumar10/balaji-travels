/// Normalised API error mirroring the backend's
/// `{ "error": { "code", "message", "details?" } }` envelope.
class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  final int statusCode;
  final String code;
  final String message;
  final Object? details;

  bool get isAuth => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isNetwork => statusCode == 0;

  factory ApiException.network([String? m]) => ApiException(
        statusCode: 0,
        code: 'NETWORK',
        message: m ?? 'No internet connection',
      );

  @override
  String toString() => 'ApiException($statusCode $code: $message)';
}
