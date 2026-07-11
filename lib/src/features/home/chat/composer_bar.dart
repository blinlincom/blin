part of 'package:bim/src/features/home/home_page.dart';

class _MentionPicker extends StatelessWidget {
  const _MentionPicker({
    required this.members,
    required this.loading,
    required this.showAll,
    required this.onAllSelected,
    required this.onMemberSelected,
  });

  final List<Map<String, Object?>> members;
  final bool loading;
  final bool showAll;
  final VoidCallback onAllSelected;
  final ValueChanged<Map<String, Object?>> onMemberSelected;

  @override
  Widget build(BuildContext context) {
    final itemCount = members.length + (showAll ? 1 : 0);
    return Material(
      color: BimColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: loading && itemCount == 0
            ? const Padding(
                padding: EdgeInsets.all(BimSpacing.x4),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : itemCount == 0
            ? const Padding(
                padding: EdgeInsets.all(BimSpacing.x4),
                child: Center(child: Text('没有匹配的群成员')),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: BimSpacing.x2),
                itemCount: itemCount,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (showAll && index == 0) {
                    return ListTile(
                      dense: true,
                      leading: const _MentionAllAvatar(),
                      title: const Text('全体成员'),
                      subtitle: const Text('通知群内所有成员'),
                      onTap: onAllSelected,
                    );
                  }
                  final member = members[index - (showAll ? 1 : 0)];
                  return ListTile(
                    dense: true,
                    leading: _Avatar(
                      label: _memberTitle(member),
                      imageUrl: _avatarUrlFromMap(member),
                      size: 38,
                    ),
                    title: Text(_memberTitle(member)),
                    subtitle: Text(_memberSubtitle(member)),
                    onTap: () => onMemberSelected(member),
                  );
                },
              ),
      ),
    );
  }
}

class _MentionAllAvatar extends StatelessWidget {
  const _MentionAllAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BimColors.primaryWeak,
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: const Icon(Icons.campaign_outlined, color: BimColors.primary),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.disabledText,
    required this.toolsOpen,
    required this.emojiOpen,
    required this.voiceMode,
    required this.recording,
    required this.onVoice,
    required this.onVoiceRecordStart,
    required this.onVoiceRecordEnd,
    required this.onVoiceRecordCancel,
    required this.onEmoji,
    required this.onTools,
    required this.onSend,
    required this.onContentInserted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String disabledText;
  final bool toolsOpen;
  final bool emojiOpen;
  final bool voiceMode;
  final bool recording;
  final VoidCallback onVoice;
  final VoidCallback onVoiceRecordStart;
  final VoidCallback onVoiceRecordEnd;
  final VoidCallback onVoiceRecordCancel;
  final VoidCallback onEmoji;
  final VoidCallback onTools;
  final VoidCallback onSend;
  final ValueChanged<KeyboardInsertedContent> onContentInserted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: BimColors.surface,
        border: Border(top: BorderSide(color: BimColors.borderLight)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          BimSpacing.x2,
          BimSpacing.x2,
          BimSpacing.x2,
          max(BimSpacing.x2, MediaQuery.viewPaddingOf(context).bottom),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _ComposerIconButton(
              tooltip: voiceMode ? '键盘' : '语音',
              icon: voiceMode ? Icons.keyboard_alt_outlined : Icons.mic_none,
              onPressed: !enabled ? null : onVoice,
            ),
            const SizedBox(width: BimSpacing.x1),
            Expanded(
              child: voiceMode
                  ? _VoiceRecordButton(
                      enabled: enabled,
                      disabledText: disabledText,
                      recording: recording,
                      onStart: onVoiceRecordStart,
                      onEnd: onVoiceRecordEnd,
                      onCancel: onVoiceRecordCancel,
                    )
                  : Container(
                      constraints: const BoxConstraints(
                        minHeight: BimDimensions.composerControl,
                      ),
                      decoration: BoxDecoration(
                        color: BimColors.fill,
                        borderRadius: BorderRadius.circular(BimRadius.sm),
                      ),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: 4,
                        readOnly: !enabled,
                        enabled: enabled,
                        textInputAction: TextInputAction.send,
                        contentInsertionConfiguration:
                            ContentInsertionConfiguration(
                              allowedMimeTypes: const [
                                'image/gif',
                                'image/png',
                                'image/jpeg',
                                'image/webp',
                              ],
                              onContentInserted: onContentInserted,
                            ),
                        onSubmitted: (_) {
                          if (enabled) {
                            onSend();
                          }
                        },
                        decoration: InputDecoration(
                          hintText: enabled ? '输入消息' : disabledText,
                          hintStyle: const TextStyle(
                            color: BimColors.mutedText,
                            fontSize: BimTypography.body,
                          ),
                          filled: true,
                          fillColor: !enabled
                              ? BimColors.fillPressed
                              : BimColors.fill,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            _ComposerIconButton(
              tooltip: emojiOpen ? '键盘' : '表情',
              icon: emojiOpen
                  ? Icons.keyboard_alt_outlined
                  : Icons.sentiment_satisfied_alt,
              onPressed: !enabled ? null : onEmoji,
            ),
            const SizedBox(width: 4),
            _ComposerIconButton(
              tooltip: toolsOpen ? '收起' : '更多',
              icon: toolsOpen ? Icons.close : Icons.add_circle_outline,
              onPressed: !enabled ? null : onTools,
            ),
            if (!voiceMode)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  if (!enabled || value.text.trim().isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 40,
                        child: TextButton(
                          onPressed: onSend,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: _chatAckColor,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(
                              BimDimensions.composerControl,
                              40,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: const Text(
                            '发送',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _VoiceRecordButton extends StatefulWidget {
  const _VoiceRecordButton({
    required this.enabled,
    required this.disabledText,
    required this.recording,
    required this.onStart,
    required this.onEnd,
    required this.onCancel,
  });

  final bool enabled;
  final String disabledText;
  final bool recording;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  State<_VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<_VoiceRecordButton>
    with SingleTickerProviderStateMixin {
  bool _canceling = false;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didUpdateWidget(covariant _VoiceRecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording && !_waveController.isAnimating) {
      _waveController.repeat();
    } else if (!widget.recording && _waveController.isAnimating) {
      _waveController.stop();
      _waveController.reset();
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  void _updateCancel(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final local = box.globalToLocal(globalPosition);
    final next =
        local.dy < -22 ||
        local.dx < -18 ||
        local.dx > box.size.width + 18 ||
        local.dy > box.size.height + 24;
    if (next != _canceling && mounted) {
      HapticFeedback.selectionClick();
      setState(() => _canceling = next);
    }
  }

  void _finish() {
    if (_canceling) {
      widget.onCancel();
    } else {
      widget.onEnd();
    }
    if (mounted) {
      setState(() => _canceling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = !widget.enabled
        ? widget.disabledText
        : widget.recording
        ? (_canceling ? '松开取消' : '松开发送，上滑取消')
        : '按住说话';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: widget.enabled
          ? (details) {
              HapticFeedback.lightImpact();
              setState(() => _canceling = false);
              widget.onStart();
            }
          : null,
      onLongPressMoveUpdate: widget.enabled
          ? (details) => _updateCancel(details.globalPosition)
          : null,
      onLongPressEnd: widget.enabled ? (_) => _finish() : null,
      onLongPressCancel: widget.enabled ? widget.onCancel : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        height: BimDimensions.composerControl,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !widget.enabled
              ? const Color(0xffeeeeee)
              : widget.recording
              ? (_canceling ? const Color(0xffffece8) : const Color(0xffe8f7ee))
              : _fillColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: widget.recording
                ? (_canceling ? BimColors.redPacket : _chatAckColor)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.recording) ...[
              _VoiceWaveIndicator(
                controller: _waveController,
                color: _canceling ? BimColors.redPacket : _chatAckColor,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: !widget.enabled
                      ? _mutedColor
                      : _canceling
                      ? BimColors.redPacket
                      : _textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceWaveIndicator extends StatelessWidget {
  const _VoiceWaveIndicator({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 5; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Transform.scale(
                  alignment: Alignment.center,
                  scaleY: _barScale(controller.value, index),
                  child: Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  double _barScale(double value, int index) {
    final phase = (value + index * 0.16) % 1;
    return 0.45 + sin(phase * pi * 2).abs() * 0.65;
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: BimDimensions.composerControl,
      height: BimDimensions.composerControl,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          size: 25,
          color: onPressed == null ? _mutedColor : _textColor,
        ),
      ),
    );
  }
}
