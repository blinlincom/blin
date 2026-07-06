import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import 'app_logger.dart';
import 'api_payload_crypto.dart';
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
  final Random _nonceRandom = Random.secure();

  Future<AppInfo> getAppInfo() async {
    final result = await post<Map<String, Object?>>('get_app_info', {
      'timestamp': _timestamp(),
    }, logDioErrorAsWarn: true);
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
    final result = await securePublicPost<Map<String, Object?>>(
      'login',
      device: device,
      params: {'username': username, 'password': password, 'captcha': captcha},
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return UserSession.fromJson(result.data);
  }

  Future<UserSession> loginWithMobile({
    required String mobile,
    required String code,
    required String device,
    String captcha = '',
  }) async {
    final result = await securePublicPost<Map<String, Object?>>(
      'mobile_login',
      device: device,
      params: {'mobile': mobile, 'code': code, 'captcha': captcha},
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return UserSession.fromJson(result.data);
  }

  Future<ImageCaptcha> getImageCaptcha({required int type}) async {
    final result = await post<Object?>('get_image_verification_code', {
      'type': type,
      'timestamp': _timestamp(),
    });
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return ImageCaptcha.fromJson(result.data);
  }

  Future<void> register({
    required String username,
    required String password,
    required String device,
    String nickname = '',
    String mobile = '',
    String email = '',
    String captcha = '',
    String inviteCode = '',
  }) async {
    final result = await securePublicPost<Object?>(
      'register',
      device: device,
      params: {
        'username': username,
        'password': password,
        if (nickname.isNotEmpty) 'nickname': nickname,
        if (mobile.isNotEmpty) 'mobile': mobile,
        if (email.isNotEmpty) 'email': email,
        if (captcha.isNotEmpty) 'captcha': captcha,
        if (inviteCode.isNotEmpty) 'invitecode': inviteCode,
      },
      expectSecureResponse: false,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<void> sendEmailCode(
    String email, {
    required String device,
    int type = 1,
  }) async {
    final result = await securePublicPost<Object?>(
      'get_email_verification_code',
      device: device,
      params: {'email': email, 'type': type.toString()},
      expectSecureResponse: false,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<void> sendMobileCode(
    String mobile, {
    required String device,
    int type = 2,
  }) async {
    final result = await securePublicPost<Object?>(
      'get_mobile_verification_code',
      device: device,
      params: {'mobile': mobile, 'type': type.toString()},
      expectSecureResponse: false,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<UserSession> getCurrentUser(
    UserSession session, {
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'get_user_other_information',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
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
    final result = await secureSignedImPost<Map<String, Object?>>(
      'im_connect',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return ChatSession.fromJson(result.data);
  }

  Future<void> ackGatewayCursor({
    required String ackUrl,
    required String ticket,
    required String lastCursor,
    List<String> clientMsgNos = const [],
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'api',
      'gateway ack start',
      data: {'ack_url': ackUrl, 'cursor_len': lastCursor.length},
    );
    try {
      final response = await _dio.post<Object?>(
        ackUrl,
        data: <String, Object?>{
          'ticket': ticket,
          'last_cursor': lastCursor,
          if (clientMsgNos.isNotEmpty) 'client_msg_nos': clientMsgNos,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
        ),
      );
      final result = _parse<Map<String, Object?>>(response.data);
      if (!result.isSuccess) {
        throw ApiException(result.message, code: result.code);
      }
      AppLogger.info(
        'api',
        'gateway ack success',
        data: {
          'cursor_len': lastCursor.length,
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ?? error.message ?? 'Gateway ACK 失败',
        code: error.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, Object?>>> conversations({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 20,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'im_conversations',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return _mapListFromPayload(result.data);
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
    return _mapListFromPayload(data);
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
    final result = await secureSignedImPost<Map<String, Object?>>(
      'im_person_messages',
      session: session,
      device: device,
      secureResponse: true,
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
    return _mapListFromPayload(data);
  }

  List<Map<String, Object?>> _mapListFromPayload(Map<String, Object?> data) {
    Object? list;
    for (final key in ['list', 'items', 'rows', 'records']) {
      final value = data[key];
      if (value is List) {
        list = value;
        break;
      }
    }
    final nested = data['data'];
    if (list == null && nested is List) {
      list = nested;
    }
    if (list == null && nested is Map) {
      return _mapListFromPayload(nested.cast<String, Object?>());
    }
    if (list is! List) {
      return [];
    }
    return list
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList();
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
    final result = await secureSignedImPost<Map<String, Object?>>(
      'im_group_messages',
      session: session,
      device: device,
      secureResponse: true,
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

  Future<Map<String, Object?>> sendPersonMessage({
    required UserSession session,
    required String device,
    required String receiverId,
    required String clientMsgNo,
    required String contentType,
    Map<String, Object?> params = const {},
    String filePath = '',
    void Function(double progress)? onUploadProgress,
  }) {
    return secureImBusinessAction(
      action: 'im_person_send',
      session: session,
      device: device,
      clientMsgNo: clientMsgNo,
      secureParams: {
        'receiver_id': receiverId,
        'content_type': contentType,
        ...params,
      },
      params: {'client_msg_no': clientMsgNo},
      filePath: filePath,
      onUploadProgress: onUploadProgress,
      secureResponse: true,
    );
  }

  Future<Map<String, Object?>> sendGroupMessage({
    required UserSession session,
    required String device,
    required String groupId,
    required String clientMsgNo,
    required String contentType,
    Map<String, Object?> params = const {},
    String filePath = '',
    void Function(double progress)? onUploadProgress,
  }) {
    return secureImBusinessAction(
      action: 'im_group_send',
      session: session,
      device: device,
      clientMsgNo: clientMsgNo,
      secureParams: {
        'group_id': groupId,
        'content_type': contentType,
        ...params,
      },
      params: {'client_msg_no': clientMsgNo},
      filePath: filePath,
      onUploadProgress: onUploadProgress,
      secureResponse: true,
    );
  }

  Future<Map<String, Object?>> deletePrivateConversation({
    required UserSession session,
    required String device,
    required String receiverId,
  }) {
    return imBusinessAction(
      action: 'im_person_conversation_delete',
      session: session,
      device: device,
      params: {'receiver_id': receiverId},
    );
  }

  Future<Map<String, Object?>> deleteGroupConversation({
    required UserSession session,
    required String device,
    required String groupId,
  }) {
    return imBusinessAction(
      action: 'im_group_conversation_delete',
      session: session,
      device: device,
      params: {'group_id': groupId},
    );
  }

  Future<Map<String, Object?>> clearAllChatRecords({
    required UserSession session,
    required String device,
  }) {
    return imBusinessAction(
      action: 'im_chat_records_clear_all',
      session: session,
      device: device,
      params: const {},
    );
  }

  Future<Map<String, Object?>> deleteMessageForSelf({
    required UserSession session,
    required String device,
    required String targetClientMsgNo,
  }) {
    return imBusinessAction(
      action: 'im_message_delete',
      session: session,
      device: device,
      params: {'target_client_msg_no': targetClientMsgNo},
    );
  }

  Future<List<Map<String, Object?>>> friends({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 50,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'im_friend_list',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
      secureResponse: true,
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
    final result = await secureSignedImPost<Map<String, Object?>>(
      'im_group_list',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
      secureResponse: true,
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
    bool secureResponse = true,
    void Function(double progress)? onUploadProgress,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      action,
      session: session,
      device: device,
      params: params,
      filePath: filePath,
      onUploadProgress: onUploadProgress,
      secureResponse: secureResponse,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
  }

  Future<Map<String, Object?>> secureImBusinessAction({
    required String action,
    required UserSession session,
    required String device,
    required String clientMsgNo,
    required Map<String, Object?> params,
    required Map<String, Object?> secureParams,
    String filePath = '',
    bool secureResponse = false,
    void Function(double progress)? onUploadProgress,
  }) async {
    final timestamp = _timestamp();
    final nonce = _nonce();
    final payload = <String, Object?>{
      ...params,
      'usertoken': session.userToken,
      'device': device,
      'device_flag': AppConfig.imDeviceFlagApp.toString(),
      'device_level': AppConfig.imDeviceLevelMaster.toString(),
      'timestamp': timestamp,
      'nonce': nonce,
      if (secureResponse) 'secure_response': '1',
    };
    payload.addAll(
      ApiPayloadCrypto.encrypt(
        payload: secureParams,
        appId: appId,
        appKey: _signer.appKey,
        userToken: session.userToken,
        device: device,
        clientMsgNo: clientMsgNo,
        timestamp: timestamp,
        nonce: nonce,
      ),
    );
    EncryptedApiFile? encryptedFile;
    if (filePath.isNotEmpty) {
      encryptedFile = await ApiPayloadCrypto.encryptFile(
        filePath: filePath,
        device: device,
        clientMsgNo: clientMsgNo,
        timestamp: timestamp,
        nonce: nonce,
      );
      payload.addAll({
        'secure_file_alg': 'AES-128-CBC',
        'secure_file_version': '1',
        'secure_file_name': encryptedFile.originalName,
        'secure_file_size': encryptedFile.originalSize.toString(),
        'secure_file_sha256': encryptedFile.cipherSha256,
      });
    }
    try {
      payload['sign'] = _signer.sign({'appid': appId, ...payload});
      final result = await post<Map<String, Object?>>(
        action,
        payload,
        filePath: encryptedFile?.path ?? '',
        fileFieldName: encryptedFile == null ? 'file' : 'secure_file',
        onUploadProgress: onUploadProgress,
        secureResponse: secureResponse
            ? _SecureResponseContext(
                session: session,
                device: device,
                timestamp: timestamp,
                nonce: nonce,
              )
            : null,
      );
      if (!result.isSuccess) {
        throw ApiException(result.message, code: result.code);
      }
      return result.data;
    } finally {
      final tempPath = encryptedFile?.path ?? '';
      if (tempPath.isNotEmpty) {
        await File(tempPath).delete().catchError((Object _) => File(tempPath));
      }
    }
  }

  Future<ApiResult<T>> secureSignedImPost<T>(
    String action, {
    required UserSession session,
    required String device,
    required Map<String, Object?> params,
    String filePath = '',
    bool secureResponse = true,
    void Function(double progress)? onUploadProgress,
  }) {
    final clientMsgNo = _nonce();
    final timestamp = _timestamp();
    final nonce = _nonce();
    final payload = <String, Object?>{
      'usertoken': session.userToken,
      'device': device,
      'device_flag': AppConfig.imDeviceFlagApp.toString(),
      'device_level': AppConfig.imDeviceLevelMaster.toString(),
      'timestamp': timestamp,
      'nonce': nonce,
      'client_msg_no': clientMsgNo,
      if (secureResponse) 'secure_response': '1',
    };
    payload.addAll(
      ApiPayloadCrypto.encrypt(
        payload: params,
        appId: appId,
        appKey: _signer.appKey,
        userToken: session.userToken,
        device: device,
        clientMsgNo: clientMsgNo,
        timestamp: timestamp,
        nonce: nonce,
      ),
    );
    payload['sign'] = _signer.sign({'appid': appId, ...payload});
    return post<T>(
      action,
      payload,
      filePath: filePath,
      onUploadProgress: onUploadProgress,
      secureResponse: secureResponse
          ? _SecureResponseContext(
              session: session,
              device: device,
              timestamp: timestamp,
              nonce: nonce,
            )
          : null,
    );
  }

  Future<ApiResult<T>> securePublicPost<T>(
    String action, {
    required String device,
    required Map<String, Object?> params,
    String filePath = '',
    bool expectSecureResponse = true,
    void Function(double progress)? onUploadProgress,
  }) {
    final clientMsgNo = _nonce();
    final timestamp = _timestamp();
    final nonce = _nonce();
    final payload = <String, Object?>{
      'device': device,
      'device_flag': AppConfig.imDeviceFlagApp.toString(),
      'device_level': AppConfig.imDeviceLevelMaster.toString(),
      'timestamp': timestamp,
      'nonce': nonce,
      'client_msg_no': clientMsgNo,
      if (expectSecureResponse) 'secure_response': '1',
    };
    payload.addAll(
      ApiPayloadCrypto.encrypt(
        payload: params,
        appId: appId,
        appKey: _signer.appKey,
        userToken: '',
        device: device,
        clientMsgNo: clientMsgNo,
        timestamp: timestamp,
        nonce: nonce,
      ),
    );
    payload['sign'] = _signer.sign({'appid': appId, ...payload});
    return post<T>(
      action,
      payload,
      filePath: filePath,
      onUploadProgress: onUploadProgress,
      secureResponse: expectSecureResponse
          ? _SecureResponseContext.public(
              device: device,
              timestamp: timestamp,
              nonce: nonce,
            )
          : null,
    );
  }

  Future<void> logout({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Object?>(
      'im_logout',
      session: session,
      device: device,
      params: const {},
    );
    if (!result.isSuccess && result.code != 401) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<ApiResult<T>> post<T>(
    String action,
    Map<String, Object?> params, {
    String filePath = '',
    String fileFieldName = 'file',
    void Function(double progress)? onUploadProgress,
    _SecureResponseContext? secureResponse,
    bool logDioErrorAsWarn = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final requestId = AppLogger.traceId('api');
    AppLogger.info(
      'api',
      'post start',
      data: {
        'request_id': requestId,
        'action': action,
        'base_url': baseUrl,
        'has_file': filePath.isNotEmpty,
        'file_path': filePath.isEmpty ? '' : filePath,
        'secure_response_required': secureResponse != null,
        'param_keys': params.keys.toList(growable: false),
        'param_summary': _requestParamSummary(params, filePath: filePath),
        'params': _safeLogParams(params),
      },
    );
    try {
      final requestData = <String, Object?>{'appid': appId, ...params};
      if (filePath.isNotEmpty) {
        requestData[fileFieldName] = await MultipartFile.fromFile(filePath);
      }
      final response = await _dio.post<Object?>(
        action,
        data: FormData.fromMap(requestData),
        onSendProgress: onUploadProgress == null
            ? null
            : (sent, total) {
                if (total <= 0) {
                  return;
                }
                onUploadProgress((sent / total).clamp(0, 1).toDouble());
              },
      );
      AppLogger.info(
        'api',
        'post raw response',
        data: {
          'request_id': requestId,
          'action': action,
          'status_code': response.statusCode,
          'content_type': response.headers.value(Headers.contentTypeHeader),
          'body_summary': _responseBodySummary(response.data),
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      final result = _parse<T>(response.data, secureResponse: secureResponse);
      AppLogger.info(
        'api',
        'post success',
        data: {
          'request_id': requestId,
          'action': action,
          'code': result.code,
          'msg': result.message,
          'secure_response_required': secureResponse != null,
          'payload_summary': _payloadSummary(result.data),
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      return result;
    } on DioException catch (error) {
      final response = error.response?.data;
      final errorData = {
        'request_id': requestId,
        'action': action,
        'type': error.type.name,
        'status_code': error.response?.statusCode,
        'response_summary': _responseBodySummary(response),
        'ms': stopwatch.elapsedMilliseconds,
      };
      if (logDioErrorAsWarn) {
        AppLogger.warn(
          'api',
          'post dio warning',
          data: {...errorData, 'error': error.message},
        );
      } else {
        AppLogger.error(
          'api',
          'post dio error',
          error: error.message,
          data: errorData,
        );
      }
      if (response != null) {
        final result = _parse<T>(response, secureResponse: secureResponse);
        AppLogger.warn(
          'api',
          'post error response',
          data: {
            'request_id': requestId,
            'action': action,
            'code': result.code,
            'msg': result.message,
            'payload_summary': _payloadSummary(result.data),
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
        data: {
          'request_id': requestId,
          'action': action,
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      rethrow;
    }
  }

  ApiResult<T> _parse<T>(
    Object? body, {
    _SecureResponseContext? secureResponse,
  }) {
    if (body is! Map) {
      throw ApiException('接口返回格式不正确');
    }
    final map = body.cast<String, Object?>();
    final code = int.tryParse(map['code']?.toString() ?? '') ?? 0;
    final data = map['data'];
    Object? normalizedData = data;
    if (secureResponse != null && code == 1) {
      if (data is! Map) {
        throw ApiException('接口密文返回格式不正确');
      }
      final rawData = data.cast<String, Object?>();
      if ((rawData['secure_payload']?.toString() ?? '').isEmpty) {
        throw ApiException('接口未返回密文数据');
      }
      normalizedData = ApiPayloadCrypto.decryptResponse(
        payload: rawData,
        appId: appId,
        appKey: _signer.appKey,
        userToken: secureResponse.userToken,
        device: secureResponse.device,
        timestamp: secureResponse.timestamp,
        nonce: secureResponse.nonce,
      );
    }
    if (T.toString().contains('Map') && data is! Map) {
      normalizedData = <String, Object?>{};
    }
    return ApiResult<T>(
      code: code,
      message: map['msg']?.toString() ?? '',
      data: normalizedData as T,
      timestamp: int.tryParse(map['timestamp']?.toString() ?? '') ?? 0,
      sign: map['sign']?.toString(),
    );
  }

  String _timestamp() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  String _nonce() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = _nonceRandom.nextInt(1 << 32).toRadixString(36);
    return '$micros$random';
  }

  Map<String, Object?> _safeLogParams(Map<String, Object?> params) {
    if (AppConfig.debugFullApiLog) {
      return Map<String, Object?>.from(params);
    }
    const sensitiveKeys = {
      'password',
      'usertoken',
      'sign',
      'content',
      'secure_payload',
      'file',
      'money',
      'remark',
      'secure_file_name',
      'secure_file_size',
      'secure_file_sha256',
    };
    return {
      for (final entry in params.entries)
        entry.key: sensitiveKeys.contains(entry.key)
            ? '***'
            : entry.value is Map || entry.value is Iterable
            ? '[complex]'
            : entry.value,
    };
  }

  Map<String, Object?> _requestParamSummary(
    Map<String, Object?> params, {
    required String filePath,
  }) {
    final securePayload = params['secure_payload']?.toString() ?? '';
    final content = params['content']?.toString() ?? '';
    return {
      'param_count': params.length,
      'has_usertoken': (params['usertoken']?.toString() ?? '').isNotEmpty,
      'has_device': (params['device']?.toString() ?? '').isNotEmpty,
      'has_timestamp': (params['timestamp']?.toString() ?? '').isNotEmpty,
      'has_sign': (params['sign']?.toString() ?? '').isNotEmpty,
      'has_secure_payload': securePayload.isNotEmpty,
      'secure_payload_len': securePayload.length,
      'content_len': content.length,
      'has_file': filePath.isNotEmpty,
    };
  }

  Map<String, Object?> _responseBodySummary(Object? body) {
    if (body is Map) {
      final map = body.map((key, value) => MapEntry(key.toString(), value));
      final data = map['data'];
      return {
        'type': 'map',
        'keys': map.keys.toList(growable: false),
        'code': map['code'],
        'msg': map['msg'],
        'timestamp': map['timestamp'],
        'sign_present': (map['sign']?.toString() ?? '').isNotEmpty,
        'data_summary': _payloadSummary(data),
      };
    }
    if (body is List) {
      return {'type': 'list', 'count': body.length};
    }
    final text = body?.toString() ?? '';
    return {
      'type': body == null ? 'null' : body.runtimeType.toString(),
      'text_len': text.length,
      if (text.isNotEmpty)
        'text_preview': text.substring(0, min(160, text.length)),
    };
  }

  Map<String, Object?> _payloadSummary(Object? payload) {
    if (payload is Map) {
      final map = payload.map((key, value) => MapEntry(key.toString(), value));
      final securePayload = map['secure_payload']?.toString() ?? '';
      return {
        'type': 'map',
        'key_count': map.length,
        'keys': map.keys.take(80).toList(growable: false),
        'has_secure_payload': securePayload.isNotEmpty,
        'secure_payload_len': securePayload.length,
        if (map['list'] is List) 'list_count': (map['list'] as List).length,
        if (map['items'] is List) 'items_count': (map['items'] as List).length,
        if (map['rows'] is List) 'rows_count': (map['rows'] as List).length,
        if (map['records'] is List)
          'records_count': (map['records'] as List).length,
      };
    }
    if (payload is List) {
      return {'type': 'list', 'count': payload.length};
    }
    final text = payload?.toString() ?? '';
    return {
      'type': payload == null ? 'null' : payload.runtimeType.toString(),
      'text_len': text.length,
    };
  }
}

class _SecureResponseContext {
  _SecureResponseContext({
    required UserSession session,
    required this.device,
    required this.timestamp,
    required this.nonce,
  }) : userToken = session.userToken;

  const _SecureResponseContext.public({
    required this.device,
    required this.timestamp,
    required this.nonce,
  }) : userToken = '';

  final String userToken;
  final String device;
  final String timestamp;
  final String nonce;
}
