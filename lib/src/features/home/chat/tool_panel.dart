part of 'package:bim/src/features/home/home_page.dart';

class _ChatToolsPanel extends StatefulWidget {
  const _ChatToolsPanel({
    required this.height,
    required this.isGroup,
    required this.onTextOption,
    required this.onVoiceInput,
    required this.onImage,
    required this.onEmoji,
    required this.onSticker,
    required this.onVideo,
    required this.onFile,
    required this.onContactCard,
    required this.onTransfer,
    required this.onRedPacket,
    required this.onGroupVoiceCall,
    required this.onGroupVideoCall,
    this.onGroupMembers,
  });

  final double height;
  final bool isGroup;
  final VoidCallback onTextOption;
  final VoidCallback onVoiceInput;
  final VoidCallback onImage;
  final VoidCallback onEmoji;
  final VoidCallback onSticker;
  final VoidCallback onVideo;
  final VoidCallback onFile;
  final VoidCallback onContactCard;
  final VoidCallback onTransfer;
  final VoidCallback onRedPacket;
  final VoidCallback onGroupVoiceCall;
  final VoidCallback onGroupVideoCall;
  final VoidCallback? onGroupMembers;

  @override
  State<_ChatToolsPanel> createState() => _ChatToolsPanelState();
}

class _ChatToolsPanelState extends State<_ChatToolsPanel> {
  late final PageController _pageController;
  var _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _ToolItem('相册', widget.onImage, Icons.photo_library_rounded),
      _ToolItem('视频', widget.onVideo, Icons.video_library_rounded),
      if (widget.isGroup) ...[
        _ToolItem('语音通话', widget.onGroupVoiceCall, Icons.phone_in_talk_rounded),
        _ToolItem(
          '视频通话',
          widget.onGroupVideoCall,
          Icons.video_camera_back_rounded,
        ),
      ],
      _ToolItem('文件', widget.onFile, Icons.insert_drive_file_rounded),
      _ToolItem('红包', widget.onRedPacket, Icons.card_giftcard_rounded),
      _ToolItem('转账', widget.onTransfer, Icons.swap_horiz_rounded),
      _ToolItem('语音输入', widget.onVoiceInput, Icons.mic_rounded),
      _ToolItem('名片', widget.onContactCard, Icons.badge_rounded),
      _ToolItem('表情', widget.onEmoji, Icons.emoji_emotions_rounded),
      _ToolItem('贴纸', widget.onSticker, Icons.sticky_note_2_rounded),
      _ToolItem('文本选项', widget.onTextOption, Icons.tune_rounded),
      if (widget.isGroup && widget.onGroupMembers != null)
        _ToolItem('群成员', widget.onGroupMembers!, Icons.groups_rounded),
    ];
    final pages = <List<_ToolItem>>[];
    for (var index = 0; index < items.length; index += 8) {
      pages.add(items.sublist(index, (index + 8).clamp(0, items.length)));
    }
    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        color: _fillColor,
        border: Border(top: BorderSide(color: _lightBorderColor)),
      ),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: pages.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (value) => setState(() => _pageIndex = value),
              itemBuilder: (context, pageIndex) {
                final pageItems = pages[pageIndex];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
                  child: _ToolPageGrid(items: pageItems),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              bottom: max(18.0, MediaQuery.viewPaddingOf(context).bottom + 6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < pages.length; index++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: _pageIndex == index
                          ? const Color(0xff7f858d)
                          : const Color(0xffd9dce1),
                      borderRadius: BorderRadius.circular(BimRadius.pill),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolPageGrid extends StatelessWidget {
  const _ToolPageGrid({required this.items});

  final List<_ToolItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          Expanded(
            child: Row(
              children: [
                for (var column = 0; column < 4; column++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Builder(
                        builder: (context) {
                          final index = row * 4 + column;
                          if (index >= items.length) {
                            return const SizedBox.shrink();
                          }
                          return _ToolButton(item: items[index]);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (row == 0) const SizedBox(height: 22),
        ],
      ],
    );
  }
}

class _ToolItem {
  const _ToolItem(this.label, this.onTap, this.icon);

  final String label;
  final VoidCallback onTap;
  final IconData icon;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.item});

  final _ToolItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: BimDimensions.toolIcon,
            height: BimDimensions.toolIcon,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(BimRadius.lg),
            ),
            child: Icon(item.icon, size: 24, color: _textColor),
          ),
          const SizedBox(height: 9),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: _secondaryTextColor,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
