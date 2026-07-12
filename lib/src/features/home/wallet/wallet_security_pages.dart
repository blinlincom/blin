part of 'package:bim/src/features/home/home_page.dart';

class WalletRechargePage extends StatefulWidget {
  const WalletRechargePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletRechargePage> createState() => _WalletRechargePageState();
}

class _WalletRechargePageState extends State<WalletRechargePage> {
  final _km = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.rechargeWalletByKm(_km.text.trim());
      if (mounted) {
        _showWalletMessage(context, '充值成功');
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WalletFormScaffold(
      title: '充值',
      children: [
        _WalletTextField(controller: _km, label: '卡密', hint: '输入充值卡密'),
        const SizedBox(height: 22),
        _WalletPrimaryButton(
          text: _busy ? '提交中...' : '确认充值',
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

class WalletWithdrawPage extends StatefulWidget {
  const WalletWithdrawPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletWithdrawPage> createState() => _WalletWithdrawPageState();
}

class _WalletWithdrawPageState extends State<WalletWithdrawPage> {
  final _amount = TextEditingController();
  final _account = TextEditingController();
  final _name = TextEditingController();
  final _remark = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _account.dispose();
    _name.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.withdrawWallet(
        amount: _amount.text.trim(),
        account: _account.text.trim(),
        name: _name.text.trim(),
        remark: _remark.text.trim(),
      );
      if (mounted) {
        _showWalletMessage(context, '提现申请已提交');
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WalletFormScaffold(
      title: '提现',
      children: [
        _WalletTextField(
          controller: _amount,
          label: '金额',
          hint: '0.00',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        _WalletTextField(controller: _name, label: '姓名', hint: '收款人姓名'),
        const SizedBox(height: 12),
        _WalletTextField(controller: _account, label: '账户', hint: '收款账户'),
        const SizedBox(height: 12),
        _WalletTextField(controller: _remark, label: '备注', hint: '选填'),
        const SizedBox(height: 22),
        _WalletPrimaryButton(
          text: _busy ? '提交中...' : '提交提现',
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

class WalletSecurityPage extends StatefulWidget {
  const WalletSecurityPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletSecurityPage> createState() => _WalletSecurityPageState();
}

class _WalletSecurityPageState extends State<WalletSecurityPage> {
  final _mobile = TextEditingController();
  final _mobileCode = TextEditingController();
  final _email = TextEditingController();
  final _emailCode = TextEditingController();
  final _captcha = TextEditingController();
  UserSecurityInfo? _info;
  _WalletSecurityEditMode _editMode = _WalletSecurityEditMode.none;
  bool _loading = true;
  bool _busy = false;
  bool _sendingMobile = false;
  bool _sendingEmail = false;
  int _captchaRevision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mobile.dispose();
    _mobileCode.dispose();
    _email.dispose();
    _emailCode.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final info = await widget.controller.loadUserSecurityInfo();
      if (mounted) {
        setState(() {
          _info = info;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _showWalletMessage(context, error.toString());
      }
    }
  }

  void _refreshCaptcha() {
    setState(() {
      _captcha.clear();
      _captchaRevision++;
    });
  }

  void _startEdit(_WalletSecurityEditMode mode) {
    final info = _info ?? const UserSecurityInfo();
    setState(() {
      _editMode = _editMode == mode ? _WalletSecurityEditMode.none : mode;
      _captcha.clear();
      _mobileCode.clear();
      _emailCode.clear();
      _captchaRevision++;
      if (mode == _WalletSecurityEditMode.mobile && info.mobileBound) {
        _mobile.text = info.mobile;
      }
      if (mode == _WalletSecurityEditMode.email && info.emailBound) {
        _email.text = info.email;
      }
    });
  }

  void _closeEdit() {
    setState(() {
      _editMode = _WalletSecurityEditMode.none;
      _captcha.clear();
      _mobileCode.clear();
      _emailCode.clear();
      _captchaRevision++;
    });
  }

  String _captchaValue() {
    final value = _captcha.text.trim();
    if (value.isEmpty) {
      _showWalletMessage(context, '请先输入图片验证码');
    }
    return value;
  }

  Future<void> _sendMobileCode() async {
    final mobile = _mobile.text.trim();
    if (mobile.isEmpty) {
      _showWalletMessage(context, '请输入手机号');
      return;
    }
    final captcha = _captchaValue();
    if (captcha.isEmpty) {
      return;
    }
    setState(() => _sendingMobile = true);
    try {
      await widget.controller.sendMobileBindCode(
        mobile: mobile,
        captcha: captcha,
      );
      if (mounted) {
        _showWalletMessage(context, '验证码已发送');
        _refreshCaptcha();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
        _refreshCaptcha();
      }
    } finally {
      if (mounted) {
        setState(() => _sendingMobile = false);
      }
    }
  }

  Future<void> _confirmMobile() async {
    final mobile = _mobile.text.trim();
    final code = _mobileCode.text.trim();
    if (mobile.isEmpty || code.isEmpty) {
      _showWalletMessage(context, '请输入手机号和验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final info = await widget.controller.confirmMobileBind(
        mobile: mobile,
        code: code,
      );
      if (mounted) {
        setState(() {
          _info = info;
          _mobileCode.clear();
          _editMode = _WalletSecurityEditMode.none;
        });
        _showWalletMessage(context, '手机号已绑定');
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _sendEmailCode() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showWalletMessage(context, '请输入邮箱');
      return;
    }
    final captcha = _captchaValue();
    if (captcha.isEmpty) {
      return;
    }
    setState(() => _sendingEmail = true);
    try {
      await widget.controller.sendEmailBindCode(email: email, captcha: captcha);
      if (mounted) {
        _showWalletMessage(context, '验证码已发送');
        _refreshCaptcha();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
        _refreshCaptcha();
      }
    } finally {
      if (mounted) {
        setState(() => _sendingEmail = false);
      }
    }
  }

  Future<void> _confirmEmail() async {
    final email = _email.text.trim();
    final code = _emailCode.text.trim();
    if (email.isEmpty || code.isEmpty) {
      _showWalletMessage(context, '请输入邮箱和验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final info = await widget.controller.confirmEmailBind(
        email: email,
        code: code,
      );
      if (mounted) {
        setState(() {
          _info = info;
          _emailCode.clear();
          _editMode = _WalletSecurityEditMode.none;
        });
        _showWalletMessage(context, '邮箱已绑定');
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info ?? const UserSecurityInfo();
    return _WalletFormScaffold(
      title: '账号安全',
      children: [
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          _WalletPlainNotice(
            icon: info.securityBound
                ? Icons.verified_user_outlined
                : Icons.info_outline,
            text: info.securityBound ? '已绑定安全验证方式' : '请至少绑定手机号或邮箱后再设置支付密码',
            color: info.securityBound
                ? BimColors.successText
                : const Color(0xffb45309),
            background: info.securityBound
                ? BimColors.successSurface
                : BimColors.warningSurface,
            border: info.securityBound
                ? BimColors.successBorder
                : BimColors.warningBorder,
          ),
        const SizedBox(height: 16),
        _WalletSecurityStatusRow(
          label: '手机号',
          value: info.mobileBound ? info.mobile : '未绑定',
          actionText: info.mobileBound ? '更换' : '绑定',
          selected: _editMode == _WalletSecurityEditMode.mobile,
          onTap: _loading
              ? null
              : () => _startEdit(_WalletSecurityEditMode.mobile),
        ),
        const SizedBox(height: 10),
        _WalletSecurityStatusRow(
          label: '邮箱',
          value: info.emailBound ? info.email : '未绑定',
          actionText: info.emailBound ? '更换' : '绑定',
          selected: _editMode == _WalletSecurityEditMode.email,
          onTap: _loading
              ? null
              : () => _startEdit(_WalletSecurityEditMode.email),
        ),
        if (_editMode != _WalletSecurityEditMode.none) ...[
          const SizedBox(height: 18),
          _WalletSecurityEditPanel(
            title: _editMode == _WalletSecurityEditMode.mobile
                ? (info.mobileBound ? '更换手机号' : '绑定手机号')
                : (info.emailBound ? '更换邮箱' : '绑定邮箱'),
            onClose: _closeEdit,
            children: [
              _WalletImageCaptchaInput(
                controller: _captcha,
                revision: _captchaRevision,
                loader: widget.controller.loadImageCaptcha,
                onRefresh: _refreshCaptcha,
              ),
              const SizedBox(height: 12),
              if (_editMode == _WalletSecurityEditMode.mobile) ...[
                _WalletTextField(
                  controller: _mobile,
                  label: '手机号',
                  hint: '请输入手机号',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                _WalletCodeSendField(
                  controller: _mobileCode,
                  label: '短信验证码',
                  hint: '请输入验证码',
                  buttonText: _sendingMobile ? '发送中...' : '获取短信验证码',
                  onPressed: _sendingMobile || _busy ? null : _sendMobileCode,
                ),
                const SizedBox(height: 12),
                _WalletPrimaryButton(
                  text: _busy ? '保存中...' : '保存手机号',
                  onPressed: _busy ? null : _confirmMobile,
                ),
              ] else ...[
                _WalletTextField(
                  controller: _email,
                  label: '邮箱',
                  hint: '请输入邮箱',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                _WalletCodeSendField(
                  controller: _emailCode,
                  label: '邮箱验证码',
                  hint: '请输入验证码',
                  buttonText: _sendingEmail ? '发送中...' : '获取邮箱验证码',
                  onPressed: _sendingEmail || _busy ? null : _sendEmailCode,
                ),
                const SizedBox(height: 12),
                _WalletPrimaryButton(
                  text: _busy ? '保存中...' : '保存邮箱',
                  onPressed: _busy ? null : _confirmEmail,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

enum _WalletSecurityEditMode { none, mobile, email }

class _WalletSecurityStatusRow extends StatelessWidget {
  const _WalletSecurityStatusRow({
    required this.label,
    required this.value,
    required this.actionText,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final String actionText;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surfaceColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Icon(
                label == '手机号'
                    ? Icons.phone_iphone_outlined
                    : Icons.email_outlined,
                color: selected ? _primaryColor : _secondaryTextColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                actionText,
                style: TextStyle(
                  color: selected ? _primaryColor : _secondaryTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                selected ? Icons.keyboard_arrow_up : Icons.chevron_right,
                color: selected ? _primaryColor : _mutedColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletSecurityEditPanel extends StatelessWidget {
  const _WalletSecurityEditPanel({
    required this.title,
    required this.onClose,
    required this.children,
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '收起',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                  color: _secondaryTextColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _WalletImageCaptchaInput extends StatefulWidget {
  const _WalletImageCaptchaInput({
    required this.controller,
    required this.revision,
    required this.loader,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final int revision;
  final Future<ImageCaptcha> Function({required int type}) loader;
  final VoidCallback onRefresh;

  @override
  State<_WalletImageCaptchaInput> createState() =>
      _WalletImageCaptchaInputState();
}

class _WalletImageCaptchaInputState extends State<_WalletImageCaptchaInput> {
  late Future<ImageCaptcha> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader(type: 3);
  }

  @override
  void didUpdateWidget(covariant _WalletImageCaptchaInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _future = widget.loader(type: 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _WalletTextField(
            controller: widget.controller,
            label: '图片验证码',
            hint: '请输入图片验证码',
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(width: 10),
        FutureBuilder<ImageCaptcha>(
          future: _future,
          builder: (context, snapshot) {
            final captcha = snapshot.data;
            return InkWell(
              onTap: widget.onRefresh,
              child: Container(
                width: 112,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  border: Border.all(color: _lightBorderColor),
                ),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _WalletCaptchaPreview(captcha: captcha),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WalletCaptchaPreview extends StatelessWidget {
  const _WalletCaptchaPreview({required this.captcha});

  final ImageCaptcha? captcha;

  @override
  Widget build(BuildContext context) {
    final image = captcha?.image.trim() ?? '';
    if (image.isEmpty) {
      return const Icon(Icons.refresh, color: _mutedColor, size: 20);
    }
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: image,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
      );
    }
    final raw = image.contains(',') ? image.split(',').last : image;
    try {
      return Image.memory(base64Decode(raw), fit: BoxFit.cover);
    } catch (_) {
      return const Icon(Icons.refresh, color: _mutedColor, size: 20);
    }
  }
}

class WalletPayPasswordPage extends StatefulWidget {
  const WalletPayPasswordPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletPayPasswordPage> createState() => _WalletPayPasswordPageState();
}

class _WalletPayPasswordPageState extends State<WalletPayPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  final _captcha = TextEditingController();
  bool _busy = false;
  bool _sendingCode = false;
  WalletBalance? _balance;
  String _method = '';
  int _captchaRevision = 0;

  @override
  void initState() {
    super.initState();
    _balance = widget.controller.walletBalance;
    final methods = _balance?.securityMethods ?? const <WalletSecurityMethod>[];
    if (methods.isNotEmpty) {
      _method = methods.first.method;
    }
    _loadBalance();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final balance = await widget.controller.loadWalletBalance(refresh: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _balance = balance;
        if (_method.isEmpty && balance.securityMethods.isNotEmpty) {
          _method = balance.securityMethods.first.method;
        }
      });
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    }
  }

  Future<void> _sendCode() async {
    if (_method.isEmpty) {
      _showWalletMessage(context, '请先绑定手机号、邮箱或安全验证方式');
      return;
    }
    final captcha = _captcha.text.trim();
    if (captcha.isEmpty) {
      _showWalletMessage(context, '请先输入图片验证码');
      return;
    }
    setState(() => _sendingCode = true);
    try {
      await widget.controller.sendWalletPayPasswordCode(
        verificationMethod: _method,
        captcha: captcha,
      );
      if (mounted) {
        _showWalletMessage(context, '验证码已发送');
        setState(() {
          _captcha.clear();
          _captchaRevision++;
        });
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
        setState(() {
          _captcha.clear();
          _captchaRevision++;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sendingCode = false);
      }
    }
  }

  Future<void> _submit() async {
    final value = _password.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      _showWalletMessage(context, '支付密码必须是6位数字');
      return;
    }
    if (value != _confirm.text.trim()) {
      _showWalletMessage(context, '两次密码不一致');
      return;
    }
    final code = _code.text.trim();
    if (code.isEmpty) {
      _showWalletMessage(context, '请输入验证码');
      return;
    }
    if (_method.isEmpty) {
      _showWalletMessage(context, '请先绑定手机号、邮箱或安全验证方式');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.setWalletPayPassword(
        password: value,
        verificationMethod: _method,
        verifyCode: code,
      );
      if (mounted) {
        _showWalletMessage(context, '设置成功');
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balance ?? widget.controller.walletBalance;
    final methods = balance?.securityMethods ?? const <WalletSecurityMethod>[];
    final canSet = methods.isNotEmpty && balance?.payPasswordLocked != true;
    return _WalletFormScaffold(
      title: '支付密码',
      children: [
        _WalletPayPasswordSecurityPanel(
          balance: balance,
          selectedMethod: _method,
          onChanged: methods.isEmpty
              ? null
              : (value) => setState(() => _method = value),
        ),
        if (methods.isEmpty) ...[
          const SizedBox(height: 12),
          _WalletPrimaryButton(
            text: '去绑定安全验证',
            onPressed: () => _push(
              context,
              WalletSecurityPage(controller: widget.controller),
            ).then((_) => _loadBalance()),
          ),
        ],
        const SizedBox(height: 14),
        _WalletTextField(
          controller: _password,
          label: '支付密码',
          hint: '6位数字',
          keyboardType: TextInputType.number,
          obscureText: true,
        ),
        const SizedBox(height: 12),
        _WalletTextField(
          controller: _confirm,
          label: '确认密码',
          hint: '再次输入',
          keyboardType: TextInputType.number,
          obscureText: true,
        ),
        const SizedBox(height: 12),
        _WalletImageCaptchaInput(
          controller: _captcha,
          revision: _captchaRevision,
          loader: widget.controller.loadImageCaptcha,
          onRefresh: () {
            setState(() {
              _captcha.clear();
              _captchaRevision++;
            });
          },
        ),
        const SizedBox(height: 12),
        _WalletCodeSendField(
          controller: _code,
          label: '验证码',
          hint: '安全验证码',
          buttonText: _sendingCode ? '发送中...' : '获取安全验证码',
          onPressed: canSet && !_sendingCode ? _sendCode : null,
        ),
        const SizedBox(height: 22),
        _WalletPrimaryButton(
          text: _busy ? '保存中...' : '保存',
          onPressed: canSet && !_busy ? _submit : null,
        ),
      ],
    );
  }
}

class _WalletPayPasswordSecurityPanel extends StatelessWidget {
  const _WalletPayPasswordSecurityPanel({
    required this.balance,
    required this.selectedMethod,
    required this.onChanged,
  });

  final WalletBalance? balance;
  final String selectedMethod;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final methods = balance?.securityMethods ?? const <WalletSecurityMethod>[];
    if (methods.isEmpty) {
      return const _WalletPlainNotice(
        icon: Icons.info_outline,
        text: '请先绑定手机号、邮箱或安全验证方式',
        color: Color(0xffb45309),
        background: Color(0xfffffbeb),
        border: Color(0xfffde68a),
      );
    }
    final value = methods.any((item) => item.method == selectedMethod)
        ? selectedMethod
        : methods.first.method;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: const InputDecoration(
            labelText: '安全验证',
            filled: true,
            fillColor: _surfaceColor,
            border: OutlineInputBorder(
              borderSide: BorderSide(color: _lightBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: _lightBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: _primaryColor),
            ),
          ),
          items: [
            for (final method in methods)
              DropdownMenuItem<String>(
                value: method.method,
                child: Text(
                  '${method.label}${method.target.isEmpty ? '' : ' ${method.target}'}',
                ),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (value) {
                  if (value != null) {
                    onChanged!(value);
                  }
                },
        ),
        if (balance?.payPasswordLocked == true) ...[
          const SizedBox(height: 10),
          const _WalletPlainNotice(
            icon: Icons.lock_outline,
            text: '支付密码已锁定，请联系管理员解锁',
            color: Color(0xff991b1b),
            background: Color(0xfffef2f2),
            border: Color(0xfffecaca),
          ),
        ],
      ],
    );
  }
}

class _WalletPlainNotice extends StatelessWidget {
  const _WalletPlainNotice({
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
    required this.border,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
