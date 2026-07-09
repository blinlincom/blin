part of 'package:bim/src/features/home/home_page.dart';

class ActionInputField {
  const ActionInputField({
    required this.id,
    required this.label,
    this.hint = '',
    this.initial = '',
    this.keyboardType,
    this.maxLines = 1,
    this.obscureText = false,
  });

  final String id;
  final String label;
  final String hint;
  final String initial;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool obscureText;
}

void _showChatSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      elevation: 0,
      backgroundColor: error ? _dangerColor : const Color(0xff1f2329),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ActionInputPage extends StatefulWidget {
  const ActionInputPage({required this.title, required this.fields, super.key});

  final String title;
  final List<ActionInputField> fields;

  @override
  State<ActionInputPage> createState() => _ActionInputPageState();
}

class _ActionInputPageState extends State<ActionInputPage> {
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      _controllers[field.id] = TextEditingController(text: field.initial);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        toolbarHeight: 50,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        titleTextStyle: const TextStyle(
          color: _textColor,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _lightBorderColor),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                itemCount: widget.fields.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildField(widget.fields[index]),
              ),
            ),
            _ActionInputFooter(
              onCancel: () => Navigator.of(context).pop(),
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(ActionInputField field) {
    final controller = _controllers[field.id]!;
    final choices = _choicesForField(field.id);
    if (choices.isNotEmpty) {
      var current = controller.text.trim();
      if (current.isEmpty) {
        current = choices.first.value;
      }
      return _ActionFieldShell(
        label: field.label,
        hint: field.hint,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              _ActionChoiceButton(
                label: choice.label,
                selected: current == choice.value,
                onTap: () {
                  controller.text = choice.value;
                  setState(() {});
                },
              ),
          ],
        ),
      );
    }
    if (_isSwitchField(field.id)) {
      final enabled = controller.text.trim() == '1';
      return _ActionFieldShell(
        label: field.label,
        hint: field.hint,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _lightBorderColor),
          ),
          child: SwitchListTile.adaptive(
            value: enabled,
            onChanged: (value) {
              controller.text = value ? '1' : '';
              setState(() {});
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            dense: true,
            title: Text(
              enabled ? '已开启' : '未开启',
              style: const TextStyle(
                color: _textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            activeThumbColor: _chatAckColor,
            activeTrackColor: const Color(0xffd8f4df),
          ),
        ),
      );
    }
    return _ActionFieldShell(
      label: field.label,
      hint: field.hint,
      child: TextField(
        controller: controller,
        keyboardType: field.keyboardType,
        maxLines: field.maxLines,
        minLines: field.maxLines > 1 ? 2 : 1,
        obscureText: field.obscureText,
        style: const TextStyle(
          color: _textColor,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
        decoration: InputDecoration(
          hintText: field.hint.isEmpty ? null : field.hint,
          hintStyle: const TextStyle(color: _mutedColor, fontSize: 14),
          filled: true,
          fillColor: _surfaceColor,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _lightBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _lightBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _primaryColor),
          ),
        ),
      ),
    );
  }

  void _submit() {
    Navigator.of(
      context,
    ).pop(_controllers.map((key, value) => MapEntry(key, value.text.trim())));
  }

  bool _isSwitchField(String id) {
    return id == 'mention_all' || id == 'burn_after_read';
  }

  List<_ActionChoice> _choicesForField(String id) {
    return switch (id) {
      'asset_type' => const [
        _ActionChoice('money', '余额'),
        _ActionChoice('integral', '积分'),
      ],
      'packet_type' => const [
        _ActionChoice('ordinary', '普通'),
        _ActionChoice('luck', '拼手气'),
        _ActionChoice('specified', '指定'),
      ],
      _ => const [],
    };
  }
}

class _ActionChoice {
  const _ActionChoice(this.value, this.label);

  final String value;
  final String label;
}

class _ActionFieldShell extends StatelessWidget {
  const _ActionFieldShell({
    required this.label,
    required this.hint,
    required this.child,
  });

  final String label;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (hint.isNotEmpty && !_hintDuplicatedInInput(hint))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              hint,
              style: const TextStyle(
                color: _secondaryTextColor,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  bool _hintDuplicatedInInput(String value) {
    return value.length <= 18;
  }
}

class _ActionChoiceButton extends StatelessWidget {
  const _ActionChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40, minWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xffe9f8ed) : _surfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _chatAckColor : _lightBorderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xff208a45) : _textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ActionInputFooter extends StatelessWidget {
  const _ActionInputFooter({required this.onCancel, required this.onSubmit});

  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(top: BorderSide(color: _lightBorderColor)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottom > 0 ? bottom : 10),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: _secondaryTextColor,
                side: const BorderSide(color: _borderColor),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: _chatAckColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('确定'),
            ),
          ),
        ],
      ),
    );
  }
}
