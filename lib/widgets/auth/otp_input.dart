import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// OTP input widget with 5 digit boxes.
/// Uses a hidden TextFormField and displays characters in individual boxes.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.onCompleted,
    this.onChanged,
    this.length = 5,
  });

  final void Function(String code) onCompleted;
  final void Function(String code)? onChanged;
  final int length;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _code = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (text.length <= widget.length) {
      setState(() {
        _code = text;
      });
      widget.onChanged?.call(text);
      if (text.length == widget.length) {
        widget.onCompleted(text);
      }
    }
  }

  int get _focusedIndex {
    if (_code.length >= widget.length) {
      return widget.length - 1;
    }
    return _code.length;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _focusNode.requestFocus();
      },
      child: Stack(
        children: [
          // Hidden input field
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 1,
              child: TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                maxLength: widget.length,
                autofocus: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                decoration: const InputDecoration(
                  counterText: '',
                ),
              ),
            ),
          ),
          // Visual boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.length, (index) {
              final hasValue = index < _code.length;
              final isFocused = _focusNode.hasFocus && index == _focusedIndex;
              final char = hasValue ? _code[index] : '';

              return _OtpBox(
                char: char,
                isFocused: isFocused,
                hasValue: hasValue,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.char,
    required this.isFocused,
    required this.hasValue,
  });

  final String char;
  final bool isFocused;
  final bool hasValue;

  @override
  Widget build(BuildContext context) {
    final showBorder = isFocused || hasValue;

    return Container(
      width: 56,
      height: 60,
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLow,
        borderRadius: EditorialRadius.borderRadiusStandard,
        border: Border.all(
          color: showBorder ? EditorialColors.primary : EditorialColors.surfaceContainerLow,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          char,
          style: EditorialTypography.headlineSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: EditorialColors.onSurface,
          ),
        ),
      ),
    );
  }
}
