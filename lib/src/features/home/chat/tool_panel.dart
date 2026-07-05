part of 'package:bim/src/features/home/home_page.dart';

class _ChatToolsPanel extends StatelessWidget {
  const _ChatToolsPanel({
    required this.isGroup,
    required this.onTextOption,
    required this.onImage,
    required this.onEmoji,
    required this.onGif,
    required this.onSticker,
    required this.onVoice,
    required this.onVideo,
    required this.onFile,
    required this.onContactCard,
    required this.onTransfer,
    required this.onRedPacket,
    this.onGroupMembers,
  });

  final bool isGroup;
  final VoidCallback onTextOption;
  final VoidCallback onImage;
  final VoidCallback onEmoji;
  final VoidCallback onGif;
  final VoidCallback onSticker;
  final VoidCallback onVoice;
  final VoidCallback onVideo;
  final VoidCallback onFile;
  final VoidCallback onContactCard;
  final VoidCallback onTransfer;
  final VoidCallback onRedPacket;
  final VoidCallback? onGroupMembers;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ToolItem(
        Icons.photo_library_rounded,
        '相册',
        onImage,
        const Color(0xff8e6df7),
      ),
      _ToolItem(
        Icons.photo_camera_rounded,
        '拍摄',
        onImage,
        const Color(0xff2f7df6),
      ),
      _ToolItem(
        Icons.videocam_rounded,
        '视频通话',
        onVideo,
        const Color(0xff2fc86f),
      ),
      _ToolItem(
        Icons.location_on_rounded,
        '位置',
        onTextOption,
        const Color(0xffffa21a),
      ),
      _ToolItem(Icons.folder_rounded, '文件', onFile, const Color(0xff2f7df6)),
      _ToolItem(
        Icons.attach_money_rounded,
        '转账',
        onTransfer,
        const Color(0xff28b957),
      ),
      _ToolItem(
        Icons.redeem_rounded,
        '红包',
        onRedPacket,
        const Color(0xffff543c),
      ),
      _ToolItem(
        Icons.contact_page_rounded,
        '名片',
        onContactCard,
        const Color(0xff347cff),
      ),
      _ToolItem(
        Icons.emoji_emotions_rounded,
        '表情',
        onEmoji,
        const Color(0xffffc043),
      ),
      _ToolItem(Icons.gif_box_rounded, 'GIF', onGif, const Color(0xff20c997)),
      _ToolItem(
        Icons.sticky_note_2_rounded,
        '贴纸',
        onSticker,
        const Color(0xff7c5cff),
      ),
      _ToolItem(
        Icons.keyboard_voice_rounded,
        '语音',
        onVoice,
        const Color(0xff5ac8fa),
      ),
      _ToolItem(
        Icons.tune_rounded,
        '文本选项',
        onTextOption,
        const Color(0xff8e99a8),
      ),
      if (isGroup && onGroupMembers != null)
        _ToolItem(
          Icons.groups_rounded,
          '群成员',
          onGroupMembers!,
          const Color(0xff34c759),
        ),
    ];
    final pages = <List<_ToolItem>>[];
    for (var index = 0; index < items.length; index += 8) {
      pages.add(items.sublist(index, (index + 8).clamp(0, items.length)));
    }
    return Container(
      height: 174,
      color: _chatPageColor,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: PageView.builder(
          itemCount: pages.length,
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, pageIndex) {
            final pageItems = pages[pageIndex];
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 13, 18, 12),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pageItems.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 66,
                crossAxisSpacing: 10,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) =>
                  _ToolButton(item: pageItems[index]),
            );
          },
        ),
      ),
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
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(
                item.icon == Icons.attach_money_rounded ? 16 : 6,
              ),
            ),
            child: Icon(item.icon, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 7),
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
