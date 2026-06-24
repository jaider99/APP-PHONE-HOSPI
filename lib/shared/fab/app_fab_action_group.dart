import 'package:flutter/material.dart';

import 'app_fab_action.dart';

class AppFabActionGroup {
  const AppFabActionGroup({
    required this.title,
    required this.actions,
    this.subtitle,
    this.leadingIcon,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final List<AppFabAction> actions;
}
