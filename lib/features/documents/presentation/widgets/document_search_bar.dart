import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DigitalAtelierSearchBar extends StatefulWidget {
  const DigitalAtelierSearchBar({
    required this.controller,
    required this.onChanged,
    required this.horizontalPadding,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double horizontalPadding;

  @override
  State<DigitalAtelierSearchBar> createState() => _DigitalAtelierSearchBarState();
}

class _DigitalAtelierSearchBarState extends State<DigitalAtelierSearchBar> {
  late final FocusNode _focusNode;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _setPressed(bool value) {
    if (_isPressed == value || !mounted) return;
    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasFocus = _focusNode.hasFocus;
    final width = MediaQuery.sizeOf(context).width;
    final hintText = width < 360
        ? 'Search documents...'
        : 'Search documents, suppliers...';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            height: 54,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: hasFocus
                      ? const Color.fromRGBO(26, 28, 28, 0.05)
                      : const Color.fromRGBO(26, 28, 28, 0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 21,
                  color: Color(0xFF7E7576),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    onChanged: widget.onChanged,
                    cursorColor: const Color(0xFF000000),
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF1B1B1B),
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      hintText: hintText,
                      hintStyle: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF7E7576),
                        height: 1.2,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DocumentSearchBar extends StatelessWidget {
  const DocumentSearchBar({
    required this.controller,
    required this.onChanged,
    required this.horizontalPadding,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return DigitalAtelierSearchBar(
      controller: controller,
      onChanged: onChanged,
      horizontalPadding: horizontalPadding,
    );
  }
}
