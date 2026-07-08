part of 'package:bim/src/features/home/home_page.dart';

class _ChatToolsPanel extends StatefulWidget {
  const _ChatToolsPanel({
    required this.height,
    required this.isGroup,
    required this.onTextOption,
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
      _ToolItem(
        Icons.photo_library_rounded,
        '相册',
        widget.onImage,
        const Color(0xff8e6df7),
      ),
      _ToolItem(
        Icons.videocam_rounded,
        '视频',
        widget.onVideo,
        const Color(0xff2fc86f),
      ),
      _ToolItem(
        Icons.folder_rounded,
        '文件',
        widget.onFile,
        const Color(0xff2f7df6),
      ),
      if (widget.isGroup) ...[
        _ToolItem(
          Icons.call_rounded,
          '语音通话',
          widget.onGroupVoiceCall,
          const Color(0xff34c759),
        ),
        _ToolItem(
          Icons.video_call_rounded,
          '视频通话',
          widget.onGroupVideoCall,
          BimColors.primary,
        ),
      ],
      _ToolItem(
        Icons.attach_money_rounded,
        '转账',
        widget.onTransfer,
        BimColors.transfer,
      ),
      _ToolItem(
        Icons.redeem_rounded,
        '红包',
        widget.onRedPacket,
        BimColors.redPacket,
      ),
      _ToolItem(
        Icons.contact_page_rounded,
        '名片',
        widget.onContactCard,
        const Color(0xff347cff),
      ),
      _ToolItem(
        Icons.emoji_emotions_rounded,
        '表情',
        widget.onEmoji,
        const Color(0xffffc043),
      ),
      _ToolItem(
        Icons.sticky_note_2_rounded,
        '贴纸',
        widget.onSticker,
        const Color(0xff7c5cff),
      ),
      _ToolItem(
        Icons.tune_rounded,
        '文本选项',
        widget.onTextOption,
        const Color(0xff8e99a8),
      ),
      if (widget.isGroup && widget.onGroupMembers != null)
        _ToolItem(
          Icons.groups_rounded,
          '群成员',
          widget.onGroupMembers!,
          const Color(0xff34c759),
        ),
    ];
    final pages = <List<_ToolItem>>[];
    for (var index = 0; index < items.length; index += 8) {
      pages.add(items.sublist(index, (index + 8).clamp(0, items.length)));
    }
    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        color: _surfaceColor,
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
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: _ToolPageGrid(items: pageItems),
                );
              },
            ),
          ),
          if (pages.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < pages.length; index++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: _pageIndex == index ? 13 : 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: _pageIndex == index
                            ? const Color(0xff8f96a3)
                            : const Color(0xffd5d9df),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            )
          else
            const SizedBox(height: 14),
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
                      padding: EdgeInsets.only(
                        left: column == 0 ? 0 : 6,
                        right: column == 3 ? 0 : 6,
                      ),
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
          if (row == 0) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ToolItem {
  const _ToolItem(this.icon, this.label, this.onTap, this.color);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
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
              color: item.color,
              borderRadius: BorderRadius.circular(
                item.icon == Icons.attach_money_rounded
                    ? BimRadius.pill
                    : BimRadius.md,
              ),
            ),
            child: Icon(item.icon, size: 23, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xff2f3338),
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
