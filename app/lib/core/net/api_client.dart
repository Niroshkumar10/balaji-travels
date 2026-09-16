import 'package:dio/dio.dart';

import '../auth/session.dart';
import '../config/app_config.dart';
import 'api_exception.dart';
import 'result.dart';

/// Thin Dio wrapper.
///
///  - Prepends `/api/v1`, attaches the bearer token from [Session].
///  - Maps every failure to [ApiException] (network → statusCode 0).
///  - On a 401 with code `SESSION_SUPERSEDED` / `SESSION_EXPIRED` it invokes
///    [onUnauthorized] so the app can bounce to login.
class ApiClient {
  ApiClient(this._session, {this.onUnauthorized})
      : _dio = Dio(
          BaseOptions(
            baseUrl: '${AppConfig.apiBaseUrl}/api/v1',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'content-type': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final t = _session.token;
          if (t != null && t.isNotEmpty) {
            options.headers['authorization'] = 'Bearer $t';
          }
          handler.next(options);
        },
        onError: (e, handler) {
          if (e.response?.statusCode == 401) onUnauthorized?.call();
          handler.next(e);
        },
      ),
    );
  }

  final Dio _dio;
  final Session _session;
  final void Function()? onUnauthorized;

  Future<Result<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<Result<Map<String, dynamic>>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) =>
      _send(() => _dio.post(path, data: body, options: Options(headers: headers)));

  Future<Result<Map<String, dynamic>>> patch(String path, {Object? body}) =>
      _send(() => _dio.patch(path, data: body));

  /// Multipart upload — [fileField] is the form field name the server's
  /// multer middleware expects (`upload.single('file')` on the KYC document
  /// routes), [fileBytes]/[filename] the picked image, [fields] any other
  /// form text fields (docType, number, expiry, ...).
  ///
  /// contentType is set explicitly rather than left to the BaseOptions'
  /// default 'application/json' header — Dio only fills in the multipart
  /// boundary itself when the caller declares 'multipart/form-data' up
  /// front; otherwise the base JSON header would win and the server would
  /// receive an unparsable body.
  Future<Result<Map<String, dynamic>>> postMultipart(
    String path, {
    required String fileField,
    required List<int> fileBytes,
    required String filename,
    Map<String, String> fields = const {},
  }) =>
      _send(() => _dio.post(
            path,
            data: FormData.fromMap({
              ...fields,
              fileField: MultipartFile.fromBytes(fileBytes, filename: filename),
            }),
            options: Options(contentType: 'multipart/form-data'),
          ));

  Future<Result<Map<String, dynamic>>> delete(String path) =>
      _send(() => _dio.delete(path));

  Future<Result<Map<String, dynamic>>> _send(
    Future<Response> Function() call,
  ) async {
    try {
      final res = await call();
      final data = res.data;
      return Ok(data is Map<String, dynamic> ? data : <String, dynamic>{'data': data});
    } on DioException catch (e) {
      return Err(_toApiException(e));
    } catch (e) {
      return Err(ApiException(statusCode: 0, code: 'UNKNOWN', message: e.toString()));
    }
  }

  ApiException _toApiException(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ApiException.network();
    }
    final status = e.response?.statusCode ?? 0;
    final body = e.response?.data;
    if (body is Map && body['error'] is Map) {
      final err = body['error'] as Map;
      return ApiException(
        statusCode: status,
        code: (err['code'] ?? 'ERROR').toString(),
        message: (err['message'] ?? 'Request failed').toString(),
        details: err['details'],
      );
    }
    return ApiException(
      statusCode: status,
      code: 'HTTP_$status',
      message: 'Request failed ($status)',
    );
  }
}
