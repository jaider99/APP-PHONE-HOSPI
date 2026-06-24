import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hospi_dash/services/camera_upload_service.dart';

import 'app_fab_action.dart';

List<AppFabAction> scannerFabActions({
  required WidgetRef ref,
  VoidCallback? onManual,
}) {
  return [
    AppFabAction(
      type: FabActionType.uploadFile,
      label: 'Upload file',
      caption: 'PDF, image, or receipt',
      icon: Icons.file_upload_outlined,
      isPrimary: true,
      onTap: (context) async {
        debugPrint('[FAB] Selected child action: upload_file');
        await CameraUploadService.handleFilePick(context, ref);
      },
    ),
    AppFabAction(
      type: FabActionType.camera,
      label: 'Camera',
      caption: 'Scan a receipt now',
      icon: Icons.photo_camera_rounded,
      onTap: (context) async {
        debugPrint('[FAB] Selected child action: camera');
        await CameraUploadService.handleCameraCapture(context, ref);
      },
    ),
    AppFabAction(
      type: FabActionType.photoLibrary,
      label: 'Photo library',
      caption: 'Choose an existing image',
      icon: Icons.image_outlined,
      onTap: (context) async {
        debugPrint('[FAB] Selected child action: photo_library');
        await CameraUploadService.handleGalleryPick(context, ref);
      },
    ),
    AppFabAction(
      type: FabActionType.manualExpense,
      label: 'Manually',
      caption: 'Enter details yourself',
      icon: Icons.edit_outlined,
      onTap: (context) async {
        debugPrint('[FAB] Selected child action: manual_expense');
        if (onManual != null) {
          onManual();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Manual entry coming soon'),
          ),
        );
      },
    ),
  ];
}
