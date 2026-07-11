part of 'package:bim/src/features/home/home_page.dart';

class _ChatToolsPanel extends StatefulWidget {
  const _ChatToolsPanel({
    required this.height,
    required this.isGroup,
    required this.onBurnAfterRead,
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
  final VoidCallback onBurnAfterRead;
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
      _ToolItem('阅后即焚', widget.onBurnAfterRead, Icons.timer_outlined),
      if (widget.isGroup && widget.onGroupMembers != null)
        _ToolItem('群成员', widget.onGroupMembers!, Icons.groups_rounded),
    ];
    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        color: BimColors.fill,
        border: Border(top: BorderSide(color: BimColors.borderLight)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= BimBreakpoints.desktop
              ? 6
              : constraints.maxWidth >= BimBreakpoints.medium
              ? 5
              : 4;
          final perPage = columns * 2;
          final pages = <List<_ToolItem>>[];
          for (var index = 0; index < items.length; index += perPage) {
            pages.add(items.sublist(index, min(index + perPage, items.length)));
          }
          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: pages.length,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (value) => setState(() => _pageIndex = value),
                  itemBuilder: (context, pageIndex) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        BimSpacing.x4,
                        BimSpacing.x5,
                        BimSpacing.x4,
                        BimSpacing.x2,
                      ),
                      child: _ToolPageGrid(
                        items: pages[pageIndex],
                        columns: columns,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  bottom: max(
                    BimSpacing.x4,
                    MediaQuery.viewPaddingOf(context).bottom + BimSpacing.x1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var index = 0; index < pages.length; index++)
                      AnimatedContainer(
                        duration: BimMotion.normal,
                        curve: BimMotion.curve,
                        width: _pageIndex == index ? 16 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(
                          horizontal: BimSpacing.x1,
                        ),
                        decoration: BoxDecoration(
                          color: _pageIndex == index
                              ? BimColors.primary
                              : BimColors.border,
                          borderRadius: BorderRadius.circular(BimRadius.pill),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolPageGrid extends StatelessWidget {
  const _ToolPageGrid({required this.items, required this.columns});

  final List<_ToolItem> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: BimSpacing.x4,
        crossAxisSpacing: BimSpacing.x2,
        childAspectRatio: 0.92,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _ToolButton(item: items[index]),
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
    return BimPressable(
      onTap: item.onTap,
      semanticLabel: item.label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: BimDimensions.toolIcon,
            height: BimDimensions.toolIcon,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BimColors.surface,
              borderRadius: BorderRadius.circular(BimRadius.md),
            ),
            child: Icon(item.icon, size: 23, color: BimColors.text),
          ),
          const SizedBox(height: BimSpacing.x2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: BimTypography.meta,
              color: BimColors.secondaryText,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
