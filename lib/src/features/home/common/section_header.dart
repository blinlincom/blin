part of 'package:bim/src/features/home/home_page.dart';

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: children);
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: _borderColor)),
      child: SelectableText(text),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      color: const Color(0xffffeeee),
      child: Text(text, style: const TextStyle(color: _dangerColor)),
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: const Color(0xffffeeee),
      child: Text(text, style: const TextStyle(color: _dangerColor)),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: const Color(0xffeef5ff),
      child: Text(text, maxLines: 5, overflow: TextOverflow.ellipsis),
    );
  }
}

class _LinearBusy extends StatelessWidget {
  const _LinearBusy();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: LinearProgressIndicator(minHeight: 2),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: _pageColor,
      child: Text(
        text,
        style: const TextStyle(
          color: _mutedColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GroupGap extends StatelessWidget {
  const _GroupGap();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 8);
  }
}

class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex();

  @override
  Widget build(BuildContext context) {
    const letters = [
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
      '#',
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final letter in letters)
          SizedBox(
            height: 13,
            width: 18,
            child: Center(
              child: Text(
                letter,
                style: const TextStyle(
                  color: Color(0xff6f7785),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Text(text, style: const TextStyle(color: _mutedColor)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: _mutedColor)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _dangerColor),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
