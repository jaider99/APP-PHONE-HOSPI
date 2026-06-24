import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/router/app_router.dart';

import 'app_fab_action.dart';

List<AppFabAction> dashboardFabActions() {
  return globalFabActions();
}

List<AppFabAction> globalFabActions() {
  return [
    AppFabAction(
      type: FabActionType.uploadExpense,
      label: 'Upload expense',
      caption: 'Scan or import a receipt',
      icon: Icons.add_photo_alternate_outlined,
      isPrimary: true,
      onTap: (_) async {},
    ),
    AppFabAction(
      type: FabActionType.salesImport,
      label: 'Import sales report',
      caption: 'Upload POS export data',
      icon: Icons.upload_file_rounded,
      onTap: (context) async => context.push(AppRoutes.salesImport),
    ),
    AppFabAction(
      type: FabActionType.salesConnectPos,
      label: 'Connect POS',
      caption: 'Set up a sales integration',
      icon: Icons.link_rounded,
      onTap: (context) async => context.push(AppRoutes.salesConnectPos),
    ),
    AppFabAction(
      type: FabActionType.reviewCenter,
      label: 'Review Center',
      caption: 'Resolve pending actions',
      icon: Icons.task_alt_rounded,
      onTap: (context) async => context.go(AppRoutes.reviewCenter),
    ),
    AppFabAction(
      type: FabActionType.expenseTracker,
      label: 'Expense tracker',
      caption: 'Open spend breakdown',
      icon: Icons.pie_chart_outline_rounded,
      onTap: (context) async => context.go(AppRoutes.expenses),
    ),
    AppFabAction(
      type: FabActionType.providers,
      label: 'Providers',
      caption: 'Supplier intelligence',
      icon: Icons.storefront_outlined,
      onTap: (context) async => context.go(AppRoutes.providers),
    ),
    AppFabAction(
      type: FabActionType.products,
      label: 'Products',
      caption: 'Stock and pricing',
      icon: Icons.inventory_2_outlined,
      onTap: (context) async => context.go(AppRoutes.products),
    ),
    AppFabAction(
      type: FabActionType.orders,
      label: 'Orders',
      caption: 'Purchase operations',
      icon: Icons.receipt_long_outlined,
      onTap: (context) async => context.go(AppRoutes.orders),
    ),
    AppFabAction(
      type: FabActionType.documents,
      label: 'Documents',
      caption: 'Inbox and extraction queue',
      icon: Icons.description_outlined,
      onTap: (context) async => context.go(AppRoutes.documents),
    ),
  ];
}

List<AppFabAction> salesFabActions() {
  return [
    AppFabAction(
      type: FabActionType.salesImport,
      label: 'Import sales report',
      caption: 'Upload POS export data',
      icon: Icons.upload_file_rounded,
      isPrimary: true,
      onTap: (context) async => context.push(AppRoutes.salesImport),
    ),
    AppFabAction(
      type: FabActionType.salesConnectPos,
      label: 'Connect POS',
      caption: 'Set up a sales integration',
      icon: Icons.link_rounded,
      onTap: (context) async => context.push(AppRoutes.salesConnectPos),
    ),
    AppFabAction(
      type: FabActionType.uploadExpense,
      label: 'Upload expense',
      caption: 'Scan or import a receipt',
      icon: Icons.add_photo_alternate_outlined,
      onTap: (_) async {},
    ),
    AppFabAction(
      type: FabActionType.reviewCenter,
      label: 'Review Center',
      caption: 'Resolve pending actions',
      icon: Icons.task_alt_rounded,
      onTap: (context) async => context.go(AppRoutes.reviewCenter),
    ),
  ];
}

List<AppFabAction> reviewFabActions() {
  return [
    AppFabAction(
      type: FabActionType.uploadExpense,
      label: 'Upload expense',
      caption: 'Scan or import a receipt',
      icon: Icons.add_photo_alternate_outlined,
      isPrimary: true,
      onTap: (_) async {},
    ),
    AppFabAction(
      type: FabActionType.documents,
      label: 'Documents',
      caption: 'Open extraction inbox',
      icon: Icons.description_outlined,
      onTap: (context) async => context.go(AppRoutes.documents),
    ),
    AppFabAction(
      type: FabActionType.products,
      label: 'Products',
      caption: 'Stock and pricing',
      icon: Icons.inventory_2_outlined,
      onTap: (context) async => context.go(AppRoutes.products),
    ),
    AppFabAction(
      type: FabActionType.salesImport,
      label: 'Import sales report',
      caption: 'Upload POS export data',
      icon: Icons.upload_file_rounded,
      onTap: (context) async => context.push(AppRoutes.salesImport),
    ),
  ];
}
