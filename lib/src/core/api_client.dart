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
  final Map<int, int> _captchaIds = <int, int>{};
  final Map<String, int> _verificationIds = <String, int>{};

  int get _latestCaptchaId => _captchaIds.isEmpty ? 0 : _captchaIds.values.last;

  String get _clientPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'web';
  }

  Future<AppInfo> getAppInfo() async {
    final data = await _v2Request(
      'GET',
      'v2/app/info',
      query: {'app_id': appId},
    );
    return AppInfo.fromJson(data);
  }

  Future<UserSession> login({
    required String username,
    required String password,
    required String device,
    String captcha = '',
  }) async {
    final data = await _v2Request(
      'POST',
      'v2/auth/login/password',
      body: {
        'app_id': int.tryParse(appId) ?? 1,
        'username': username,
        'password': password,
        'platform': _clientPlatform,
        'device_id': device,
        'device_name': device,
        if (captcha.isNotEmpty) ...{
          'captcha_id': _captchaIds[1] ?? 0,
          'captcha_code': captcha,
        },
      },
    );
    return UserSession.fromJson(data);
  }

  Future<UserSession> loginWithMobile({
    required String mobile,
    required String code,
    required String device,
    String captcha = '',
  }) async {
    final data = await _v2Request(
      'POST',
      'v2/auth/login/code',
      body: {
        'app_id': int.tryParse(appId) ?? 1,
        'identifier_type': 'phone',
        'identifier': mobile,
        'platform': _clientPlatform,
        'device_id': device,
        'device_name': device,
        'verification_id': _verificationIds['login:$mobile'] ?? 0,
        'verification_code': code,
      },
    );
    return UserSession.fromJson(data);
  }

  Future<ImageCaptcha> getImageCaptcha({required int type}) async {
    final data = await _v2Request(
      'POST',
      'v2/verification/captcha',
      body: {'app_id': int.tryParse(appId) ?? 1},
    );
    final id = int.tryParse(data['id']?.toString() ?? '') ?? 0;
    if (id > 0) _captchaIds[type] = id;
    return ImageCaptcha.fromJson(data);
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
    await _v2Request(
      'POST',
      'v2/auth/register',
      body: {
        'app_id': int.tryParse(appId) ?? 1,
        'username': username,
        'nickname': nickname,
        'password': password,
        'platform': _clientPlatform,
        'device_id': device,
        'device_name': device,
        if (mobile.isNotEmpty) ...{
          'identifier_type': 'phone',
          'identifier': mobile,
          'verification_id': _verificationIds['register:$mobile'] ?? 0,
        } else if (email.isNotEmpty) ...{
          'identifier_type': 'email',
          'identifier': email,
          'verification_id': _verificationIds['register:$email'] ?? 0,
        },
        if ((mobile.isNotEmpty || email.isNotEmpty) && captcha.isNotEmpty)
          'verification_code': captcha,
        if (mobile.isEmpty && email.isEmpty && captcha.isNotEmpty) ...{
          'captcha_id': _captchaIds[2] ?? 0,
          'captcha_code': captcha,
        },
      },
    );
  }

  Future<void> sendEmailCode(
    String email, {
    required String device,
    int type = 1,
    String captcha = '',
  }) async {
    final data = await _v2Request(
      'POST',
      'v2/verification/code',
      body: {
        'app_id': int.tryParse(appId) ?? 1,
        'scene': 'register',
        'target': email,
        'captcha_id': _captchaIds[2] ?? 0,
        'captcha_code': captcha,
      },
    );
    final verificationId =
        int.tryParse(data['verification_id']?.toString() ?? '') ?? 0;
    if (verificationId > 0) {
      _verificationIds['register:$email'] = verificationId;
    }
  }

  Future<void> sendMobileCode(
    String mobile, {
    required String device,
    int type = 2,
    String captcha = '',
  }) async {
    final data = await _v2Request(
      'POST',
      'v2/verification/code',
      body: {
        'app_id': int.tryParse(appId) ?? 1,
        'scene': type == 1 ? 'login' : 'register',
        'target': mobile,
        'captcha_id': _captchaIds[type] ?? 0,
        'captcha_code': captcha,
      },
    );
    final verificationId =
        int.tryParse(data['verification_id']?.toString() ?? '') ?? 0;
    if (verificationId > 0) {
      _verificationIds['${type == 1 ? 'login' : 'register'}:$mobile'] =
          verificationId;
    }
  }

  Future<UserSession> getCurrentUser(
    UserSession session, {
    required String device,
  }) async {
    final data = await _v2Request('GET', 'v2/users/me', session: session);
    final avatar = await _resolveAssetUrl(session, data['avatar_asset_id']);
    final background = await _resolveAssetUrl(
      session,
      data['background_asset_id'],
    );
    return session.copyWith(
      nickname: data['nickname']?.toString() ?? session.nickname,
      avatar: avatar.isEmpty ? session.avatar : avatar,
      profileBackground: background.isEmpty
          ? session.profileBackground
          : background,
    );
  }

  Future<WalletBalance> walletBalance({
    required UserSession session,
    required String device,
  }) async {
    final data = await _v2Request('GET', 'v2/wallet/balance', session: session);
    return WalletBalance.fromJson(data);
  }

  Future<List<WalletBill>> walletBills({
    required UserSession session,
    required String device,
    String scene = 'all',
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _v2Request(
      'GET',
      'v2/wallet/bills',
      session: session,
      query: {'limit': limit},
    );
    final list = data['items'];
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

  Future<Map<String, Object?>> assetExchangeOverview({
    required UserSession session,
    required String device,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_exchange_overview',
      session: session,
      device: device,
      params: const {},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> assetExchangeQuote({
    required UserSession session,
    required String device,
    required String amount,
    required String requestId,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_exchange_quote',
      session: session,
      device: device,
      params: {'amount': amount, 'request_id': requestId},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
  }

  Future<Map<String, Object?>> assetExchangeExecute({
    required UserSession session,
    required String device,
    required String quoteToken,
    required String payPassword,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'wallet_asset_exchange_execute',
      session: session,
      device: device,
      params: {'quote_token': quoteToken, 'pay_password': payPassword},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
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
    required String payPassword,
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
        'pay_password': payPassword,
        'address_id': addressId,
        'payment_method_id': paymentMethodId,
      },
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return OtcOrder.fromJson(result.data);
  }

  Future<Map<String, Object?>> otcTradeOptions({
    required UserSession session,
    required String device,
    required int adId,
    required String side,
  }) async {
    final result = await secureSignedImPost<Map<String, Object?>>(
      'otc_trade_options',
      session: session,
      device: device,
      params: {'ad_id': adId, 'side': side},
      secureResponse: true,
    );
    if (!result.isSuccess)
      throw ApiException(result.message, code: result.code);
    return result.data;
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
    required String payPassword,
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
        'pay_password': payPassword,
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
    await _v2Request(
      'PUT',
      'v2/wallet/payment-password',
      session: session,
      body: {
        'password': password,
        'method': verificationMethod,
        'verification_id':
            _verificationIds['payment_password:$verificationMethod'] ?? 0,
        'verification_code': verifyCode,
      },
    );
  }

  Future<Map<String, Object?>> walletSendPayPasswordCode({
    required UserSession session,
    required String device,
    required String verificationMethod,
    required String captcha,
  }) async {
    final security = await _v2Request(
      'GET',
      'v2/auth/security',
      session: session,
    );
    final methods = _mapListFromPayload({'items': security['methods']});
    final selected = methods.firstWhere(
      (item) => item['type']?.toString() == verificationMethod,
      orElse: () => const <String, Object?>{},
    );
    final target = selected['identifier']?.toString() ?? '';
    if (target.isEmpty) throw ApiException('请先绑定安全验证方式');
    final data = await _v2Request(
      'POST',
      'v2/verification/code',
      body: {
        'app_id': int.tryParse(appId) ?? 1,
        'scene': 'payment_password',
        'target': target,
        'captcha_id': _latestCaptchaId,
        'captcha_code': captcha,
      },
    );
    _verificationIds['payment_password:$verificationMethod'] =
        int.tryParse(data['verification_id']?.toString() ?? '') ?? 0;
    return data;
  }

  Future<UserSecurityInfo> userSecurityInfo({
    required UserSession session,
    required String device,
  }) async {
    final data = await _v2Request('GET', 'v2/auth/security', session: session);
    final methods = _mapListFromPayload({'items': data['methods']});
    return UserSecurityInfo.fromJson({
      'mobile_bound': methods.any((item) => item['type'] == 'phone'),
      'email_bound': methods.any((item) => item['type'] == 'email'),
      'mobile': methods
          .where((item) => item['type'] == 'phone')
          .map((item) => item['identifier'])
          .firstOrNull,
      'email': methods
          .where((item) => item['type'] == 'email')
          .map((item) => item['identifier'])
          .firstOrNull,
      'security_bound': methods.isNotEmpty,
      'security_methods': methods
          .map(
            (item) => {
              'method': item['type'],
              'label': item['type'] == 'phone' ? '手机号' : '邮箱',
              'target': item['identifier'],
            },
          )
          .toList(),
    });
  }

  Future<void> sendUserMobileBindCode({
    required UserSession session,
    required String device,
    required String mobile,
    required String captcha,
  }) async {
    final data = await _v2Request(
      'POST',
      'v2/verification/code',
      body: {
        'app_id': int.tryParse(appId) ?? 1,
        'scene': 'bind_phone',
        'target': mobile,
        'captcha_id': _latestCaptchaId,
        'captcha_code': captcha,
      },
    );
    _verificationIds['bind_phone:$mobile'] =
        int.tryParse(data['verification_id']?.toString() ?? '') ?? 0;
  }

  Future<UserSecurityInfo> confirmUserMobileBind({
    required UserSession session,
    required String device,
    required String mobile,
    required String code,
  }) async {
    await _v2Request(
      'POST',
      'v2/auth/security/bind',
      session: session,
      body: {
        'method': 'phone',
        'identifier': mobile,
        'verification_id': _verificationIds['bind_phone:$mobile'] ?? 0,
        'verification_code': code,
      },
    );
    return userSecurityInfo(session: session, device: device);
  }

  Future<void> sendUserEmailBindCode({
    required UserSession session,
    required String device,
    required String email,
    required String captcha,
  }) async {
    final data = await _v2Request(
      'POST',
      'v2/verification/code',
      body: {
        'app_id': int.tryParse(appId) ?? 1,
        'scene': 'bind_email',
        'target': email,
        'captcha_id': _latestCaptchaId,
        'captcha_code': captcha,
      },
    );
    _verificationIds['bind_email:$email'] =
        int.tryParse(data['verification_id']?.toString() ?? '') ?? 0;
  }

  Future<UserSecurityInfo> confirmUserEmailBind({
    required UserSession session,
    required String device,
    required String email,
    required String code,
  }) async {
    await _v2Request(
      'POST',
      'v2/auth/security/bind',
      session: session,
      body: {
        'method': 'email',
        'identifier': email,
        'verification_id': _verificationIds['bind_email:$email'] ?? 0,
        'verification_code': code,
      },
    );
    return userSecurityInfo(session: session, device: device);
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
    final data = await _v2Request(
      'POST',
      'sync/ticket',
      session: session,
      body: const <String, Object?>{},
      cancelToken: cancelToken,
    );
    final gatewayUrl = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/')
        .resolve('sync/connect')
        .replace(scheme: baseUrl.startsWith('https://') ? 'wss' : 'ws')
        .toString();
    return ChatSession.fromJson({
      'uid': 'app${int.tryParse(appId) ?? 1}user${session.userId}',
      'token': session.userToken,
      'device': device,
      'device_flag': AppConfig.imDeviceFlagApp,
      'device_level': AppConfig.imDeviceLevelMaster,
      'channel_type_person': 1,
      'channel_type_group': 2,
      'route': {'api_url': baseUrl, 'https_stream_addr': gatewayUrl},
      'stream': {
        'ticket': data['ticket']?.toString() ?? '',
        'expire_in': int.tryParse(data['expires_in']?.toString() ?? '') ?? 120,
        'https_stream_addr': gatewayUrl,
      },
      'server_history_sync_enabled': 1,
    });
  }

  Future<List<Map<String, Object?>>> conversations({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _v2Request(
      'GET',
      'v2/im/conversations',
      session: session,
      query: {'limit': limit},
    );
    return _mapListFromPayload(data);
  }

  Future<List<Map<String, Object?>>> serviceAccounts({
    required UserSession session,
    required String device,
  }) async {
    final data = await _v2Request(
      'GET',
      'v2/service-accounts/',
      session: session,
    );
    return _mapListFromPayload(data);
  }

  Future<Map<String, Object?>> serviceAccountDetail({
    required UserSession session,
    required String device,
    required int serviceId,
  }) async {
    final code = await _serviceAccountCode(session, serviceId);
    return _v2Request('GET', 'v2/service-accounts/$code', session: session);
  }

  Future<Map<String, Object?>> updateServiceAccountSettings({
    required UserSession session,
    required String device,
    required int serviceId,
    bool? muted,
    bool? pinned,
    bool? following,
  }) async {
    final code = await _serviceAccountCode(session, serviceId);
    return _v2Request(
      'PUT',
      'v2/service-accounts/$code/settings',
      session: session,
      body: {'muted': muted ?? false, 'subscribed': following ?? true},
    );
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
    return _v2Request(
      'GET',
      'v2/im/history',
      session: session,
      query: {
        'channel_id': 'app${int.tryParse(appId) ?? 1}user$receiverId',
        'channel_type': 1,
        if (startMessageSeq > 0) 'before_seq': startMessageSeq,
        'limit': limit,
      },
    );
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
    return _v2Request(
      'GET',
      'v2/im/history',
      session: session,
      query: {
        'channel_id': 'app${int.tryParse(appId) ?? 1}group$groupId',
        'channel_type': 2,
        if (startMessageSeq > 0) 'before_seq': startMessageSeq,
        'limit': limit,
      },
    );
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
  }) async {
    final payload = Map<String, Object?>.from(params);
    if (filePath.isNotEmpty) {
      payload.addAll(
        await _uploadV2Asset(session, filePath, contentType, onUploadProgress),
      );
    }
    return _v2Request(
      'POST',
      'v2/im/messages',
      session: session,
      body: {
        'channel_id': 'app${int.tryParse(appId) ?? 1}user$receiverId',
        'channel_type': 1,
        'client_msg_no': clientMsgNo,
        'content_type': int.tryParse(contentType) ?? 1,
        'payload': payload,
      },
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
  }) async {
    final payload = Map<String, Object?>.from(params);
    if (filePath.isNotEmpty) {
      payload.addAll(
        await _uploadV2Asset(session, filePath, contentType, onUploadProgress),
      );
    }
    return _v2Request(
      'POST',
      'v2/im/messages',
      session: session,
      body: {
        'channel_id': 'app${int.tryParse(appId) ?? 1}group$groupId',
        'channel_type': 2,
        'client_msg_no': clientMsgNo,
        'content_type': int.tryParse(contentType) ?? 1,
        'payload': payload,
      },
    );
  }

  Future<Map<String, Object?>> uploadGroupAvatar({
    required UserSession session,
    required String device,
    required String groupId,
    required String filePath,
    void Function(double progress)? onUploadProgress,
  }) {
    final clientMsgNo = _nonce();
    return secureImBusinessAction(
      action: 'im_group_avatar_upload',
      session: session,
      device: device,
      clientMsgNo: clientMsgNo,
      params: {'client_msg_no': clientMsgNo},
      secureParams: {'group_id': groupId},
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
    final data = await _v2Request('GET', 'v2/social/friends', session: session);
    final items = await _withResolvedAvatars(
      session,
      _mapListFromPayload(data),
    );
    return FriendSnapshot(
      items: items,
      complete: true,
      version: DateTime.now().millisecondsSinceEpoch.toString(),
      generatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Future<List<Map<String, Object?>>> groups({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 50,
  }) async {
    final data = await _v2Request('GET', 'v2/social/groups', session: session);
    return _withResolvedAvatars(session, _mapListFromPayload(data));
  }

  Future<Map<String, Object?>> momentsFeed({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 20,
  }) async {
    return _v2Request(
      'GET',
      'v2/moments/',
      session: session,
      query: {'limit': limit},
    );
  }

  Future<Map<String, Object?>> momentsUser({
    required UserSession session,
    required String device,
    required int userId,
    int page = 1,
    int limit = 20,
  }) async {
    return _v2Request(
      'GET',
      'v2/moments/',
      session: session,
      query: {'user_id': userId, 'limit': limit},
    );
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
    final decodedMedia = jsonDecode(mediaJson);
    return _v2Request(
      'POST',
      'v2/moments/',
      session: session,
      body: {
        'content': content,
        'visibility': visibility == 0 ? 'friends' : 'private',
        'media': decodedMedia is List ? decodedMedia : const [],
      },
    );
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
  }) async {
    return _uploadV2Asset(session, filePath, mediaType, onUploadProgress);
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
    return _dispatchV2Action(action, session, params);
  }

  Future<Map<String, Object?>> _dispatchV2Action(
    String action,
    UserSession session,
    Map<String, Object?> params,
  ) {
    final groupId = params['group_id']?.toString() ?? '';
    final memberId = params['member_id']?.toString() ?? '';
    switch (action) {
      case 'im_friend_apply':
        return _v2Request(
          'POST',
          'v2/social/friend-requests',
          session: session,
          body: {
            'recipient_id':
                int.tryParse(params['friend_id']?.toString() ?? '') ?? 0,
            'message': params['remark']?.toString() ?? '',
          },
        );
      case 'im_friend_handle':
        return _v2Request(
          'POST',
          'v2/social/friend-requests/${params['apply_id']}/decision',
          session: session,
          body: {'accept': params['accept']?.toString() == '1'},
        );
      case 'im_friend_apply_list':
        return _v2Request('GET', 'v2/social/friend-requests', session: session);
      case 'im_friend_search':
        return _v2Request(
          'GET',
          'v2/social/users/search',
          session: session,
          query: {'username': params['keyword']?.toString() ?? ''},
        );
      case 'im_friend_delete':
        return _v2Request(
          'DELETE',
          'v2/social/friends/${params['friend_id']}',
          session: session,
        );
      case 'im_friend_status':
        return _friendStatusV2(session, params['friend_id']);
      case 'im_group_create':
        return _v2Request(
          'POST',
          'v2/social/groups',
          session: session,
          body: {
            'name': params['name']?.toString() ?? '',
            'member_ids': _numericIds(params['member_ids']),
          },
        );
      case 'im_group_update':
        return _v2Request(
          'PATCH',
          'v2/social/groups/$groupId',
          session: session,
          body: {
            if (params.containsKey('name')) 'name': params['name'],
            if (params.containsKey('notice')) 'announcement': params['notice'],
          },
        );
      case 'im_group_members':
        return _v2Request(
          'GET',
          'v2/social/groups/$groupId/members',
          session: session,
        );
      case 'im_group_members_add':
        return _v2Request(
          'POST',
          'v2/social/groups/$groupId/members',
          session: session,
          body: {'member_ids': _numericIds(params['member_ids'])},
        );
      case 'im_group_members_remove':
        return _removeGroupMembers(
          session,
          groupId,
          _numericIds(params['member_ids']),
        );
      case 'im_group_member_mute':
        final seconds =
            int.tryParse(params['expire_seconds']?.toString() ?? '') ?? 0;
        return _v2Request(
          'PUT',
          'v2/social/groups/$groupId/members/$memberId/mute',
          session: session,
          body: {
            'muted_until': seconds <= 0
                ? null
                : DateTime.now()
                      .toUtc()
                      .add(Duration(seconds: seconds))
                      .toIso8601String(),
          },
        );
      case 'im_group_member_unmute':
        return _v2Request(
          'PUT',
          'v2/social/groups/$groupId/members/$memberId/mute',
          session: session,
          body: {'muted_until': null},
        );
      case 'im_group_admin_set':
        return _v2Request(
          'PUT',
          'v2/social/groups/$groupId/members/$memberId/role',
          session: session,
          body: {
            'role': params['is_admin']?.toString() == '1' ? 'admin' : 'member',
          },
        );
      case 'im_group_leave':
        return _v2Request(
          'POST',
          'v2/social/groups/$groupId/leave',
          session: session,
          body: const {},
        );
      case 'im_group_delete':
        return _v2Request(
          'DELETE',
          'v2/social/groups/$groupId',
          session: session,
        );
      case 'im_group_mute_status':
        return _v2Request('GET', 'v2/social/groups/$groupId', session: session);
      case 'im_person_conversation_delete':
        return _v2Request(
          'DELETE',
          'v2/im/conversation',
          session: session,
          body: {
            'channel_id':
                'app${int.tryParse(appId) ?? 1}user${params['receiver_id']}',
            'channel_type': 1,
          },
        );
      case 'im_group_conversation_delete':
        return _v2Request(
          'DELETE',
          'v2/im/conversation',
          session: session,
          body: {
            'channel_id': 'app${int.tryParse(appId) ?? 1}group$groupId',
            'channel_type': 2,
          },
        );
      case 'moments_delete':
        return _v2Request(
          'DELETE',
          'v2/moments/${params['post_id']}',
          session: session,
        );
      case 'moments_like':
        return _v2Request(
          'PUT',
          'v2/moments/${params['post_id']}/like',
          session: session,
          body: const {},
        );
      case 'moments_unlike':
        return _v2Request(
          'DELETE',
          'v2/moments/${params['post_id']}/like',
          session: session,
        );
      case 'moments_comment_add':
        return _v2Request(
          'POST',
          'v2/moments/${params['post_id']}/comments',
          session: session,
          body: {
            'content': params['content']?.toString() ?? '',
            if ((int.tryParse(params['reply_user_id']?.toString() ?? '') ?? 0) >
                0)
              'reply_to_user_id': int.parse(params['reply_user_id'].toString()),
          },
        );
      case 'moments_comment_delete':
        return _v2Request(
          'DELETE',
          'v2/moments/comments/${params['comment_id']}',
          session: session,
        );
      case 'im_message_read_receipts':
        final receipts = _jsonList(params['receipts']);
        final through = receipts.fold<int>(
          0,
          (value, item) => max(
            value,
            int.tryParse(item['message_seq']?.toString() ?? '') ?? 0,
          ),
        );
        return _v2Request(
          'POST',
          'v2/im/read',
          session: session,
          body: {
            'channel_id': params['channel_id']?.toString() ?? '',
            'channel_type':
                int.tryParse(params['channel_type']?.toString() ?? '') ?? 0,
            'through_seq': through,
          },
        );
      case 'im_retry_messages':
        return Future.value(<String, Object?>{'queued': true});
      default:
        throw ApiException('客户端功能尚未迁移到新接口: $action');
    }
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
    await _v2Request(
      'POST',
      'v2/auth/logout',
      session: session,
      body: const <String, Object?>{},
    );
  }

  Future<Map<String, Object?>> _v2Request(
    String method,
    String path, {
    UserSession? session,
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    CancelToken? cancelToken,
  }) async {
    final requestId = AppLogger.traceId('api-v2');
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          contentType: Headers.jsonContentType,
          headers: {
            if (session != null) 'Authorization': 'Bearer ${session.userToken}',
            'X-Request-ID': requestId,
          },
        ),
      );
      final envelope = response.data is Map
          ? (response.data as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, Object?>{};
      if (envelope['code']?.toString() != 'OK') {
        throw ApiException(
          envelope['message']?.toString() ?? '接口请求失败',
          code: response.statusCode,
        );
      }
      final data = envelope['data'];
      if (data is Map) {
        return data.map((key, value) => MapEntry(key.toString(), value));
      }
      if (data is List) return <String, Object?>{'items': data};
      return <String, Object?>{'value': data};
    } on DioException catch (error) {
      final envelope = error.response?.data is Map
          ? (error.response!.data as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const <String, Object?>{};
      throw ApiException(
        envelope['message']?.toString() ?? error.message ?? '网络请求失败',
        code: error.response?.statusCode,
      );
    }
  }

  Future<Map<String, Object?>> _uploadV2Asset(
    UserSession session,
    String filePath,
    String contentType,
    void Function(double progress)? onUploadProgress,
  ) async {
    final response = await _dio.post<Object?>(
      'v2/assets/',
      data: FormData.fromMap({
        'kind': contentType,
        'file': await MultipartFile.fromFile(filePath),
      }),
      options: Options(
        headers: {'Authorization': 'Bearer ${session.userToken}'},
      ),
      onSendProgress: onUploadProgress == null
          ? null
          : (sent, total) {
              if (total > 0) onUploadProgress(sent / total);
            },
    );
    final envelope = response.data is Map
        ? (response.data as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, Object?>{};
    if (envelope['code']?.toString() != 'OK' || envelope['data'] is! Map) {
      throw ApiException(envelope['message']?.toString() ?? '文件上传失败');
    }
    final asset = (envelope['data'] as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    return {
      'asset_id': asset['id'],
      'asset': asset,
      if (asset['url'] != null) 'url': asset['url'],
      if (asset['mime_type'] != null) 'mime_type': asset['mime_type'],
      if (asset['size'] != null) 'size': asset['size'],
      if (asset['original_name'] != null) 'file_name': asset['original_name'],
    };
  }

  Future<String> _resolveAssetUrl(UserSession session, Object? rawId) async {
    final id = int.tryParse(rawId?.toString() ?? '') ?? 0;
    if (id <= 0) return '';
    try {
      final data = await _v2Request('GET', 'v2/assets/$id', session: session);
      return data['url']?.toString() ?? '';
    } on ApiException {
      return '';
    }
  }

  List<int> _numericIds(Object? value) {
    final values = value is Iterable
        ? value
        : value?.toString().split(',') ?? const <String>[];
    return values
        .map((item) => int.tryParse(item.toString().trim()) ?? 0)
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
  }

  List<Map<String, Object?>> _jsonList(Object? value) {
    Object? decoded = value;
    if (value is String && value.isNotEmpty) decoded = jsonDecode(value);
    if (decoded is! Iterable) return const <Map<String, Object?>>[];
    return decoded
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>> _removeGroupMembers(
    UserSession session,
    String groupId,
    List<int> memberIds,
  ) async {
    for (final memberId in memberIds) {
      await _v2Request(
        'DELETE',
        'v2/social/groups/$groupId/members/$memberId',
        session: session,
      );
    }
    return <String, Object?>{'removed': true};
  }

  Future<Map<String, Object?>> _friendStatusV2(
    UserSession session,
    Object? rawFriendId,
  ) async {
    final friendId = int.tryParse(rawFriendId?.toString() ?? '') ?? 0;
    final data = await _v2Request('GET', 'v2/social/friends', session: session);
    final item = _mapListFromPayload(data)
        .cast<Map<String, Object?>?>()
        .firstWhere(
          (friend) => int.tryParse(friend?['id']?.toString() ?? '') == friendId,
          orElse: () => null,
        );
    return <String, Object?>{'is_friend': item != null ? 1 : 0, 'friend': item};
  }

  Future<String> _serviceAccountCode(UserSession session, int serviceId) async {
    final data = await _v2Request(
      'GET',
      'v2/service-accounts/',
      session: session,
    );
    for (final item in _mapListFromPayload(data)) {
      if (int.tryParse(item['id']?.toString() ?? '') == serviceId) {
        final code = item['code']?.toString() ?? '';
        if (code.isNotEmpty) return code;
      }
    }
    throw ApiException('服务号不存在');
  }

  Future<List<Map<String, Object?>>> _withResolvedAvatars(
    UserSession session,
    List<Map<String, Object?>> items,
  ) async {
    return Future.wait(
      items.map((item) async {
        final result = Map<String, Object?>.from(item);
        final avatar = await _resolveAssetUrl(session, item['avatar_asset_id']);
        if (avatar.isNotEmpty) {
          result['avatar_url'] = avatar;
          result['usertx'] = avatar;
          result['group_avatar'] = avatar;
        }
        return result;
      }),
    );
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

Map<String, Object?> _objectResult(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const {};
}
