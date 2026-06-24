import 'package:flutter/material.dart';

enum FabActionType {
  uploadExpense,
  uploadFile,
  camera,
  photoLibrary,
  manualExpense,
  salesImport,
  salesConnectPos,
  reviewCenter,
  expenseTracker,
  providers,
  products,
  orders,
  documents,
}

class AppFabAction {
  const AppFabAction({
    required this.type,
    required this.label,
    required this.icon,
    required this.onTap,
    this.caption,
    this.isPrimary = false,
  });

  final FabActionType type;
  final String label;
  final String? caption;
  final IconData icon;
  final bool isPrimary;
  final Future<void> Function(BuildContext context) onTap;
}
