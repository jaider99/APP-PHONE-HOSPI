import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hospi_dash/core/theme/app_motion.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/services/camera_upload_service.dart';

/// Scanner-first action sheet.
///
/// Opened from the floating Add FAB. "Scan receipt" is visually primary — a
/// charcoal full-width tile that mirrors the FAB. "Upload PDF / image" and
/// "Enter manually" are quieter secondary tiles below.
///
/// Backend hooks are unchanged: it routes straight into
/// [CameraUploadService] which already owns the camera → expense form →
/// upload → background extraction flow.
class ScannerActionSheet {
  ScannerActionSheet._();

  /// Show the sheet. The optional [onManual] callback fires when the user
  /// chooses "Enter manually" (e.g. show a snackbar).
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    VoidCallback? onManual,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (ctx) => _ScannerSheet(
        parentContext: context,
        ref: ref,
        onManual: onManual,
      ),
    );
  }
}

class _ScannerSheet extends StatelessWidget {
  const _ScannerSheet({
    required this.parentContext,
    required this.ref,
    this.onManual,
  });

  /// The context that originally invoked the sheet — used for navigation
  /// AFTER the sheet has been popped, so router pushes happen against a
  /// still-mounted ancestor.
  final BuildContext parentContext;
  final WidgetRef ref;
  final VoidCallback? onManual;

  Future<void> _closeSheet(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    await Future<void>.delayed(AppMotion.fast);
  }

  Future<void> _scan(BuildContext sheetContext) async {
    await _closeSheet(sheetContext);
    if (!parentContext.mounted) return;
    await CameraUploadService.handleCameraCapture(parentContext, ref);
  }

  Future<void> _upload(BuildContext sheetContext) async {
    await _closeSheet(sheetContext);
    if (!parentContext.mounted) return;
    // Choose file (supports image + PDF); keeps the existing flow.
    await CameraUploadService.handleFilePick(parentContext, ref);
  }

  Future<void> _gallery(BuildContext sheetContext) async {
    await _closeSheet(sheetContext);
    if (!parentContext.mounted) return;
    await CameraUploadService.handleGalleryPick(parentContext, ref);
  }

  Future<void> _manual(BuildContext sheetContext) async {
    await _closeSheet(sheetContext);
    if (!parentContext.mounted) return;
    if (onManual != null) {
      onManual!();
    } else {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 110),
          backgroundColor: EditorialColors.onSurface,
          content: Text(
            'Manual entry coming soon',
            style: EditorialTypography.bodyMedium.copyWith(
              color: EditorialColors.onPrimary,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnimatedPadding(
      duration: AppMotion.emphasised,
      curve: AppMotion.enter,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: EditorialColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 32,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: EditorialColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'New expense',
                    style: EditorialTypography.titleLarge.copyWith(
                      color: EditorialColors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Scan a receipt and we extract the rest.',
                    style: EditorialTypography.bodyMedium.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Primary action
                _PrimaryAction(
                  label: 'Scan receipt',
                  caption: 'Capture with camera',
                  icon: Icons.photo_camera_rounded,
                  onTap: () => _scan(context),
                ),
                const SizedBox(height: 10),

                // Secondary actions
                _SecondaryAction(
                  label: 'Upload file',
                  caption: 'PDF or image',
                  icon: Icons.file_upload_outlined,
                  onTap: () => _upload(context),
                ),
                const SizedBox(height: 8),
                _SecondaryAction(
                  label: 'Choose from library',
                  caption: 'Pick a photo',
                  icon: Icons.image_outlined,
                  onTap: () => _gallery(context),
                ),
                const SizedBox(height: 8),
                _SecondaryAction(
                  label: 'Enter manually',
                  caption: 'Type the details',
                  icon: Icons.edit_outlined,
                  onTap: () => _manual(context),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Primary / secondary tiles
// ─────────────────────────────────────────────────────────────────────────────

class _PrimaryAction extends StatefulWidget {
  const _PrimaryAction({
    required this.label,
    required this.caption,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String caption;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_PrimaryAction> createState() => _PrimaryActionState();
}

class _PrimaryActionState extends State<_PrimaryAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: AppMotion.fast,
        curve: AppMotion.enter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: EditorialColors.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  widget.icon,
                  color: EditorialColors.onPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: EditorialTypography.titleMedium.copyWith(
                        color: EditorialColors.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.caption,
                      style: EditorialTypography.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatefulWidget {
  const _SecondaryAction({
    required this.label,
    required this.caption,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String caption;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_SecondaryAction> createState() => _SecondaryActionState();
}

class _SecondaryActionState extends State<_SecondaryAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: AppMotion.fast,
        curve: AppMotion.enter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: EditorialColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: EditorialColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  color: EditorialColors.onSurface,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: EditorialTypography.bodyLarge.copyWith(
                        color: EditorialColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.caption,
                      style: EditorialTypography.bodySmall.copyWith(
                        color: EditorialColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: EditorialColors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
