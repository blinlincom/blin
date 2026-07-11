import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import 'app_logger.dart';
import 'wire_codec.dart';
import 'request_stamp.dart';
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
       _signer = RequestStamp(appKey);

  final Dio _dio;
  final String baseUrl;
  final String appId;
  final RequestStamp _signer;
  final Random _nonceRandom = Random.secure();

  String get _clientPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'web';
  }

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
    final stopwatch = Stopwatch()..start();
    final requestId = AppLogger.traceId('api');
    final params = <String, Object?>{
      'appid': appId,
      'type': type,
      'timestamp': _timestamp(),
      'nonce': _nonce(),
    };
    AppLogger.info(
      'api',
      'captcha image request start',
      data: {
        'request_id': requestId,
        'action': 'get_image_verification_code',
        'base_url': baseUrl,
        'type': type,
      },
    );
    try {
      final response = await _dio.post<Object?>(
        'get_image_verification_code',
        data: FormData.fromMap(params),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            Headers.acceptHeader:
                'image/png,image/*;q=0.9,application/json;q=0.8',
          },
        ),
      );
      final captcha = _parseImageCaptchaResponse(
        response.data,
        contentType: response.headers.value(Headers.contentTypeHeader),
      );
      AppLogger.info(
        'api',
        'captcha image request success',
        data: {
          'request_id': requestId,
          'status_code': response.statusCode,
          'content_type': response.headers.value(Headers.contentTypeHeader),
          'has_image': captcha.hasImage,
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      return captcha;
    } on DioException catch (error) {
      final response = error.response;
      AppLogger.error(
        'api',
        'captcha image request failed',
        error: error.message,
        data: {
          'request_id': requestId,
          'type': error.type.name,
          'status_code': response?.statusCode,
          'content_type': response?.headers.value(Headers.contentTypeHeader),
          'response_summary': _responseBodySummary(response?.data),
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      if (response?.data != null) {
        return _parseImageCaptchaResponse(
          response!.data,
          contentType: response.headers.value(Headers.contentTypeHeader),
        );
      }
      throw ApiException(error.message ?? '验证码加载失败');
    } catch (error, stackTrace) {
      AppLogger.error(
        'api',
        'captcha image parse failed',
        error: error,
        stackTrace: stackTrace,
        data: {'request_id': requestId, 'ms': stopwatch.elapsedMilliseconds},
      );
      rethrow;
    }
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
    String captcha = '',
  }) async {
    final result = await securePublicPost<Object?>(
      'get_email_verification_code',
      device: device,
      params: {
        'email': email,
        'type': type.toString(),
        if (captcha.isNotEmpty) 'captcha': captcha,
      },
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
    String captcha = '',
  }) async {
    final result = await securePublicPost<Object?>(
      'get_mobile_verification_code',
      device: device,
      params: {
        'mobile': mobile,
        'type': type.toString(),
        if (captcha.isNotEmpty) 'captcha': captcha,
      },
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
      profileBackground:
          _stringFromKeys(result.data, const [
            'profile_background',
            'profile_background_url',
            'moments_background',
            'moments_cover',
            'cover_url',
            'background_url',
            'user_bg',
            'userbg',
          ]) ??
          session.profileBackground,
    );
  }

  Future<WalletBalance> walletBalance({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_balance',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return WalletBalance.fromJson(result.data);
  }

  Future<List<WalletBill>> walletBills({
    required UserSession session,
    required String device,
    String scene = 'all',
    int page = 1,
    int limit = 20,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_bill_list',
      session: session,
      device: device,
      params: {
        'scene': scene,
        'page': page.toString(),
        'limit': limit.toString(),
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    final list = result.data['list'];
    if (list is! List) {
      return const [];
    }
    return list.map(WalletBill.fromJson).toList(growable: false);
  }

  Future<OtcConfig> otcConfig({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_config',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return OtcConfig.fromJson(result.data);
  }

  Future<UsdtWalletOverview> usdtWalletOverview({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_overview',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return UsdtWalletOverview.fromJson(result.data);
  }

  Future<Map<String, Object?>> usdtDepositAddress({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_deposit_address',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> usdtTransferPreview({
    required UserSession session,
    required String device,
    required String username,
    required String amount,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_transfer_preview',
      session: session,
      device: device,
      params: {'username': username, 'amount': amount},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> usdtTransferCreate({
    required UserSession session,
    required String device,
    required String username,
    required String amount,
    required String payPassword,
    String remark = '',
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_transfer_create',
      session: session,
      device: device,
      params: {
        'request_id': _nonce(),
        'username': username,
        'amount': amount,
        'pay_password': payPassword,
        'remark': remark,
      },
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> usdtWithdrawPreview({
    required UserSession session,
    required String device,
    required String address,
    required String amount,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_withdraw_preview',
      session: session,
      device: device,
      params: {'address': address, 'amount': amount},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> usdtWithdrawCreate({
    required UserSession session,
    required String device,
    required String address,
    required String amount,
    required String payPassword,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_withdraw_create',
      session: session,
      device: device,
      params: {
        'request_id': _nonce(),
        'address': address,
        'amount': amount,
        'pay_password': payPassword,
      },
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<List<UsdtAssetBill>> usdtAssetBills({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_bill_list',
      session: session,
      device: device,
      params: const {'limit': '100'},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    final list = result.data['list'];
    return list is List
        ? list.map(UsdtAssetBill.fromJson).toList(growable: false)
        : const [];
  }

  Future<List<OtcAd>> otcAds({
    required UserSession session,
    required String device,
    required String side,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_ad_list',
      session: session,
      device: device,
      params: {'side': side},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    final list = result.data['list'];
    return list is List
        ? list.map(OtcAd.fromJson).toList(growable: false)
        : const [];
  }

  Future<List<OtcOrder>> otcOrders({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_order_list',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    final list = result.data['list'];
    return list is List
        ? list.map(OtcOrder.fromJson).toList(growable: false)
        : const [];
  }

  Future<OtcOrder> otcCreateOrder({
    required UserSession session,
    required String device,
    required int adId,
    required String side,
    required String fiatAmount,
    required int addressId,
    required int paymentMethodId,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      side == 'buy' ? 'otc_order_buy_create' : 'otc_order_sell_create',
      session: session,
      device: device,
      params: {
        'request_id': _nonce(),
        'ad_id': adId,
        'fiat_amount': fiatAmount,
        'address_id': addressId,
        'payment_method_id': paymentMethodId,
      },
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return OtcOrder.fromJson(result.data);
  }

  Future<List<Map<String, Object?>>> otcAddresses({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_address_list',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    final list = result.data['list'];
    return list is List
        ? list.map(_objectResult).toList(growable: false)
        : const [];
  }

  Future<Map<String, Object?>> otcSaveAddress({
    required UserSession session,
    required String device,
    required int assetId,
    required int networkId,
    required String label,
    required String address,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_address_add',
      session: session,
      device: device,
      params: {
        'asset_id': assetId,
        'network_id': networkId,
        'label': label,
        'address': address,
      },
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<List<Map<String, Object?>>> otcPaymentMethods({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_payment_method_list',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    final list = result.data['list'];
    return list is List
        ? list.map(_objectResult).toList(growable: false)
        : const [];
  }

  Future<Map<String, Object?>> otcSavePaymentMethod({
    required UserSession session,
    required String device,
    required String type,
    required String name,
    required String account,
    String bankName = '',
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_payment_method_save',
      session: session,
      device: device,
      params: {
        'method_type': type,
        'account_name': name,
        'account_no': account,
        'bank_name': bankName,
      },
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> otcApplyMerchant({
    required UserSession session,
    required String device,
    required String payPassword,
    String remark = '',
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_merchant_apply',
      session: session,
      device: device,
      params: {
        'request_id': _nonce(),
        'pay_password': payPassword,
        'remark': remark,
      },
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> otcCreateMerchantAd({
    required UserSession session,
    required String device,
    required String side,
    required int assetId,
    required int networkId,
    required String price,
    required String minFiat,
    required String maxFiat,
    required String availableAsset,
    required List<String> paymentMethods,
    String terms = '',
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_merchant_ad_create',
      session: session,
      device: device,
      params: {
        'side': side,
        'asset_id': assetId,
        'network_id': networkId,
        'price': price,
        'min_fiat': minFiat,
        'max_fiat': maxFiat,
        'available_asset': availableAsset,
        'payment_methods': paymentMethods,
        'terms': terms,
      },
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> otcPayMerchantDeposit({
    required UserSession session,
    required String device,
    required String payPassword,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_merchant_deposit_pay',
      session: session,
      device: device,
      params: {'request_id': _nonce(), 'pay_password': payPassword},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<void> walletSetPayPassword({
    required UserSession session,
    required String device,
    required String password,
    required String verificationMethod,
    required String verifyCode,
  }) async {
    final result = await secureSignedImPost<Object?>(
      'wallet_pay_password_set',
      session: session,
      device: device,
      params: {
        'new_pay_password': password,
        'verification_method': verificationMethod,
        'verify_code': verifyCode,
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<Map<String, Object?>> walletSendPayPasswordCode({
    required UserSession session,
    required String device,
    required String verificationMethod,
    required String captcha,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_security_code_send',
      session: session,
      device: device,
      params: {
        if (verificationMethod.isNotEmpty)
          'verification_method': verificationMethod,
        'captcha': captcha,
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
  }

  Future<UserSecurityInfo> userSecurityInfo({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'user_security_info',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return UserSecurityInfo.fromJson(result.data);
  }

  Future<void> sendUserMobileBindCode({
    required UserSession session,
    required String device,
    required String mobile,
    required String captcha,
  }) async {
    final result = await secureSignedImPost<Object?>(
      'user_mobile_bind_code_send',
      session: session,
      device: device,
      params: {'mobile': mobile, 'captcha': captcha},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<UserSecurityInfo> confirmUserMobileBind({
    required UserSession session,
    required String device,
    required String mobile,
    required String code,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'user_mobile_bind_confirm',
      session: session,
      device: device,
      params: {'mobile': mobile, 'code': code},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return UserSecurityInfo.fromJson(result.data);
  }

  Future<void> sendUserEmailBindCode({
    required UserSession session,
    required String device,
    required String email,
    required String captcha,
  }) async {
    final result = await secureSignedImPost<Object?>(
      'user_email_bind_code_send',
      session: session,
      device: device,
      params: {'email': email, 'captcha': captcha},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<UserSecurityInfo> confirmUserEmailBind({
    required UserSession session,
    required String device,
    required String email,
    required String code,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'user_email_bind_confirm',
      session: session,
      device: device,
      params: {'email': email, 'code': code},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return UserSecurityInfo.fromJson(result.data);
  }

  Future<void> walletRechargeKm({
    required UserSession session,
    required String device,
    required String km,
  }) async {
    final result = await secureSignedImPost<Object?>(
      'wallet_recharge_km',
      session: session,
      device: device,
      params: {'km': km},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<void> walletWithdraw({
    required UserSession session,
    required String device,
    required String amount,
    required String account,
    required String name,
    String remark = '',
  }) async {
    final result = await secureSignedImPost<Object?>(
      'wallet_withdraw',
      session: session,
      device: device,
      params: {
        'money': amount,
        'type': '0',
        'account': account,
        'name': name,
        if (remark.isNotEmpty) 'remark': remark,
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
  }

  Future<List<WalletWithdrawRecord>> walletWithdrawRecords({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 20,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_withdraw_list',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    final list = result.data['list'];
    if (list is! List) {
      return const [];
    }
    return list.map(WalletWithdrawRecord.fromJson).toList(growable: false);
  }

  Future<WalletBill> walletBillDetail({
    required UserSession session,
    required String device,
    required int billId,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_bill_detail',
      session: session,
      device: device,
      params: {'id': billId.toString()},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return WalletBill.fromJson(result.data);
  }

  Future<WalletOrder> walletCurrentCollectCode({
    required UserSession session,
    required String device,
    String amount = '',
    String remark = '',
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_collect_code_current',
      session: session,
      device: device,
      params: {
        if (amount.isNotEmpty) 'amount': amount,
        if (remark.isNotEmpty) 'remark': remark,
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return WalletOrder.fromJson(result.data);
  }

  Future<WalletOrder> walletCurrentPayCode({
    required UserSession session,
    required String device,
    String remark = '',
    String payPassword = '',
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_pay_code_current',
      session: session,
      device: device,
      params: {
        if (remark.isNotEmpty) 'remark': remark,
        if (payPassword.isNotEmpty) 'pay_password': payPassword,
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return WalletOrder.fromJson(result.data);
  }

  Future<WalletOrder> walletScanQr({
    required UserSession session,
    required String device,
    required String qrToken,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_qr_scan',
      session: session,
      device: device,
      params: {'qr_token': qrToken},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return WalletOrder.fromJson(result.data);
  }

  Future<WalletOrder> walletConfirmQrPay({
    required UserSession session,
    required String device,
    String qrToken = '',
    String orderNo = '',
    required String payPassword,
    required String amount,
    required String requestId,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_qr_pay_confirm',
      session: session,
      device: device,
      params: {
        if (qrToken.isNotEmpty) 'qr_token': qrToken,
        if (orderNo.isNotEmpty) 'order_no': orderNo,
        'pay_password': payPassword,
        'request_id': requestId,
        if (amount.isNotEmpty) 'amount': amount,
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return WalletOrder.fromJson(result.data['order']);
  }

  Future<WalletOrder> walletOrderStatus({
    required UserSession session,
    required String device,
    required String orderNo,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_order_status',
      session: session,
      device: device,
      params: {'order_no': orderNo},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return WalletOrder.fromJson(result.data);
  }

  Future<ChatSession> connectIm({
    required UserSession session,
    required String device,
    CancelToken? cancelToken,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'im_connect',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
      cancelToken: cancelToken,
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

  Future<List<Map<String, Object?>>> serviceAccounts({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'service_account_list',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return _mapListFromPayload(result.data);
  }

  Future<Map<String, Object?>> serviceAccountDetail({
    required UserSession session,
    required String device,
    required int serviceId,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'service_account_detail',
      session: session,
      device: device,
      params: {'service_id': serviceId.toString()},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return Map<String, Object?>.from(result.data);
  }

  Future<Map<String, Object?>> updateServiceAccountSettings({
    required UserSession session,
    required String device,
    required int serviceId,
    bool? muted,
    bool? pinned,
    bool? following,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'service_account_settings_update',
      session: session,
      device: device,
      params: {
        'service_id': serviceId.toString(),
        if (muted != null) 'muted': muted ? '1' : '0',
        if (pinned != null) 'pinned': pinned ? '1' : '0',
        if (following != null) 'following': following ? '1' : '0',
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return Map<String, Object?>.from(result.data);
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
    bool unreadOnly = false,
    int unreadLimit = 0,
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
        if (unreadOnly) 'unread_only': '1',
        if (unreadLimit > 0) 'unread_limit': unreadLimit.toString(),
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
    bool unreadOnly = false,
    int unreadLimit = 0,
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
        if (unreadOnly) 'unread_only': '1',
        if (unreadLimit > 0) 'unread_limit': unreadLimit.toString(),
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

  Future<Map<String, Object?>> uploadProfileBackground({
    required UserSession session,
    required String device,
    required String filePath,
    void Function(double progress)? onUploadProgress,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'upload_background',
      session: session,
      device: device,
      params: const {},
      filePath: filePath,
      secureResponse: false,
      onUploadProgress: onUploadProgress,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
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

  Future<FriendSnapshot> friends({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 50,
  }) async {
    final items = <Map<String, Object?>>[];
    var currentPage = page;
    var version = '';
    var generatedAt = 0;
    for (var requestCount = 0; requestCount < 20; requestCount++) {
      final result = await secureSignedImPost<Map<String, Object?>>(
        'im_friend_list',
        session: session,
        device: device,
        params: {'page': currentPage.toString(), 'limit': limit.toString()},
        secureResponse: true,
      );
      if (!result.isSuccess) {
        throw ApiException(result.message, code: result.code);
      }
      final pageVersion = result.data['snapshot_version']?.toString() ?? '';
      if (pageVersion.isEmpty ||
          (version.isNotEmpty && version != pageVersion)) {
        throw ApiException('好友数据同步版本发生变化，请重试');
      }
      version = pageVersion;
      generatedAt =
          int.tryParse(result.data['generated_at']?.toString() ?? '') ??
          generatedAt;
      final list = result.data['list'];
      if (list is List) {
        items.addAll(
          list.whereType<Map>().map((item) => item.cast<String, Object?>()),
        );
      }
      if (result.data['snapshot_complete']?.toString() == '1') {
        return FriendSnapshot(
          items: items,
          complete: true,
          version: version,
          generatedAt: generatedAt,
        );
      }
      currentPage++;
    }
    throw ApiException('好友数量超过同步上限');
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

  Future<Map<String, Object?>> momentsFeed({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 20,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'moments_feed',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
  }

  Future<Map<String, Object?>> momentsUser({
    required UserSession session,
    required String device,
    required int userId,
    int page = 1,
    int limit = 20,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'moments_user',
      session: session,
      device: device,
      params: {
        'user_id': userId.toString(),
        'page': page.toString(),
        'limit': limit.toString(),
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
  }

  Future<Map<String, Object?>> momentsPublish({
    required UserSession session,
    required String device,
    required String content,
    required String mediaJson,
    int visibility = 0,
    List<int> visibleUserIds = const [],
    List<int> remindUserIds = const [],
    String location = '',
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'moments_publish',
      session: session,
      device: device,
      params: {
        'content': content,
        'media': mediaJson,
        'visibility': visibility.toString(),
        if (visibleUserIds.isNotEmpty) 'visible_user_ids': visibleUserIds,
        if (remindUserIds.isNotEmpty) 'remind_user_ids': remindUserIds,
        if (location.isNotEmpty) 'location': location,
      },
      secureResponse: true,
    );
    if (!result.isSuccess) {
      throw ApiException(result.message, code: result.code);
    }
    return result.data;
  }

  Future<Map<String, Object?>> momentsMediaUpload({
    required UserSession session,
    required String device,
    required String filePath,
    required String mediaType,
    String name = '',
    String mime = '',
    int size = 0,
    int width = 0,
    int height = 0,
    int duration = 0,
    void Function(double progress)? onUploadProgress,
  }) {
    final clientMsgNo = _nonce();
    return secureImBusinessAction(
      action: 'moments_media_upload',
      session: session,
      device: device,
      clientMsgNo: clientMsgNo,
      params: {'client_msg_no': clientMsgNo},
      secureParams: {
        'media_type': mediaType,
        if (name.isNotEmpty) 'name': name,
        if (mime.isNotEmpty) 'mime': mime,
        if (size > 0) 'size': size.toString(),
        if (width > 0) 'width': width.toString(),
        if (height > 0) 'height': height.toString(),
        if (duration > 0) 'duration': duration.toString(),
      },
      filePath: filePath,
      onUploadProgress: onUploadProgress,
      secureResponse: true,
    );
  }

  Future<Map<String, Object?>> momentsDelete({
    required UserSession session,
    required String device,
    required int postId,
  }) {
    return imBusinessAction(
      action: 'moments_delete',
      session: session,
      device: device,
      params: {'post_id': postId.toString()},
    );
  }

  Future<Map<String, Object?>> momentsLike({
    required UserSession session,
    required String device,
    required int postId,
  }) {
    return imBusinessAction(
      action: 'moments_like',
      session: session,
      device: device,
      params: {'post_id': postId.toString()},
    );
  }

  Future<Map<String, Object?>> momentsUnlike({
    required UserSession session,
    required String device,
    required int postId,
  }) {
    return imBusinessAction(
      action: 'moments_unlike',
      session: session,
      device: device,
      params: {'post_id': postId.toString()},
    );
  }

  Future<Map<String, Object?>> momentsCommentAdd({
    required UserSession session,
    required String device,
    required int postId,
    required String content,
    int replyCommentId = 0,
    int replyUserId = 0,
  }) {
    return imBusinessAction(
      action: 'moments_comment_add',
      session: session,
      device: device,
      params: {
        'post_id': postId.toString(),
        'content': content,
        if (replyCommentId > 0) 'reply_comment_id': replyCommentId.toString(),
        if (replyUserId > 0) 'reply_user_id': replyUserId.toString(),
      },
    );
  }

  Future<Map<String, Object?>> momentsCommentDelete({
    required UserSession session,
    required String device,
    required int commentId,
  }) {
    return imBusinessAction(
      action: 'moments_comment_delete',
      session: session,
      device: device,
      params: {'comment_id': commentId.toString()},
    );
  }

  Future<Map<String, Object?>> liveKitCallCreate({
    required UserSession session,
    required String device,
    required String callType,
    required String mediaType,
    String receiverId = '',
    String groupId = '',
    String title = '',
    List<String> inviteUserIds = const [],
  }) {
    return imBusinessAction(
      action: 'im_call_create',
      session: session,
      device: device,
      params: {
        'call_type': callType,
        'media_type': mediaType,
        if (receiverId.isNotEmpty) 'receiver_id': receiverId,
        if (groupId.isNotEmpty) 'group_id': groupId,
        if (title.isNotEmpty) 'title': title,
        if (inviteUserIds.isNotEmpty) 'invite_user_ids': inviteUserIds,
      },
    );
  }

  Future<Map<String, Object?>> liveKitCallAccept({
    required UserSession session,
    required String device,
    required int callId,
  }) {
    return imBusinessAction(
      action: 'im_call_accept',
      session: session,
      device: device,
      params: {'call_id': callId.toString()},
    );
  }

  Future<Map<String, Object?>> liveKitCallReject({
    required UserSession session,
    required String device,
    required int callId,
  }) {
    return imBusinessAction(
      action: 'im_call_reject',
      session: session,
      device: device,
      params: {'call_id': callId.toString()},
    );
  }

  Future<Map<String, Object?>> liveKitCallCancel({
    required UserSession session,
    required String device,
    required int callId,
  }) {
    return imBusinessAction(
      action: 'im_call_cancel',
      session: session,
      device: device,
      params: {'call_id': callId.toString()},
    );
  }

  Future<Map<String, Object?>> liveKitCallHangup({
    required UserSession session,
    required String device,
    required int callId,
    bool endCall = false,
  }) {
    return imBusinessAction(
      action: 'im_call_hangup',
      session: session,
      device: device,
      params: {'call_id': callId.toString(), if (endCall) 'end_call': '1'},
    );
  }

  Future<Map<String, Object?>> liveKitCallToken({
    required UserSession session,
    required String device,
    required int callId,
  }) {
    return imBusinessAction(
      action: 'im_call_token',
      session: session,
      device: device,
      params: {'call_id': callId.toString()},
    );
  }

  Future<Map<String, Object?>> stickerPacks({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 50,
  }) {
    return imBusinessAction(
      action: 'im_sticker_packs',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
    );
  }

  Future<Map<String, Object?>> stickerMine({
    required UserSession session,
    required String device,
  }) {
    return imBusinessAction(
      action: 'im_sticker_mine',
      session: session,
      device: device,
      params: const {},
    );
  }

  Future<Map<String, Object?>> stickerPackBuy({
    required UserSession session,
    required String device,
    required String packId,
  }) {
    return imBusinessAction(
      action: 'im_sticker_pack_buy',
      session: session,
      device: device,
      params: {'pack_id': packId},
    );
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
      'client_platform': _clientPlatform,
      'device_flag': AppConfig.imDeviceFlagApp.toString(),
      'device_level': AppConfig.imDeviceLevelMaster.toString(),
      'timestamp': timestamp,
      'nonce': nonce,
      if (secureResponse) 'secure_response': '1',
    };
    payload.addAll(
      WireCodec.pack(
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
    PackedWireFile? wireFile;
    if (filePath.isNotEmpty) {
      wireFile = await WireCodec.packFile(
        filePath: filePath,
        device: device,
        clientMsgNo: clientMsgNo,
        timestamp: timestamp,
        nonce: nonce,
      );
      payload.addAll({
        'secure_file_alg': 'AES-128-CBC',
        'secure_file_version': '1',
        'secure_file_name': wireFile.originalName,
        'secure_file_size': wireFile.originalSize.toString(),
        'secure_file_sha256': wireFile.packedSha256,
      });
    }
    try {
      payload['sign'] = _signer.sign({'appid': appId, ...payload});
      final result = await post<Map<String, Object?>>(
        action,
        payload,
        filePath: wireFile?.path ?? '',
        fileFieldName: wireFile == null ? 'file' : 'secure_file',
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
      final tempPath = wireFile?.path ?? '';
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
    CancelToken? cancelToken,
  }) {
    final clientMsgNo = _nonce();
    final timestamp = _timestamp();
    final nonce = _nonce();
    final payload = <String, Object?>{
      'usertoken': session.userToken,
      'device': device,
      'client_platform': _clientPlatform,
      'device_flag': AppConfig.imDeviceFlagApp.toString(),
      'device_level': AppConfig.imDeviceLevelMaster.toString(),
      'timestamp': timestamp,
      'nonce': nonce,
      'client_msg_no': clientMsgNo,
      if (secureResponse) 'secure_response': '1',
    };
    payload.addAll(
      WireCodec.pack(
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
      cancelToken: cancelToken,
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
      'client_platform': _clientPlatform,
      'device_flag': AppConfig.imDeviceFlagApp.toString(),
      'device_level': AppConfig.imDeviceLevelMaster.toString(),
      'timestamp': timestamp,
      'nonce': nonce,
      'client_msg_no': clientMsgNo,
      if (expectSecureResponse) 'secure_response': '1',
    };
    payload.addAll(
      WireCodec.pack(
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
    CancelToken? cancelToken,
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
        cancelToken: cancelToken,
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

  ImageCaptcha _parseImageCaptchaResponse(
    Object? body, {
    required String? contentType,
  }) {
    final normalizedType = (contentType ?? '').split(';').first.trim();
    if (body is List<int>) {
      if (_looksLikeImageBytes(body, normalizedType)) {
        final mimeType = normalizedType.startsWith('image/')
            ? normalizedType
            : _guessImageMimeType(body);
        return ImageCaptcha(
          image: 'data:$mimeType;base64,${base64Encode(body)}',
        );
      }
      final text = utf8.decode(body, allowMalformed: true).trim();
      if (text.isNotEmpty) {
        try {
          final decoded = jsonDecode(text);
          final result = _parse<Object?>(decoded);
          if (!result.isSuccess) {
            throw ApiException(result.message, code: result.code);
          }
          return ImageCaptcha.fromJson(result.data);
        } on FormatException {
          throw ApiException('验证码返回格式不正确');
        }
      }
    }
    if (body is Map || body is String) {
      final result = body is Map
          ? _parse<Object?>(body)
          : ApiResult<Object?>(
              code: 1,
              message: 'success',
              data: body,
              timestamp: 0,
            );
      if (!result.isSuccess) {
        throw ApiException(result.message, code: result.code);
      }
      return ImageCaptcha.fromJson(result.data);
    }
    throw ApiException('验证码返回格式不正确');
  }

  bool _looksLikeImageBytes(List<int> bytes, String contentType) {
    if (contentType.startsWith('image/')) {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.length >= 6) {
      final header = String.fromCharCodes(bytes.take(6));
      if (header == 'GIF87a' || header == 'GIF89a') {
        return true;
      }
    }
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.take(4));
      final webp = String.fromCharCodes(bytes.skip(8).take(4));
      if (riff == 'RIFF' && webp == 'WEBP') {
        return true;
      }
    }
    return false;
  }

  String _guessImageMimeType(List<int> bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6) {
      final header = String.fromCharCodes(bytes.take(6));
      if (header == 'GIF87a' || header == 'GIF89a') {
        return 'image/gif';
      }
    }
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.take(4));
      final webp = String.fromCharCodes(bytes.skip(8).take(4));
      if (riff == 'RIFF' && webp == 'WEBP') {
        return 'image/webp';
      }
    }
    return 'image/png';
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
      normalizedData = WireCodec.unpackResponse(
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

String? _stringFromKeys(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

Map<String, Object?> _objectResult(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const {};
}
