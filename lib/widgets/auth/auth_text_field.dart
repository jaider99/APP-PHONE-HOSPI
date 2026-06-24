import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Reusable text field for authentication screens.
/// Supports email, password with visibility toggle, and regular text inputs.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    this.label = '',
    this.hint,
    this.hintText,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.isPassword = false,
    this.obscureText,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.validator,
    this.focusNode,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
  });

  final String label;
  final String? hint;
  final String? hintText;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final bool isPassword;
  final bool? obscureText;
  final TextInputAction textInputAction;
  final void Function(String)? onSubmitted;
  final String? Function(String?)? validator;
  final FocusNode? focusNode;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? errorText;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late final FocusNode _focusNode;
  bool _isFocused = false;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveHint = widget.hintText ?? widget.hint ?? '';
    final showLabel = widget.label.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Text(
            widget.label,
            style: EditorialTypography.labelLarge.copyWith(
              color: EditorialColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: EditorialColors.surfaceContainerLow,
            borderRadius: EditorialRadius.borderRadiusStandard,
            border: _isFocused
                ? Border.all(color: EditorialColors.primary, width: 1.5)
                : null,
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            keyboardType: widget.keyboardType,
            enabled: widget.enabled,
            textCapitalization: widget.textCapitalization,
            obscureText:
                widget.obscureText ?? (widget.isPassword && _obscureText),
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onSubmitted,
            validator: widget.validator,
            style: EditorialTypography.bodyLarge.copyWith(
              color: EditorialColors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: effectiveHint,
              hintStyle: EditorialTypography.bodyLarge.copyWith(
                color: EditorialColors.outline,
              ),
              errorText: widget.errorText,
              prefixIcon: widget.prefixIcon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: widget.suffixIcon ?? (widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscureText
                            ? Icons.remove_red_eye_outlined
                            : Icons.visibility_off_outlined,
                        color: EditorialColors.outline,
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureText = !_obscureText;
                        });
                      },
                    )
                  : null),
            ),
          ),
        ),
      ],
    );
  }
}
