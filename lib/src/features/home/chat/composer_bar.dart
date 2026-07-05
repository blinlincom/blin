part of 'package:bim/src/features/home/home_page.dart';

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.enabled,
    required this.disabledText,
    required this.toolsOpen,
    required this.onVoice,
    required this.onEmoji,
    required this.onTools,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool enabled;
  final String disabledText;
  final bool toolsOpen;
  final VoidCallback onVoice;
  final VoidCallback onEmoji;
  final VoidCallback onTools;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _chatPageColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _ComposerIconButton(
              tooltip: '语音',
              icon: Icons.mic_none,
              onPressed: sending || !enabled ? null : onVoice,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  readOnly: !enabled,
                  enabled: enabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (!sending && enabled) {
                      onSend();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: sending
                        ? '发送中'
                        : enabled
                        ? '输入消息'
                        : disabledText,
                    hintStyle: const TextStyle(
                      color: Color(0xffaeb4bd),
                      fontSize: 15,
                    ),
                    filled: true,
                    fillColor: !enabled
                        ? const Color(0xffeeeeee)
                        : Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _ComposerIconButton(
              tooltip: '表情',
              icon: Icons.sentiment_satisfied_alt,
              onPressed: sending || !enabled ? null : onEmoji,
            ),
            const SizedBox(width: 4),
            _ComposerIconButton(
              tooltip: toolsOpen ? '收起' : '更多',
              icon: toolsOpen ? Icons.close : Icons.add_circle_outline,
              onPressed: sending || !enabled ? null : onTools,
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (!enabled || (!sending && value.text.trim().isEmpty)) {
                  return const SizedBox.shrink();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 4),
                    SizedBox(
                      height: 36,
                      child: TextButton(
                        onPressed: sending ? null : onSend,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: _chatAckColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(40, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
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
      width: 34,
      height: 40,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          size: 27,
          color: onPressed == null ? _mutedColor : Colors.black,
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(label),
    );
  }
}
