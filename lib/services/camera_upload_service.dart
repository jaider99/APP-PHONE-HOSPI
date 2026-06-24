import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/features/expenses/presentation/providers/expense_form_provider.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

// Android permissions:
//   <uses-permission android:name="android.permission.CAMERA"/>
//   <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
//   <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
//       android:maxSdkVersion="32"/>
//
// iOS Info.plist:
//   NSCameraUsageDescription →
//     "Take photos of invoices and documents to scan them directly into The Ledger."
//   NSPhotoLibraryUsageDescription →
//     "Choose images of documents from your photo library."

const _allowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'];
const _maxFileSize = 10 * 1024 * 1024; // 10 MB

/// Handles camera capture, gallery pick, and file pick for expense creation.
class CameraUploadService {
  CameraUploadService._();

  static final _picker = ImagePicker();

  // ── PHOTO (camera) ───────────────────────────────────────────────────────

  static Future<void> handleCameraCapture(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // 1. Request camera permission
    final status = await Permission.camera.request();
    if (!context.mounted) return;

    if (status.isDenied) {
      _showSnackBar(context, 'Camera access needed — enable in Settings');
      return;
    }
    if (status.isPermanentlyDenied) {
      _showSnackBar(context, 'Camera access denied — opening Settings');
      await openAppSettings();
      return;
    }

    // 2. Launch camera
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1920,
      maxHeight: 1920,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (!context.mounted) return;
    if (photo == null) return; // user cancelled

    // 3. Read bytes — DO NOT save to gallery
    final Uint8List bytes = await photo.readAsBytes();
    if (!context.mounted) return;

    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _navigateToExpenseForm(
      context,
      ref,
      fileName: fileName,
      fileBytes: bytes,
      mimeType: 'image/jpeg',
      initialPages: [bytes],
    );
  }

  // ── ADD > Photo Library ──────────────────────────────────────────────────

  static Future<void> handleGalleryPick(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1920,
    );
    if (!context.mounted) return;
    if (image == null) return;

    final Uint8List bytes = await image.readAsBytes();
    if (!context.mounted) return;

    final fileName = image.name;
    final ext = fileName.split('.').last.toLowerCase();
    final mimeType = _mimeFromExtension(ext);

    await _navigateToExpenseForm(
      context,
      ref,
      fileName: fileName,
      fileBytes: bytes,
      mimeType: mimeType,
      initialPages: mimeType.startsWith('image/') ? [bytes] : const [],
    );
  }

  // ── ADD > Choose File ────────────────────────────────────────────────────

  static Future<void> handleFilePick(
    BuildContext context,
    WidgetRef ref,
  ) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        withData: false,
        allowMultiple: false,
      );
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, 'File picker unavailable');
      }
      return;
    }
    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final String? name = file.name;
    final String? path = file.path;

    if (name == null || path == null) {
      _showSnackBar(context, 'Could not read file');
      return;
    }

    // Validate extension
    final ext = name.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      _showSnackBar(
        context,
        'Unsupported format (.$ext). Use: ${_allowedExtensions.join(", ")}',
      );
      return;
    }

    // Read bytes from path
    final fileEntity = File(path);
    final fileSize = await fileEntity.length();
    if (!context.mounted) return;

    if (fileSize > _maxFileSize) {
      _showSnackBar(context, 'File too large. Max 10 MB.');
      return;
    }

    final Uint8List bytes = await fileEntity.readAsBytes();
    if (!context.mounted) return;

    final mimeType = _mimeFromExtension(ext);

    await _navigateToExpenseForm(
      context,
      ref,
      fileName: name,
      fileBytes: bytes,
      mimeType: mimeType,
      initialPages: mimeType.startsWith('image/') ? [bytes] : const [],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Open the expense form immediately after selecting a document.
  static Future<void> _navigateToExpenseForm(
    BuildContext context,
    WidgetRef ref,
    {
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    required List<Uint8List> initialPages,
  }) async {
    final companyId = await ref.read(companyIdProvider.future);
    if (!context.mounted) return;
    if (companyId == null) {
      _showSnackBar(
        context,
        'No company linked to your account. Please complete setup first.',
      );
      return;
    }

    context.push(
      AppRoutes.expenseForm,
      extra: ExpenseFormArgs(
        fileBytes: fileBytes,
        companyId: companyId,
        fileName: fileName,
        mimeType: mimeType,
        initialPages: initialPages,
      ).toMap(),
    );
  }

  static String _mimeFromExtension(String ext) {
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }

  static void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: EditorialTypography.bodySmall.copyWith(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: EditorialColors.onSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: EditorialRadius.borderRadiusMd,
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ),
    );
  }
}
