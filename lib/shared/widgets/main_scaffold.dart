import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/navigation/route_ui_config.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/shared/fab/floating_action_hub.dart';
import 'package:hospi_dash/shared/ui/app_bottom_nav.dart';

/// Main scaffold for routes that live inside the bottom-nav shell.
///
/// Renders the shell content with a floating glass navigation layer.
class MainScaffold extends ConsumerWidget {
  const MainScaffold({
    required this.child,
    super.key,
  });

  final Widget child;

  static const List<AppBottomNavItem> _navItems = [
    AppBottomNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    AppBottomNavItem(
      icon: Icons.trending_up_outlined,
      activeIcon: Icons.trending_up_rounded,
      label: 'Sales',
    ),
    AppBottomNavItem(
      icon: Icons.description_outlined,
      activeIcon: Icons.description_rounded,
      label: 'Docs',
    ),
    AppBottomNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      label: 'Orders',
    ),
  ];

  static const List<String> _routes = [
    AppRoutes.dashboard,
    AppRoutes.sales,
    AppRoutes.documents,
    AppRoutes.orders,
  ];

  static int _indexFromLocation(String location) {
    if (location.startsWith(AppRoutes.dashboard)) return 0;
    if (location.startsWith(AppRoutes.sales)) return 1;
    if (location.startsWith(AppRoutes.documents)) return 2;
    if (location.startsWith(AppRoutes.orders)) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final routeUiConfig = RouteUiResolver.resolve(location);
    final currentIndex = _indexFromLocation(location);

    // Capture the router during build so the tap callback never looks up a
    // potentially-deactivated widget's ancestor.
    final router = GoRouter.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Stack(
        children: [
          Positioned.fill(child: child),
          if (routeUiConfig.showFab)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 18),
                child: FloatingActionHub.route(
                  ref: ref,
                  actionSet: routeUiConfig.fabActionSet,
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomNav(
              items: _navItems,
              currentIndex: currentIndex,
              hasCenterFab: routeUiConfig.showFab,
              onTap: (i) {
                if (i == currentIndex) return;
                router.go(_routes[i]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
