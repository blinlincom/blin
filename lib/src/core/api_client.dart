import 'package:dio/dio.dart';

import 'app_logger.dart';
import 'api_signer.dart';
import 'app_config.dart';
import 'models.dart';

class ApiClient {
  ApiClient({
    Dio? dio,
    this.baseUrl = AppConfig.apiBaseUrl,
    this.appId = AppConfig.appId,
    String appKey = AppConfig.appKey,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 20),
               responseType: ResponseType.json,
             ),
           ),
       _signer = ApiSigner(appKey);

  final Dio _dio;
  final String baseUrl;
  final String appId;
  final ApiSigner _signer;

  Future<AppInfo> getAppInfo() async {
    final result = await post<Map<String, Object?>>('get_app_info', {
      'timestamp': _timestamp(),
    });
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return AppInfo.fromJson(result.data);
  }

  Future<UserSession> login({
    required String username,
    required String password,
    required String device,
    String captcha = '',
  }) async {
    final result = await post<Map<String, Object?>>('login', {
      'username': username,
      'password': password,
      'captcha': captcha,
      'device': device,
      'device_flag': AppConfig.imDeviceFlagApp.toString(),
      'device_level': AppConfig.imDeviceLevelMaster.toString(),
      'timestamp': _timestamp(),
    });
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return UserSession.fromJson(result.data);
  }

  Future<void> register({
    required String username,
    required String password,
    required String device,
    String mobile = '',
    String email = '',
    String captcha = '',
    String inviteCode = '',
  }) async {
    final result = await post<Object?>('register', {
      'username': username,
      'password': password,
      if (mobile.isNotEmpty) 'mobile': mobile,
      if (email.isNotEmpty) 'email': email,
      if (captcha.isNotEmpty) 'captcha': captcha,
      'device': device,
      if (inviteCode.isNotEmpty) 'invitecode': inviteCode,
      'timestamp': _timestamp(),
    });
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<void> sendEmailCode(String email) async {
    final result = await post<Object?>('get_email_verification_code', {
      'email': email,
      'type': '1',
      'timestamp': _timestamp(),
    });
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<void> sendMobileCode(String mobile) async {
    final result = await post<Object?>('get_mobile_verification_code', {
      'mobile': mobile,
      'type': '2',
      'timestamp': _timestamp(),
    });
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<UserSession> getCurrentUser(UserSession session) async {
    final result = await post<Map<String, Object?>>(
      'get_user_other_information',
      {'usertoken': session.userToken, 'timestamp': _timestamp()},
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return session.copyWith(
      nickname: result.data['nickname']?.toString() ?? session.nickname,
      avatar: result.data['usertx']?.toString() ?? session.avatar,
    );
  }

  Future<ChatSession> connectIm({
    required UserSession session,
    required String device,
  }) async {
    final result = await signedImPost<Map<String, Object?>>(
      'im_connect',
      session: session,
      device: device,
      params: const {},
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return ChatSession.fromJson(result.data);
  }

  Future<List<Map<String, Object?>>> conversations({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 20,
  }) async {
    final result = await signedImPost<Map<String, Object?>>(
      'im_conversations',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    final list = result.data['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    }
    return [];
  }

  Future<List<Map<String, Object?>>> personMessages({
    required UserSession session,
    required String device,
    required String receiverId,
    int startMessageSeq = 0,
    int endMessageSeq = 0,
    int limit = 50,
    int pullMode = 0,
  }) async {
    final data = await personMessagePage(
      session: session,
      device: device,
      receiverId: receiverId,
      startMessageSeq: startMessageSeq,
      endMessageSeq: endMessageSeq,
      limit: limit,
      pullMode: pullMode,
    );
    final list = data['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    }
    return [];
  }

  Future<Map<String, Object?>> personMessagePage({
    required UserSession session,
    required String device,
    required String receiverId,
    int startMessageSeq = 0,
    int endMessageSeq = 0,
    int limit = 50,
    int pullMode = 0,
  }) async {
    final result = await signedImPost<Map<String, Object?>>(
      'im_person_messages',
      session: session,
      device: device,
      params: {
        'receiver_id': receiverId,
        'start_message_seq': startMessageSeq.toString(),
        'end_message_seq': endMessageSeq.toString(),
        'limit': limit.toString(),
        'pull_mode': pullMode.toString(),
      },
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
  }

  Future<List<Map<String, Object?>>> groupMessages({
    required UserSession session,
    required String device,
    required String groupId,
    int startMessageSeq = 0,
    int endMessageSeq = 0,
    int limit = 50,
    int pullMode = 0,
  }) async {
    final data = await groupMessagePage(
      session: session,
      device: device,
      groupId: groupId,
      startMessageSeq: startMessageSeq,
      endMessageSeq: endMessageSeq,
      limit: limit,
      pullMode: pullMode,
    );
    final list = data['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    }
    return [];
  }

  Future<Map<String, Object?>> groupMessagePage({
    required UserSession session,
    required String device,
    required String groupId,
    int startMessageSeq = 0,
    int endMessageSeq = 0,
    int limit = 50,
    int pullMode = 0,
  }) async {
    final result = await signedImPost<Map<String, Object?>>(
      'im_group_messages',
      session: session,
      device: device,
      params: {
        'group_id': groupId,
        'start_message_seq': startMessageSeq.toString(),
        'end_message_seq': endMessageSeq.toString(),
        'limit': limit.toString(),
        'pull_mode': pullMode.toString(),
      },
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
  }

  Future<List<Map<String, Object?>>> friends({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 50,
  }) async {
    final result = await signedImPost<Map<String, Object?>>(
      'im_friend_list',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    final list = result.data['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    }
    return [];
  }

  Future<List<Map<String, Object?>>> groups({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 50,
  }) async {
    final result = await signedImPost<Map<String, Object?>>(
      'im_group_list',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    final list = result.data['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    }
    return [];
  }

  Future<Map<String, Object?>> imBusinessAction({
    required String action,
    required UserSession session,
    required String device,
    Map<String, Object?> params = const {},
    String filePath = '',
  }) async {
    final result = await signedImPost<Map<String, Object?>>(
      action,
      session: session,
      device: device,
      params: params,
      filePath: filePath,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
  }

  Future<void> logout({
    required UserSession session,
    required String device,
  }) async {
    final result = await signedImPost<Object?>(
      'im_logout',
      session: session,
      device: device,
      params: const {},
    );
    if (!result.isSuccess && result.code != 401) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<ApiResult<T>> signedImPost<T>(
    String action, {
    required UserSession session,
    required String device,
    required Map<String, Object?> params,
    String filePath = '',
  }) {
    final payload = <String, Object?>{
      ...params,
      'usertoken': session.userToken,
      'device': device,
      'device_flag': AppConfig.imDeviceFlagApp.toString(),
      'device_level': AppConfig.imDeviceLevelMaster.toString(),
      'timestamp': _timestamp(),
    };
    payload['sign'] = _signer.sign({'appid': appId, ...payload});
    return post<T>(action, payload, filePath: filePath);
  }

  Future<ApiResult<T>> post<T>(
    String action,
    Map<String, Object?> params, {
    String filePath = '',
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'api',
      'post start',
      data: {
        'action': action,
        'base_url': baseUrl,
        'has_file': filePath.isNotEmpty,
        'params': params,
      },
    );
    try {
      final requestData = <String, Object?>{'appid': appId, ...params};
      if (filePath.isNotEmpty) {
        requestData['file'] = await MultipartFile.fromFile(filePath);
      }
      final response = await _dio.post<Object?>(
        action,
        data: FormData.fromMap(requestData),
      );
      final result = _parse<T>(response.data);
      AppLogger.info(
        'api',
        'post success',
        data: {
          'action': action,
          'code': result.code,
          'msg': result.message,
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      return result;
    } on DioException catch (error) {
      final response = error.response?.data;
      AppLogger.error(
        'api',
        'post dio error',
        error: error.message,
        data: {
          'action': action,
          'type': error.type.name,
          'status_code': error.response?.statusCode,
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      if (response != null) {
        final result = _parse<T>(response);
        AppLogger.warn(
          'api',
          'post error response',
          data: {
            'action': action,
            'code': result.code,
            'msg': result.message,
            'ms': stopwatch.elapsedMilliseconds,
          },
        );
        return result;
      }
      throw ApiException(error.message ?? '网络请求失败');
    } catch (error, stackTrace) {
      AppLogger.error(
        'api',
        'post failed',
        error: error,
        stackTrace: stackTrace,
        data: {'action': action, 'ms': stopwatch.elapsedMilliseconds},
      );
      rethrow;
    }
  }

  ApiResult<T> _parse<T>(Object? body) {
    if (body is! Map) {
      throw ApiException('接口返回格式不正确');
    }
    final map = body.cast<String, Object?>();
    final data = map['data'];
    Object? normalizedData = data;
    if (T.toString().contains('Map') && data is! Map) {
      normalizedData = <String, Object?>{};
    }
    return ApiResult<T>(
      code: int.tryParse(map['code']?.toString() ?? '') ?? 0,
      message: map['msg']?.toString() ?? '',
      data: normalizedData as T,
      timestamp: int.tryParse(map['timestamp']?.toString() ?? '') ?? 0,
      sign: map['sign']?.toString(),
    );
  }

  String _timestamp() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
}
