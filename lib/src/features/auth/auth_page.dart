import 'package:flutter/material.dart';

import '../../app/session_controller.dart';
import '../../core/app_config.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  var _isLogin = true;
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _loginUsername = TextEditingController();
  final _loginPassword = TextEditingController();
  final _loginCaptcha = TextEditingController();
  final _registerUsername = TextEditingController();
  final _registerPassword = TextEditingController();
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
          appBar: AppBar(title: const Text(AppConfig.appName)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text(
                  _isLogin ? '登录' : '注册',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                _ModeSwitch(
                  isLogin: _isLogin,
                  onChanged: (value) {
                    setState(() => _isLogin = value);
                    widget.controller.clearError();
                  },
                ),
                const SizedBox(height: 22),
                if (widget.controller.error != null) ...[
                  _Notice(text: widget.controller.error!),
                  const SizedBox(height: 16),
                ],
                if (_isLogin) _loginForm() else _registerForm(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _loginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          _TextField(
            controller: _loginUsername,
            label: '账号',
            validator: (value) => _required(value, min: 4),
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _loginPassword,
            label: '密码',
            obscureText: true,
            validator: (value) => _required(value, min: 4),
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _loginCaptcha,
            label: '图片验证码',
            required: false,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.controller.busy ? null : _submitLogin,
            child: Text(widget.controller.busy ? '处理中' : '登录'),
          ),
        ],
      ),
    );
  }

  Widget _registerForm() {
    return Form(
      key: _registerFormKey,
      child: Column(
        children: [
          _TextField(
            controller: _registerUsername,
            label: '账号',
            validator: (value) => _required(value, min: 5),
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _registerPassword,
            label: '密码',
            obscureText: true,
            validator: (value) => _required(value, min: 5),
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _registerEmail,
            label: '邮箱',
            keyboardType: TextInputType.emailAddress,
            required: false,
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _registerMobile,
            label: '手机号',
            keyboardType: TextInputType.phone,
            required: false,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TextField(
                  controller: _registerCaptcha,
                  label: '验证码',
                  required: false,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 112,
                child: OutlinedButton(
                  onPressed: widget.controller.busy ? null : _sendRegisterCode,
                  child: const Text('获取验证码'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _registerInviteCode,
            label: '邀请码',
            required: false,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.controller.busy ? null : _submitRegister,
            child: Text(widget.controller.busy ? '处理中' : '注册'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitLogin() async {
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
    if (!_registerFormKey.currentState!.validate()) {
      return;
    }
    try {
      await widget.controller.register(
        username: _registerUsername.text.trim(),
        password: _registerPassword.text,
        email: _registerEmail.text.trim(),
        mobile: _registerMobile.text.trim(),
        captcha: _registerCaptcha.text.trim(),
        inviteCode: _registerInviteCode.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isLogin = true;
        _loginUsername.text = _registerUsername.text.trim();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('注册成功，请登录')));
    } catch (_) {
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  Future<void> _sendRegisterCode() async {
    final email = _registerEmail.text.trim();
    final mobile = _registerMobile.text.trim();
    try {
      if (email.isNotEmpty) {
        await widget.controller.sendEmailCode(email);
      } else if (mobile.isNotEmpty) {
        await widget.controller.sendMobileCode(mobile);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先填写邮箱或手机号')));
        return;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证码已发送')));
    } catch (_) {
      // 错误已经写入 controller，页面通过 Notice 展示。
    }
  }

  String? _required(String? value, {required int min}) {
    final text = value?.trim() ?? '';
    if (text.length < min) {
      return '至少 $min 个字符';
    }
    return null;
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.isLogin, required this.onChanged});

  final bool isLogin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffd7dce2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              text: '登录',
              selected: isLogin,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _ModeButton(
              text: '注册',
              selected: !isLogin,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
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
      child: Container(
        height: 44,
        color: selected ? const Color(0xff101114) : Colors.white,
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xff101114),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.required = true,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator:
          validator ??
          (required
              ? (value) => (value?.trim().isEmpty ?? true) ? '不能为空' : null
              : null),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xfffff2f2),
        border: Border.all(color: const Color(0xffffc9c9)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xffa40000))),
    );
  }
}
