import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/session_controller.dart';
import '../../core/design_tokens.dart';
import '../../core/models.dart';
import '../../ui/bim_ui.dart';

const _authBlue = BimColors.primary;
const _authPage = BimColors.background;
const _authSurface = BimColors.surface;
const _authText = BimColors.text;
const _authMuted = BimColors.secondaryText;
const _authBorder = BimColors.border;
const _authFill = BimColors.surface;
const _authDanger = BimColors.dangerDeep;

enum _LoginMode { password, mobile }

enum _RegisterMode { username, mobile, email }

class AuthPage extends StatefulWidget {
  const AuthPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  var _isLogin = true;
  var _loginMode = _LoginMode.password;
  var _registerMode = _RegisterMode.username;
  var _acceptedLoginAgreement = false;
  var _acceptedRegisterAgreement = false;
  var _showLoginPassword = false;
  var _showRegisterPassword = false;
  var _showConfirmPassword = false;
  var _loginCaptchaRevision = 0;
  var _registerCaptchaRevision = 0;
  var _authConfigLoading = true;
  var _authConfigError = '';

  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _loginAccount = TextEditingController();
  final _loginPassword = TextEditingController();
  final _loginCode = TextEditingController();
  final _loginImageCaptcha = TextEditingController();
  final _registerUsername = TextEditingController();
  final _registerPassword = TextEditingController();
  final _registerConfirmPassword = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerMobile = TextEditingController();
  final _registerCode = TextEditingController();
  final _registerImageCaptcha = TextEditingController();
  final _registerInviteCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_loadAuthConfig());
  }

  @override
  void didUpdateWidget(covariant AuthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_loadAuthConfig());
    }
  }

  @override
  void dispose() {
    _loginAccount.dispose();
    _loginPassword.dispose();
    _loginCode.dispose();
    _loginImageCaptcha.dispose();
    _registerUsername.dispose();
    _registerPassword.dispose();
    _registerConfirmPassword.dispose();
    _registerEmail.dispose();
    _registerMobile.dispose();
    _registerCode.dispose();
    _registerImageCaptcha.dispose();
    _registerInviteCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: _authPage,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _authConfigLoading || _authConfigError.isNotEmpty
                      ? _authConfigGate(key: const ValueKey('auth-config'))
                      : _isLogin
                      ? _loginView(key: const ValueKey('login'))
                      : _registerView(key: const ValueKey('register')),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _authConfigGate({required Key key}) {
    final hasError = _authConfigError.isNotEmpty;
    return ListView(
      key: key,
      padding: EdgeInsets.fromLTRB(_pageInset, 58, _pageInset, 28),
      children: [
        _AuthBrand(appInfo: widget.controller.appInfo),
        const SizedBox(height: 28),
        _AuthTitle(title: '登录', subtitle: hasError ? '登录配置加载失败' : '正在读取后台登录配置'),
        const SizedBox(height: 34),
        if (hasError) ...[
          _Notice(text: _authConfigError),
          const SizedBox(height: 18),
          _PrimaryAuthButton(text: '重新加载', onPressed: _loadAuthConfig),
        ] else
          const _AuthConfigLoadingForm(),
      ],
    );
  }

  Widget _loginView({required Key key}) {
    final config = widget.controller.authConfig;
    final mode = _activeLoginMode(config);
    return ListView(
      key: key,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(_pageInset, 58, _pageInset, 28),
      children: [
        _AuthBrand(appInfo: widget.controller.appInfo),
        const SizedBox(height: 28),
        const _AuthTitle(title: '登录', subtitle: '欢迎回来，登录后继续畅聊'),
        const SizedBox(height: 34),
        if (widget.controller.error != null) ...[
          _Notice(text: widget.controller.error!),
          const SizedBox(height: 14),
        ],
        if (!config.hasAnyLoginMode)
          const _UnavailableState(text: '当前后台未开放登录方式')
        else ...[
          if (config.passwordLoginEnabled && config.mobileLoginEnabled) ...[
            _LoginModeTabs(
              selected: mode,
              onChanged: (value) {
                setState(() => _loginMode = value);
                widget.controller.clearError();
              },
            ),
            const SizedBox(height: 20),
          ],
          Form(
            key: _loginFormKey,
            child: Column(
              children: [
                _AuthInput(
                  controller: _loginAccount,
                  icon: mode == _LoginMode.mobile
                      ? Icons.phone_iphone
                      : Icons.person_outline,
                  hintText: mode == _LoginMode.mobile ? '请输入手机号' : '请输入用户名或手机号',
                  keyboardType: mode == _LoginMode.mobile
                      ? TextInputType.phone
                      : TextInputType.text,
                  textInputAction: TextInputAction.next,
                  autofillHints: mode == _LoginMode.mobile
                      ? const [AutofillHints.telephoneNumber]
                      : const [AutofillHints.username],
                  validator: (value) => mode == _LoginMode.mobile
                      ? _required(value, min: 4, message: '请输入手机号')
                      : _required(value, min: 2, message: '请输入账号'),
                ),
                const SizedBox(height: 14),
                if (mode == _LoginMode.password)
                  _AuthInput(
                    controller: _loginPassword,
                    icon: Icons.lock_outline,
                    hintText: '请输入密码',
                    obscureText: !_showLoginPassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    validator: (value) =>
                        _required(value, min: 4, message: '请输入密码'),
                    suffix: IconButton(
                      tooltip: _showLoginPassword ? '隐藏密码' : '显示密码',
                      onPressed: () => setState(
                        () => _showLoginPassword = !_showLoginPassword,
                      ),
                      icon: Icon(
                        _showLoginPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: _authMuted,
                        size: 20,
                      ),
                    ),
                  )
                else
                  _AuthInput(
                    controller: _loginCode,
                    icon: Icons.verified_user_outlined,
                    hintText: '请输入短信验证码',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    validator: (value) =>
                        _required(value, min: 4, message: '请输入验证码'),
                    suffix: TextButton(
                      onPressed: widget.controller.busy ? null : _sendLoginCode,
                      child: const Text('获取验证码'),
                    ),
                  ),
                if (_loginRequiresImageCaptcha(config, mode)) ...[
                  const SizedBox(height: 14),
                  _ImageCaptchaInput(
                    controller: _loginImageCaptcha,
                    type: 1,
                    revision: _loginCaptchaRevision,
                    loader: widget.controller.loadImageCaptcha,
                    onRefresh: () {
                      setState(() {
                        _loginImageCaptcha.clear();
                        _loginCaptchaRevision++;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 18),
                _AgreementRow(
                  accepted: _acceptedLoginAgreement,
                  onChanged: (value) {
                    setState(() => _acceptedLoginAgreement = value);
                    widget.controller.clearError();
                  },
                ),
                const SizedBox(height: 20),
                _PrimaryAuthButton(
                  text: widget.controller.busy ? '处理中' : '登录',
                  onPressed: widget.controller.busy ? null : _submitLogin,
                ),
                const SizedBox(height: 18),
                _LoginFooter(
                  registerEnabled:
                      config.registerEnabled && config.hasAnyRegisterMode,
                  onForgot: () => _showFeatureNotice('忘记密码'),
                  onRegister: () => _switchMode(false),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _registerView({required Key key}) {
    final config = widget.controller.authConfig;
    final modes = _registerModes(config);
    final mode = _activeRegisterMode(config);
    return ListView(
      key: key,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(_pageInset, 20, _pageInset, 28),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: '返回登录',
            onPressed: () => _switchMode(true),
            icon: const Icon(Icons.chevron_left, color: _authText, size: 32),
          ),
        ),
        const SizedBox(height: 38),
        const _AuthTitle(title: '注册', subtitle: '创建新账号，开启全新沟通体验'),
        const SizedBox(height: 30),
        if (widget.controller.error != null) ...[
          _Notice(text: widget.controller.error!),
          const SizedBox(height: 14),
        ],
        if (!config.registerEnabled || modes.isEmpty)
          const _UnavailableState(text: '当前后台未开放注册')
        else ...[
          if (modes.length > 1) ...[
            _RegisterModeTabs(
              modes: modes,
              selected: mode,
              onChanged: (value) {
                setState(() => _registerMode = value);
                widget.controller.clearError();
              },
            ),
            const SizedBox(height: 20),
          ],
          Form(
            key: _registerFormKey,
            child: Column(
              children: [
                ..._registerIdentityFields(mode, config),
                const SizedBox(height: 14),
                _AuthInput(
                  controller: _registerPassword,
                  icon: Icons.lock_outline,
                  hintText: '请设置登录密码（6-20位，含字母和数字）',
                  obscureText: !_showRegisterPassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: _passwordValidator,
                  suffix: IconButton(
                    tooltip: _showRegisterPassword ? '隐藏密码' : '显示密码',
                    onPressed: () => setState(
                      () => _showRegisterPassword = !_showRegisterPassword,
                    ),
                    icon: Icon(
                      _showRegisterPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: _authMuted,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _AuthInput(
                  controller: _registerConfirmPassword,
                  icon: Icons.lock_outline,
                  hintText: '请再次输入密码',
                  obscureText: !_showConfirmPassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: _confirmPasswordValidator,
                  suffix: IconButton(
                    tooltip: _showConfirmPassword ? '隐藏密码' : '显示密码',
                    onPressed: () => setState(
                      () => _showConfirmPassword = !_showConfirmPassword,
                    ),
                    icon: Icon(
                      _showConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: _authMuted,
                      size: 20,
                    ),
                  ),
                ),
                if (_registerRequiresImageCaptcha(config, mode)) ...[
                  const SizedBox(height: 14),
                  _ImageCaptchaInput(
                    controller: _registerImageCaptcha,
                    type: 2,
                    revision: _registerCaptchaRevision,
                    loader: widget.controller.loadImageCaptcha,
                    onRefresh: () {
                      setState(() {
                        _registerImageCaptcha.clear();
                        _registerCaptchaRevision++;
                      });
                    },
                  ),
                ],
                if (config.inviteCodeEnabled) ...[
                  const SizedBox(height: 14),
                  _AuthInput(
                    controller: _registerInviteCode,
                    icon: Icons.confirmation_number_outlined,
                    hintText: config.inviteCodeRequired ? '请输入邀请码' : '邀请码（选填）',
                    required: config.inviteCodeRequired,
                  ),
                ],
                const SizedBox(height: 18),
                _AgreementRow(
                  accepted: _acceptedRegisterAgreement,
                  onChanged: (value) {
                    setState(() => _acceptedRegisterAgreement = value);
                    widget.controller.clearError();
                  },
                ),
                const SizedBox(height: 20),
                _PrimaryAuthButton(
                  text: widget.controller.busy ? '处理中' : '注册',
                  onPressed: widget.controller.busy ? null : _submitRegister,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '已有账号？',
                      style: TextStyle(color: _authMuted, fontSize: 15),
                    ),
                    TextButton(
                      onPressed: () => _switchMode(true),
                      child: const Text(
                        '去登录',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _registerIdentityFields(
    _RegisterMode mode,
    AppAuthConfig config,
  ) {
    switch (mode) {
      case _RegisterMode.username:
        return [
          _AuthInput(
            controller: _registerUsername,
            icon: Icons.person_outline,
            hintText: '请输入用户名',
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newUsername],
            validator: (value) => _required(value, min: 2, message: '请输入用户名'),
          ),
        ];
      case _RegisterMode.mobile:
        return [
          _AuthInput(
            controller: _registerMobile,
            icon: Icons.phone_iphone,
            hintText: '请输入手机号',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            validator: (value) => _required(value, min: 4, message: '请输入手机号'),
          ),
          const SizedBox(height: 14),
          _AuthInput(
            controller: _registerCode,
            icon: Icons.verified_user_outlined,
            hintText: '请输入短信验证码',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            validator: (value) => _required(value, min: 4, message: '请输入验证码'),
            suffix: TextButton(
              onPressed: widget.controller.busy
                  ? null
                  : () => _sendRegisterCode(mode),
              child: const Text('获取验证码'),
            ),
          ),
        ];
      case _RegisterMode.email:
        return [
          _AuthInput(
            controller: _registerEmail,
            icon: Icons.email_outlined,
            hintText: '请输入邮箱',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            validator: _emailValidator,
          ),
          const SizedBox(height: 14),
          _AuthInput(
            controller: _registerCode,
            icon: Icons.verified_user_outlined,
            hintText: '请输入邮箱验证码',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            validator: (value) => _required(value, min: 4, message: '请输入验证码'),
            suffix: TextButton(
              onPressed: widget.controller.busy
                  ? null
                  : () => _sendRegisterCode(mode),
              child: const Text('获取验证码'),
            ),
          ),
        ];
    }
  }

  Future<void> _submitLogin() async {
    if (_authConfigLoading || _authConfigError.isNotEmpty) {
      _showSnack('请先完成登录配置同步');
      return;
    }
    final config = widget.controller.authConfig;
    if (!config.hasAnyLoginMode) {
      _showSnack('当前未开放登录方式');
      return;
    }
    if (!_acceptedLoginAgreement) {
      _showSnack('请先阅读并同意用户协议和隐私政策');
      return;
    }
    if (!_loginFormKey.currentState!.validate()) {
      return;
    }
    final mode = _activeLoginMode(config);
    final loginCaptcha = _loginRequiresImageCaptcha(config, mode)
        ? _loginImageCaptcha.text.trim()
        : '';
    try {
      if (mode == _LoginMode.password) {
        await widget.controller.login(
          username: _loginAccount.text.trim(),
          password: _loginPassword.text,
          captcha: loginCaptcha,
        );
      } else {
        await widget.controller.loginWithMobile(
          mobile: _loginAccount.text.trim(),
          code: _loginCode.text.trim(),
          captcha: loginCaptcha,
        );
      }
    } catch (_) {
      if (loginCaptcha.isNotEmpty && mounted) {
        setState(_refreshLoginCaptchaInput);
      }
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  Future<void> _submitRegister() async {
    if (_authConfigLoading || _authConfigError.isNotEmpty) {
      _showSnack('请先完成登录配置同步');
      return;
    }
    final config = widget.controller.authConfig;
    if (!config.registerEnabled || _registerModes(config).isEmpty) {
      _showSnack('当前未开放注册');
      return;
    }
    if (!_acceptedRegisterAgreement) {
      _showSnack('请先阅读并同意用户协议和隐私政策');
      return;
    }
    if (!_registerFormKey.currentState!.validate()) {
      return;
    }
    final mode = _activeRegisterMode(config);
    final username = mode == _RegisterMode.username
        ? _registerUsername.text.trim()
        : _randomRegisterUsername();
    final mobile = mode == _RegisterMode.mobile
        ? _registerMobile.text.trim()
        : '';
    final email = mode == _RegisterMode.email ? _registerEmail.text.trim() : '';
    final captcha = switch (mode) {
      _RegisterMode.username =>
        config.registerCaptchaEnabled ? _registerImageCaptcha.text.trim() : '',
      _RegisterMode.mobile || _RegisterMode.email => _registerCode.text.trim(),
    };
    try {
      await widget.controller.register(
        username: username,
        password: _registerPassword.text,
        nickname: _randomRegisterNickname(),
        email: email,
        mobile: mobile,
        captcha: captcha,
        inviteCode: config.inviteCodeEnabled
            ? _registerInviteCode.text.trim()
            : '',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLogin = true;
        _loginMode = mode == _RegisterMode.mobile && config.mobileLoginEnabled
            ? _LoginMode.mobile
            : _LoginMode.password;
        _loginAccount.text = _loginMode == _LoginMode.mobile
            ? mobile
            : username;
      });
      _showSnack(mode == _RegisterMode.username ? '注册成功，请登录' : '注册成功，请登录');
    } catch (_) {
      if (_registerRequiresImageCaptcha(config, mode) && mounted) {
        setState(_refreshRegisterCaptchaInput);
      }
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  Future<void> _sendRegisterCode(_RegisterMode mode) async {
    try {
      if (mode == _RegisterMode.mobile) {
        final mobile = _registerMobile.text.trim();
        if (mobile.isEmpty) {
          _showSnack('请先填写手机号');
          return;
        }
        final captcha = _registerImageCaptcha.text.trim();
        if (captcha.isEmpty) {
          _showSnack('请先输入图片验证码');
          return;
        }
        await widget.controller.sendMobileCode(
          mobile,
          type: 2,
          captcha: captcha,
        );
      } else if (mode == _RegisterMode.email) {
        final email = _registerEmail.text.trim();
        if (email.isEmpty) {
          _showSnack('请先填写邮箱');
          return;
        }
        final captcha = _registerImageCaptcha.text.trim();
        if (captcha.isEmpty) {
          _showSnack('请先输入图片验证码');
          return;
        }
        await widget.controller.sendEmailCode(email, type: 1, captcha: captcha);
      } else {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(_refreshRegisterCaptchaInput);
      _showSnack('验证码已发送');
    } catch (_) {
      if (mounted) {
        setState(_refreshRegisterCaptchaInput);
      }
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  Future<void> _sendLoginCode() async {
    final account = _loginAccount.text.trim();
    if (account.isEmpty) {
      _showSnack('请先填写手机号');
      return;
    }
    final captcha = _loginImageCaptcha.text.trim();
    if (captcha.isEmpty) {
      _showSnack('请先输入图片验证码');
      return;
    }
    try {
      await widget.controller.sendMobileCode(
        account,
        type: 1,
        captcha: captcha,
      );
      if (!mounted) {
        return;
      }
      _showSnack('验证码已发送');
    } catch (_) {
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  _LoginMode _activeLoginMode(AppAuthConfig config) {
    if (_loginMode == _LoginMode.mobile && config.mobileLoginEnabled) {
      return _LoginMode.mobile;
    }
    if (_loginMode == _LoginMode.password && config.passwordLoginEnabled) {
      return _LoginMode.password;
    }
    if (config.passwordLoginEnabled) {
      return _LoginMode.password;
    }
    return _LoginMode.mobile;
  }

  bool _loginRequiresImageCaptcha(AppAuthConfig config, _LoginMode mode) {
    return config.loginCaptchaEnabled || mode == _LoginMode.mobile;
  }

  bool _registerRequiresImageCaptcha(AppAuthConfig config, _RegisterMode mode) {
    return (mode == _RegisterMode.username && config.registerCaptchaEnabled) ||
        mode == _RegisterMode.mobile ||
        mode == _RegisterMode.email;
  }

  void _refreshLoginCaptchaInput() {
    _loginImageCaptcha.clear();
    _loginCaptchaRevision++;
  }

  void _refreshRegisterCaptchaInput() {
    _registerImageCaptcha.clear();
    _registerCaptchaRevision++;
  }

  List<_RegisterMode> _registerModes(AppAuthConfig config) {
    if (!config.registerEnabled) {
      return const [];
    }
    return [
      if (config.usernameRegisterEnabled) _RegisterMode.username,
      if (config.mobileRegisterEnabled) _RegisterMode.mobile,
      if (config.emailRegisterEnabled) _RegisterMode.email,
    ];
  }

  _RegisterMode _activeRegisterMode(AppAuthConfig config) {
    final modes = _registerModes(config);
    if (modes.contains(_registerMode)) {
      return _registerMode;
    }
    return modes.isEmpty ? _RegisterMode.username : modes.first;
  }

  void _switchMode(bool login) {
    setState(() => _isLogin = login);
    widget.controller.clearError();
  }

  Future<void> _loadAuthConfig() async {
    setState(() {
      _authConfigLoading = true;
      _authConfigError = '';
    });
    final ok = await widget.controller.refreshAppInfoForAuth();
    if (!mounted) {
      return;
    }
    setState(() {
      _authConfigLoading = false;
      _authConfigError = ok ? '' : '无法读取后台登录配置，请检查网络后重试';
    });
  }

  void _showFeatureNotice(String feature) {
    _showSnack('$feature暂未开放');
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    showBimSnackBar(context, message);
  }

  String _randomRegisterUsername() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final suffix = List<String>.generate(
      8,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return 'bim_${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  String _randomRegisterNickname() {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = Random.secure();
    final suffix = List<String>.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return 'BIM用户$suffix';
  }

  String? _required(
    String? value, {
    required int min,
    required String message,
  }) {
    final text = value?.trim() ?? '';
    if (text.length < min) {
      return message;
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return '请输入邮箱';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return '邮箱格式不正确';
    }
    return null;
  }

  String? _passwordValidator(String? value) {
    final text = value ?? '';
    if (text.length < 6 || text.length > 20) {
      return '请输入 6-20 位密码';
    }
    final hasLetter = RegExp('[A-Za-z]').hasMatch(text);
    final hasNumber = RegExp(r'\d').hasMatch(text);
    if (!hasLetter || !hasNumber) {
      return '密码需包含字母和数字';
    }
    return null;
  }

  String? _confirmPasswordValidator(String? value) {
    final text = value ?? '';
    if (text.isEmpty) {
      return '请再次输入密码';
    }
    if (text != _registerPassword.text) {
      return '两次输入的密码不一致';
    }
    return null;
  }

  double get _pageInset {
    final width = MediaQuery.sizeOf(context).width;
    return width < 360 ? 20 : 28;
  }
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand({required this.appInfo});

  final AppInfo? appInfo;

  @override
  Widget build(BuildContext context) {
    final icon = appInfo?.icon ?? '';
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _authBlue,
            borderRadius: BorderRadius.circular(BimRadius.md),
          ),
          child: icon.isEmpty
              ? const Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 30,
                )
              : Image.network(
                  icon,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            appInfo?.name.isNotEmpty == true ? appInfo!.name : 'BIM',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _authText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthTitle extends StatelessWidget {
  const _AuthTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _authText,
            fontSize: BimTypography.authTitle,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        Text(subtitle, style: const TextStyle(color: _authMuted, fontSize: 16)),
      ],
    );
  }
}

class _LoginModeTabs extends StatelessWidget {
  const _LoginModeTabs({required this.selected, required this.onChanged});

  final _LoginMode selected;
  final ValueChanged<_LoginMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return BimSegmentedControl<_LoginMode>(
      selected: selected,
      options: const [
        BimSegmentOption(value: _LoginMode.password, label: '密码登录'),
        BimSegmentOption(value: _LoginMode.mobile, label: '验证码登录'),
      ],
      onChanged: onChanged,
    );
  }
}

class _RegisterModeTabs extends StatelessWidget {
  const _RegisterModeTabs({
    required this.modes,
    required this.selected,
    required this.onChanged,
  });

  final List<_RegisterMode> modes;
  final _RegisterMode selected;
  final ValueChanged<_RegisterMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return BimSegmentedControl<_RegisterMode>(
      selected: selected,
      options: [
        for (final mode in modes)
          BimSegmentOption(value: mode, label: _registerModeLabel(mode)),
      ],
      onChanged: onChanged,
    );
  }

  String _registerModeLabel(_RegisterMode mode) {
    return switch (mode) {
      _RegisterMode.username => '用户名注册',
      _RegisterMode.mobile => '手机号注册',
      _RegisterMode.email => '邮箱注册',
    };
  }
}

class _AuthInput extends StatelessWidget {
  const _AuthInput({
    required this.controller,
    required this.icon,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.required = true,
    this.suffix,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final bool required;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _authFill,
        border: Border.all(color: _authBorder),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        validator:
            validator ??
            (required
                ? (value) => (value?.trim().isEmpty ?? true) ? '不能为空' : null
                : null),
        style: const TextStyle(
          color: _authText,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: _authMuted, fontSize: 15),
          prefixIcon: Icon(icon, color: _authMuted, size: 21),
          suffixIcon: suffix,
          suffixIconConstraints: const BoxConstraints(minHeight: 48),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}

class _ImageCaptchaInput extends StatefulWidget {
  const _ImageCaptchaInput({
    required this.controller,
    required this.type,
    required this.revision,
    required this.loader,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final int type;
  final int revision;
  final Future<ImageCaptcha> Function({required int type}) loader;
  final VoidCallback onRefresh;

  @override
  State<_ImageCaptchaInput> createState() => _ImageCaptchaInputState();
}

class _ImageCaptchaInputState extends State<_ImageCaptchaInput> {
  late Future<ImageCaptcha> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader(type: widget.type);
  }

  @override
  void didUpdateWidget(_ImageCaptchaInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type ||
        oldWidget.revision != widget.revision) {
      _future = widget.loader(type: widget.type);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _authFill,
        border: Border.all(color: _authBorder),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.verified_user_outlined, color: _authMuted, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: widget.controller,
              keyboardType: TextInputType.text,
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '请输入图形验证码' : null,
              style: const TextStyle(
                color: _authText,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText: '请输入图形验证码',
                hintStyle: TextStyle(color: _authMuted, fontSize: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FutureBuilder<ImageCaptcha>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  width: 82,
                  height: 34,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return const SizedBox(
                  width: 82,
                  height: 34,
                  child: Center(
                    child: Text(
                      '获取失败',
                      style: TextStyle(color: _authDanger, fontSize: 12),
                    ),
                  ),
                );
              }
              return _CaptchaPreview(captcha: snapshot.data);
            },
          ),
          IconButton(
            tooltip: '换一张',
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh, color: _authMuted, size: 18),
          ),
        ],
      ),
    );
  }
}

class _CaptchaPreview extends StatelessWidget {
  const _CaptchaPreview({required this.captcha});

  final ImageCaptcha? captcha;

  @override
  Widget build(BuildContext context) {
    final image = captcha?.image.trim() ?? '';
    final child = _imageWidget(image);
    return ClipRRect(
      borderRadius: BorderRadius.circular(BimRadius.sm),
      child: ColoredBox(
        color: BimColors.fill,
        child: SizedBox(
          width: 82,
          height: 34,
          child:
              child ??
              const Center(
                child: Text(
                  '验证码',
                  style: TextStyle(color: _authMuted, fontSize: 12),
                ),
              ),
        ),
      ),
    );
  }

  Widget? _imageWidget(String image) {
    if (image.isEmpty) {
      return null;
    }
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(image, fit: BoxFit.cover);
    }
    final bytes = _decodeImageBytes(image);
    if (bytes == null) {
      return null;
    }
    return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
  }

  Uint8List? _decodeImageBytes(String image) {
    final text = image.startsWith('data:image')
        ? image.substring(image.indexOf(',') + 1)
        : image;
    try {
      return base64Decode(text);
    } catch (_) {
      return null;
    }
  }
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({required this.accepted, required this.onChanged});

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: accepted,
            onChanged: (value) => onChanged(value ?? false),
            side: const BorderSide(color: _authBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            activeColor: _authBlue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 7),
        const Expanded(
          child: Text.rich(
            TextSpan(
              text: '我已阅读并同意 ',
              children: [
                TextSpan(
                  text: '《用户协议》',
                  style: TextStyle(color: _authBlue),
                ),
                TextSpan(text: ' 和 '),
                TextSpan(
                  text: '《隐私政策》',
                  style: TextStyle(color: _authBlue),
                ),
              ],
            ),
            style: TextStyle(color: _authMuted, fontSize: 14, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _PrimaryAuthButton extends StatelessWidget {
  const _PrimaryAuthButton({required this.text, required this.onPressed});

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _authBlue,
          disabledBackgroundColor: const Color(0xff9bc8ff),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BimRadius.sm),
          ),
          textStyle: const TextStyle(
            fontSize: BimTypography.body,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: Text(text),
      ),
    );
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter({
    required this.registerEnabled,
    required this.onForgot,
    required this.onRegister,
  });

  final bool registerEnabled;
  final VoidCallback onForgot;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton(
          onPressed: onForgot,
          style: TextButton.styleFrom(
            foregroundColor: _authBlue,
            padding: EdgeInsets.zero,
          ),
          child: const Text('忘记密码?'),
        ),
        const Spacer(),
        if (registerEnabled)
          TextButton(
            onPressed: onRegister,
            style: TextButton.styleFrom(
              foregroundColor: _authBlue,
              padding: EdgeInsets.zero,
            ),
            child: const Text('新用户注册'),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return BimNoticeBanner(text: text, tone: BimNoticeTone.error);
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _authSurface,
        border: Border.all(color: _authBorder),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _authMuted, fontSize: 15),
      ),
    );
  }
}

class _AuthLoadingState extends StatelessWidget {
  const _AuthLoadingState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: _authSurface,
        border: Border.all(color: _authBorder),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _authMuted, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthConfigLoadingForm extends StatelessWidget {
  const _AuthConfigLoadingForm();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _AuthModeSkeleton(),
        const SizedBox(height: 20),
        const _AuthSkeletonField(icon: Icons.person_outline, text: '账号'),
        const SizedBox(height: 14),
        const _AuthSkeletonField(icon: Icons.lock_outline, text: '密码或验证码'),
        const SizedBox(height: 14),
        const _AuthLoadingState(text: '正在同步登录方式和验证码规则'),
        const SizedBox(height: 18),
        _PrimaryAuthButton(text: '登录', onPressed: null),
        const SizedBox(height: 18),
        Row(
          children: [
            TextButton(onPressed: null, child: const Text('忘记密码?')),
            const Spacer(),
            TextButton(onPressed: null, child: const Text('新用户注册')),
          ],
        ),
      ],
    );
  }
}

class _AuthModeSkeleton extends StatelessWidget {
  const _AuthModeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _authFill,
        border: Border.all(color: _authBorder),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Row(
        children: const [
          Expanded(child: _AuthSkeletonPill(text: '密码登录')),
          SizedBox(width: 4),
          Expanded(child: _AuthSkeletonPill(text: '验证码登录')),
        ],
      ),
    );
  }
}

class _AuthSkeletonPill extends StatelessWidget {
  const _AuthSkeletonPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfff1f5f9),
        borderRadius: BorderRadius.circular(BimRadius.xs),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: _authMuted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AuthSkeletonField extends StatelessWidget {
  const _AuthSkeletonField({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _authSurface,
        border: Border.all(color: _authBorder),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, color: _authMuted, size: 20),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              color: _authMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    );
  }
}
