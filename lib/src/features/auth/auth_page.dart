import 'package:flutter/material.dart';

import '../../app/session_controller.dart';

const _authBlue = Color(0xff1478ff);
const _authText = Color(0xff101216);
const _authMuted = Color(0xff7d8490);
const _authBorder = Color(0xffeceff5);
const _authDanger = Color(0xffc62828);

class AuthPage extends StatefulWidget {
  const AuthPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  var _isLogin = true;
  var _loginByPassword = true;
  var _acceptedLoginAgreement = false;
  var _acceptedRegisterAgreement = false;
  var _showLoginPassword = false;
  var _showRegisterPassword = false;
  var _showConfirmPassword = false;

  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _loginUsername = TextEditingController();
  final _loginPassword = TextEditingController();
  final _loginCaptcha = TextEditingController();
  final _registerUsername = TextEditingController();
  final _registerPassword = TextEditingController();
  final _registerConfirmPassword = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerMobile = TextEditingController();
  final _registerCaptcha = TextEditingController();
  final _registerInviteCode = TextEditingController();

  @override
  void dispose() {
    _loginUsername.dispose();
    _loginPassword.dispose();
    _loginCaptcha.dispose();
    _registerUsername.dispose();
    _registerPassword.dispose();
    _registerConfirmPassword.dispose();
    _registerEmail.dispose();
    _registerMobile.dispose();
    _registerCaptcha.dispose();
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
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xffffffff), Color(0xfff8fbff)],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  const Positioned(
                    right: -24,
                    bottom: -18,
                    child: _BubbleMark(size: 142, opacity: 0.34),
                  ),
                  const Positioned(
                    right: 96,
                    bottom: -8,
                    child: _BubbleMark(size: 82, opacity: 0.23),
                  ),
                  _isLogin ? _loginView() : _registerView(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loginView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 86, 28, 28),
      children: [
        const _AppIcon(),
        const SizedBox(height: 26),
        const Text(
          '登录',
          style: TextStyle(
            color: _authText,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '欢迎回来，登录后继续畅聊',
          style: TextStyle(color: _authMuted, fontSize: 16),
        ),
        const SizedBox(height: 46),
        _LoginModeTabs(
          passwordMode: _loginByPassword,
          onChanged: (value) {
            setState(() => _loginByPassword = value);
            widget.controller.clearError();
          },
        ),
        const SizedBox(height: 24),
        if (widget.controller.error != null) ...[
          _Notice(text: widget.controller.error!),
          const SizedBox(height: 14),
        ],
        Form(
          key: _loginFormKey,
          child: Column(
            children: [
              _AuthInput(
                controller: _loginUsername,
                icon: Icons.phone_iphone,
                hintText: '请输入手机号',
                keyboardType: TextInputType.phone,
                validator: (value) => _required(value, min: 4),
              ),
              const SizedBox(height: 16),
              _AuthInput(
                controller: _loginPassword,
                icon: Icons.lock_outline,
                hintText: _loginByPassword ? '请输入密码' : '请输入验证码',
                obscureText: _loginByPassword && !_showLoginPassword,
                validator: (value) => _required(value, min: 4),
                suffix: _loginByPassword
                    ? IconButton(
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
                      )
                    : TextButton(
                        onPressed: widget.controller.busy
                            ? null
                            : _sendLoginCode,
                        child: const Text('获取验证码'),
                      ),
              ),
              const SizedBox(height: 16),
              _CaptchaInput(controller: _registerCaptcha),
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
              Row(
                children: [
                  TextButton(
                    onPressed: () => _showFeatureNotice('忘记密码'),
                    style: TextButton.styleFrom(
                      foregroundColor: _authBlue,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('忘记密码?'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _switchMode(false),
                    style: TextButton.styleFrom(
                      foregroundColor: _authBlue,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('新用户注册'),
                  ),
                ],
              ),
              const SizedBox(height: 78),
              const _OtherLoginDivider(),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ThirdPartyButton(
                    icon: Icons.wechat,
                    label: '微信登录',
                    color: const Color(0xff12b853),
                    onTap: () => _showFeatureNotice('微信登录'),
                  ),
                  const SizedBox(width: 54),
                  _ThirdPartyButton(
                    icon: Icons.person,
                    label: 'QQ登录',
                    color: _authBlue,
                    onTap: () => _showFeatureNotice('QQ登录'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _registerView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 28),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: '返回登录',
            onPressed: () => _switchMode(true),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            icon: const Icon(Icons.chevron_left, color: _authText, size: 32),
          ),
        ),
        const SizedBox(height: 46),
        const Text(
          '注册',
          style: TextStyle(
            color: _authText,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '创建新账号，开启全新沟通体验',
          style: TextStyle(color: _authMuted, fontSize: 16),
        ),
        const SizedBox(height: 34),
        if (widget.controller.error != null) ...[
          _Notice(text: widget.controller.error!),
          const SizedBox(height: 14),
        ],
        Form(
          key: _registerFormKey,
          child: Column(
            children: [
              _AuthInput(
                controller: _registerMobile,
                icon: Icons.phone_iphone,
                hintText: '请输入手机号',
                keyboardType: TextInputType.phone,
                required: false,
              ),
              const SizedBox(height: 16),
              _AuthInput(
                controller: _registerCaptcha,
                icon: Icons.verified_user_outlined,
                hintText: '请输入验证码',
                required: false,
                suffix: TextButton(
                  onPressed: widget.controller.busy ? null : _sendRegisterCode,
                  child: const Text('获取验证码'),
                ),
              ),
              const SizedBox(height: 16),
              _AuthInput(
                controller: _registerPassword,
                icon: Icons.lock_outline,
                hintText: '请设置登录密码（6-20位，含字母和数字）',
                obscureText: !_showRegisterPassword,
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
              const SizedBox(height: 16),
              _AuthInput(
                controller: _registerConfirmPassword,
                icon: Icons.lock_outline,
                hintText: '请再次输入密码',
                obscureText: !_showConfirmPassword,
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
              const SizedBox(height: 16),
              _CaptchaInput(controller: _loginCaptcha),
              const SizedBox(height: 16),
              _AuthInput(
                controller: _registerUsername,
                icon: Icons.person_outline,
                hintText: '用户名（可选，默认使用手机号）',
                required: false,
              ),
              const SizedBox(height: 16),
              _AuthInput(
                controller: _registerEmail,
                icon: Icons.email_outlined,
                hintText: '邮箱（可选）',
                keyboardType: TextInputType.emailAddress,
                required: false,
              ),
              const SizedBox(height: 16),
              _AuthInput(
                controller: _registerInviteCode,
                icon: Icons.confirmation_number_outlined,
                hintText: '邀请码（可选）',
                required: false,
              ),
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
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '已有账号？',
                    style: TextStyle(color: _authMuted, fontSize: 15),
                  ),
                  TextButton(
                    onPressed: () => _switchMode(true),
                    style: TextButton.styleFrom(
                      foregroundColor: _authBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                    ),
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
    );
  }

  Future<void> _submitLogin() async {
    if (!_acceptedLoginAgreement) {
      _showSnack('请先阅读并同意用户协议和隐私政策');
      return;
    }
    if (!_loginFormKey.currentState!.validate()) {
      return;
    }
    try {
      await widget.controller.login(
        username: _loginUsername.text.trim(),
        password: _loginPassword.text,
        captcha: _loginCaptcha.text.trim(),
      );
    } catch (_) {
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  Future<void> _submitRegister() async {
    if (!_acceptedRegisterAgreement) {
      _showSnack('请先阅读并同意用户协议和隐私政策');
      return;
    }
    if (!_registerFormKey.currentState!.validate()) {
      return;
    }
    final mobile = _registerMobile.text.trim();
    final email = _registerEmail.text.trim();
    final username = _registerUsername.text.trim().isNotEmpty
        ? _registerUsername.text.trim()
        : mobile;
    if (username.isEmpty) {
      _showSnack('请填写手机号或用户名');
      return;
    }
    try {
      await widget.controller.register(
        username: username,
        password: _registerPassword.text,
        email: email,
        mobile: mobile,
        captcha: _registerCaptcha.text.trim(),
        inviteCode: _registerInviteCode.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLogin = true;
        _loginUsername.text = username;
      });
      _showSnack('注册成功，请登录');
    } catch (_) {
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  Future<void> _sendRegisterCode() async {
    final email = _registerEmail.text.trim();
    final mobile = _registerMobile.text.trim();
    try {
      if (mobile.isNotEmpty) {
        await widget.controller.sendMobileCode(mobile);
      } else if (email.isNotEmpty) {
        await widget.controller.sendEmailCode(email);
      } else {
        _showSnack('请先填写手机号或邮箱');
        return;
      }
      if (!mounted) {
        return;
      }
      _showSnack('验证码已发送');
    } catch (_) {
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  Future<void> _sendLoginCode() async {
    final account = _loginUsername.text.trim();
    if (account.isEmpty) {
      _showSnack('请先填写手机号');
      return;
    }
    try {
      await widget.controller.sendMobileCode(account);
      if (!mounted) {
        return;
      }
      _showSnack('验证码已发送');
    } catch (_) {
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  void _switchMode(bool login) {
    setState(() => _isLogin = login);
    widget.controller.clearError();
  }

  void _showFeatureNotice(String feature) {
    _showSnack('$feature暂未开放');
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _required(String? value, {required int min}) {
    final text = value?.trim() ?? '';
    if (text.length < min) {
      return '至少 $min 个字符';
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
}

class _AppIcon extends StatelessWidget {
  const _AppIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _authBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.chat_bubble_rounded,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _LoginModeTabs extends StatelessWidget {
  const _LoginModeTabs({required this.passwordMode, required this.onChanged});

  final bool passwordMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LoginModeButton(
            text: '密码登录',
            selected: passwordMode,
            onTap: () => onChanged(true),
          ),
        ),
        Expanded(
          child: _LoginModeButton(
            text: '验证码登录',
            selected: !passwordMode,
            onTap: () => onChanged(false),
          ),
        ),
      ],
    );
  }
}

class _LoginModeButton extends StatelessWidget {
  const _LoginModeButton({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: TextStyle(
                color: selected ? _authBlue : _authMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Container(
              width: 22,
              height: 2,
              color: selected ? _authBlue : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthInput extends StatelessWidget {
  const _AuthInput({
    required this.controller,
    required this.icon,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.required = true,
    this.suffix,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final bool required;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _authBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
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

class _CaptchaInput extends StatelessWidget {
  const _CaptchaInput({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _authBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.verified_user_outlined, color: _authMuted, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '请输入图形验证码',
                hintStyle: TextStyle(color: _authMuted, fontSize: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const _CaptchaCode(),
          TextButton.icon(
            onPressed: () {},
            style: TextButton.styleFrom(
              foregroundColor: Color(0xff4d5664),
              padding: const EdgeInsets.only(left: 4, right: 8),
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('换一张', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _CaptchaCode extends StatelessWidget {
  const _CaptchaCode();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CaptchaPainter(),
      child: const SizedBox(
        width: 76,
        height: 34,
        child: Center(
          child: Text(
            '74BK',
            style: TextStyle(
              color: Color(0xff16217b),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptchaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0x401478ff)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(4, size.height - 8),
      Offset(size.width - 4, 8),
      linePaint,
    );
    canvas.drawLine(
      Offset(12, 8),
      Offset(size.width - 10, size.height - 7),
      linePaint..color = const Color(0x4030b070),
    );
    final dotPaint = Paint()..color = const Color(0x30353a48);
    for (var i = 0; i < 14; i++) {
      canvas.drawCircle(
        Offset((i * 13) % size.width, (i * 7) % size.height),
        0.8,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
            side: const BorderSide(color: Color(0xffd9dde6)),
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
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _authBlue,
          disabledBackgroundColor: const Color(0xff9bc8ff),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        child: Text(text),
      ),
    );
  }
}

class _OtherLoginDivider extends StatelessWidget {
  const _OtherLoginDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: _authBorder)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '其他登录方式',
            style: TextStyle(color: _authMuted, fontSize: 13),
          ),
        ),
        Expanded(child: Divider(color: _authBorder)),
      ],
    );
  }
}

class _ThirdPartyButton extends StatelessWidget {
  const _ThirdPartyButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 9),
          Text(label, style: const TextStyle(color: _authMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _BubbleMark extends StatelessWidget {
  const _BubbleMark({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: size,
        height: size * 0.78,
        child: CustomPaint(painter: _BubblePainter()),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 0.8);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff5d91ff), Color(0x00ffffff)],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height * 0.4)),
      paint,
    );
    final tail = Path()
      ..moveTo(size.width * 0.63, size.height * 0.68)
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height,
        size.width * 0.42,
        size.height * 0.85,
      )
      ..close();
    canvas.drawPath(tail, paint);
    final dotPaint = Paint()..color = const Color(0xff3e8bff);
    for (final dx in [0.38, 0.5, 0.62]) {
      canvas.drawCircle(
        Offset(size.width * dx, size.height * 0.42),
        size.width * 0.045,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xfffff2f2),
        border: Border.all(color: const Color(0xffffd6d6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(color: _authDanger)),
    );
  }
}
