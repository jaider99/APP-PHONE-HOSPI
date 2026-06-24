import 'package:hospi_dash/core/router/app_router.dart';

enum AppRouteType {
  root,
  detail,
  create,
  edit,
  import,
  setup,
  modal,
  auth,
}

enum ShellFabActionSet {
  global,
  dashboard,
  documents,
  sales,
  orders,
  products,
  providers,
  expenses,
  reviewCenter,
}

class RouteUiConfig {
  const RouteUiConfig({
    required this.routeType,
    required this.showBottomNav,
    required this.showFab,
    required this.showBackButton,
    this.backFallbackRoute,
    this.fabActionSet = ShellFabActionSet.global,
  });

  final AppRouteType routeType;
  final bool showBottomNav;
  final bool showFab;
  final bool showBackButton;
  final String? backFallbackRoute;
  final ShellFabActionSet fabActionSet;
}

abstract final class RouteUiResolver {
  static const RouteUiConfig _auth = RouteUiConfig(
    routeType: AppRouteType.auth,
    showBottomNav: false,
    showFab: false,
    showBackButton: false,
  );

  static RouteUiConfig resolve(String location) {
    if (AppRoutes.isAuthRoute(location)) return _auth;

    if (location == AppRoutes.expenseForm) {
      return const RouteUiConfig(
        routeType: AppRouteType.create,
        showBottomNav: false,
        showFab: false,
        showBackButton: true,
        backFallbackRoute: AppRoutes.expenses,
      );
    }

    if (_matchesPattern(location, AppRoutes.productDetail)) {
      return const RouteUiConfig(
        routeType: AppRouteType.detail,
        showBottomNav: false,
        showFab: false,
        showBackButton: true,
        backFallbackRoute: AppRoutes.products,
      );
    }

    if (location == AppRoutes.dashboard) {
      return _shellRoot(ShellFabActionSet.dashboard);
    }
    if (location == AppRoutes.reviewCenter) {
      return _shellRoot(ShellFabActionSet.reviewCenter);
    }
    if (location == AppRoutes.sales) {
      return _shellRoot(ShellFabActionSet.sales);
    }
    if (location == AppRoutes.salesImport) {
      return const RouteUiConfig(
        routeType: AppRouteType.import,
        showBottomNav: true,
        showFab: true,
        showBackButton: true,
        backFallbackRoute: AppRoutes.sales,
        fabActionSet: ShellFabActionSet.sales,
      );
    }
    if (location == AppRoutes.salesConnectPos) {
      return const RouteUiConfig(
        routeType: AppRouteType.setup,
        showBottomNav: true,
        showFab: true,
        showBackButton: true,
        backFallbackRoute: AppRoutes.sales,
        fabActionSet: ShellFabActionSet.sales,
      );
    }
    if (_matchesPattern(location, AppRoutes.saleDetail)) {
      return _shellDetail(AppRoutes.sales, ShellFabActionSet.sales);
    }
    if (location == AppRoutes.documents) {
      return _shellRoot(ShellFabActionSet.documents);
    }
    if (location == AppRoutes.documentReviewQueue) {
      return const RouteUiConfig(
        routeType: AppRouteType.setup,
        showBottomNav: true,
        showFab: true,
        showBackButton: true,
        backFallbackRoute: AppRoutes.documents,
        fabActionSet: ShellFabActionSet.documents,
      );
    }
    if (_matchesPattern(location, AppRoutes.documentDetail)) {
      return const RouteUiConfig(
        routeType: AppRouteType.modal,
        showBottomNav: true,
        showFab: true,
        showBackButton: false,
        fabActionSet: ShellFabActionSet.documents,
      );
    }
    if (location == AppRoutes.orders) {
      return _shellRoot(ShellFabActionSet.orders);
    }
    if (_matchesPattern(location, AppRoutes.orderDetail)) {
      return _shellDetail(AppRoutes.orders, ShellFabActionSet.orders);
    }
    if (location == AppRoutes.providers) {
      return _shellRoot(ShellFabActionSet.providers);
    }
    if (_matchesPattern(location, AppRoutes.providerDetail)) {
      return _shellDetail(AppRoutes.providers, ShellFabActionSet.providers);
    }
    if (location == AppRoutes.expenses) {
      return _shellRoot(ShellFabActionSet.expenses);
    }
    if (location == AppRoutes.products) {
      return _shellRoot(ShellFabActionSet.products);
    }

    return _shellRoot(ShellFabActionSet.global);
  }

  static RouteUiConfig _shellRoot(ShellFabActionSet fabActionSet) {
    return RouteUiConfig(
      routeType: AppRouteType.root,
      showBottomNav: true,
      showFab: true,
      showBackButton: false,
      fabActionSet: fabActionSet,
    );
  }

  static RouteUiConfig _shellDetail(
    String backFallbackRoute,
    ShellFabActionSet fabActionSet,
  ) {
    return RouteUiConfig(
      routeType: AppRouteType.detail,
      showBottomNav: true,
      showFab: true,
      showBackButton: true,
      backFallbackRoute: backFallbackRoute,
      fabActionSet: fabActionSet,
    );
  }

  static bool _matchesPattern(String location, String pattern) {
    if (location == pattern) return true;
    final base = pattern.split('/:').first;
    return base.isNotEmpty && location.startsWith('$base/');
  }
}