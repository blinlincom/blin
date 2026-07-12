part of 'auth_page.dart';

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
              : CachedNetworkImage(
                  imageUrl: icon,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, __, ___) => const Icon(
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

class _AuthIdentityPane extends StatelessWidget {
  const _AuthIdentityPane({required this.appInfo});

  final AppInfo? appInfo;

  @override
  Widget build(BuildContext context) {
    final appName = appInfo?.name.isNotEmpty == true ? appInfo!.name : 'BIM';
    return ColoredBox(
      color: BimColors.navigationSurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthBrand(appInfo: appInfo),
            const Spacer(),
            Text(
              appName,
              style: const TextStyle(
                color: BimColors.textDark,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: BimSpacing.x4),
            const Text(
              '让每一次沟通保持连续、清晰和可信。',
              style: TextStyle(
                color: BimColors.secondaryText,
                fontSize: BimTypography.title,
                fontWeight: FontWeight.w500,
                height: 1.55,
              ),
            ),
            const SizedBox(height: BimSpacing.x8),
            const _AuthValueLine(
              icon: Icons.forum_outlined,
              text: '消息、联系人和群聊实时连接',
            ),
            const _AuthValueLine(
              icon: Icons.lock_outline,
              text: '账号和支付操作清晰可验证',
            ),
            const _AuthValueLine(
              icon: Icons.devices_outlined,
              text: '手机、平板和桌面保持一致体验',
            ),
            const Spacer(),
            const Text(
              'BIM',
              style: TextStyle(
                color: BimColors.mutedText,
                fontSize: BimTypography.meta,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthValueLine extends StatelessWidget {
  const _AuthValueLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BimSpacing.x4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            color: BimColors.primaryWeak,
            child: Icon(icon, color: BimColors.primary, size: 19),
          ),
          const SizedBox(width: BimSpacing.x3),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: BimColors.text,
                fontSize: BimTypography.body,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
      return CachedNetworkImage(
        imageUrl: image,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
      );
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
