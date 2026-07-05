part of 'package:bim/src/features/home/home_page.dart';

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    this.size = 44,
    this.color = _primaryColor,
    this.icon,
    this.imageUrl = '',
    this.circle = false,
  });

  final String label;
  final double size;
  final Color color;
  final IconData? icon;
  final String imageUrl;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final fallback = _AvatarFallback(
      label: label,
      size: size,
      color: color,
      icon: icon,
      circle: circle,
    );
    final url = _normalizeAvatarUrl(imageUrl);
    if (url.isEmpty) {
      return fallback;
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(circle ? size / 2 : size * 0.28),
      ),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.label,
    required this.size,
    required this.color,
    this.icon,
    this.circle = false,
  });

  final String label;
  final double size;
  final Color color;
  final IconData? icon;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(circle ? size / 2 : size * 0.28),
      ),
      child: icon == null
          ? Text(
              _avatarInitial(label),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w800,
              ),
            )
          : Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: _primaryColor, size: 25),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
