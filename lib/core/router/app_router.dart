import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/features/documents/presentation/screens/document_merge_review_screen.dart';
import 'package:hospi_dash/features/auth/presentation/screens/login_screen.dart';
import 'package:hospi_dash/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:hospi_dash/features/documents/presentation/screens/documents_screen.dart';
import 'package:hospi_dash/features/orders/presentation/screens/orders_screen.dart';
import 'package:hospi_dash/features/providers/presentation/screens/providers_screen.dart';
import 'package:hospi_dash/features/providers/presentation/screens/supplier_detail_screen.dart';
import 'package:hospi_dash/features/review_center/presentation/screens/review_center_screen.dart';
import 'package:hospi_dash/features/sales/presentation/screens/connect_pos_screen.dart';
import 'package:hospi_dash/features/sales/presentation/screens/import_sales_screen.dart';
import 'package:hospi_dash/features/sales/presentation/screens/sales_screen.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/providers/auth_provider.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/providers/registration_provider.dart';
import 'package:hospi_dash/screens/auth/sign_in_screen.dart';
import 'package:hospi_dash/screens/auth/otp_screen.dart';
import 'package:hospi_dash/screens/auth/forgot_password_screen.dart';
import 'package:hospi_dash/screens/registration/company_id_screen.dart';
import 'package:hospi_dash/screens/registration/company_details_screen.dart'
    as registration;
import 'package:hospi_dash/screens/registration/user_account_screen.dart';
import 'package:hospi_dash/screens/registration/pending_approval_screen.dart';
import 'package:hospi_dash/features/expenses/presentation/providers/expense_form_provider.dart';
import 'package:hospi_dash/features/expenses/presentation/screens/expense_form_screen.dart';
import 'package:hospi_dash/features/expenses/presentation/screens/expense_tracker_screen.dart';
import 'package:hospi_dash/features/products/presentation/screens/product_list_screen.dart';
import 'package:hospi_dash/features/products/presentation/screens/product_detail_screen.dart';
import 'package:hospi_dash/shared/widgets/main_scaffold.dart';

/// Route paths
abstract class AppRoutes {
  // Auth routes
  static const String login = '/login';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String otpVerify = '/otp-verify';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String bootstrapRecovery = '/bootstrap-recovery';
  static const String home = '/dashboard'; // Alias for authenticated home

  // New 3-step registration flow
  static const String registerCompanyId = '/register/company-id';
  static const String registerCompanyDetails = '/register/company-details';
  static const String registerUserAccount = '/register/user-account';
  static const String pendingApproval = '/pending-approval';

  // Main app routes
  static const String dashboard = '/dashboard';
  static const String sales = '/sales';
  static const String salesImport = '/sales/import';
  static const String salesConnectPos = '/sales/connect-pos';
  static const String documents = '/documents';
  static const String documentReviewQueue = '/documents/review-queue';
  static const String reviewCenter = '/review-center';
  static const String orders = '/orders';
  static const String providers = '/providers';

  // Nested routes
  static const String saleDetail = '/sales/:id';
  static const String documentDetail = '/documents/:id';
  static const String orderDetail = '/orders/:id';
  static const String providerDetail = '/providers/:id';

  // Expenses
  static const String expenses = '/expenses';
  static const String expenseForm = '/expenses/new';

  // Products
  static const String products = '/products';
  static const String productDetail = '/products/:id';

  // Settings
  static const String settings = '/settings';
  static const String profile = '/settings/profile';

  /// Check if route is an auth route (no login required)
  static bool isAuthRoute(String path) {
    return path == login ||
        path == signIn ||
        path == signUp ||
        path == otpVerify ||
        path == register ||
        path == forgotPassword ||
        path == bootstrapRecovery ||
        path == pendingApproval ||
        path.startsWith('/register/');
  }
}

      const _routeGuardTimeout = Duration(seconds: 10);

/// Provider for the app router
final appRouterProvider = Provider<GoRouter>((ref) {
  // Navigator keys are scoped inside the Provider callback so they are created
  // alongside the GoRouter and never outlive it. Placing them at the module
  // top-level causes "Duplicate GlobalKey" on hot-restart because the old
  // tree teardown can race with the new tree build.
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

  // DO NOT watch authNotifierProvider here — watching it causes GoRouter to be
  // recreated on every auth change, which tears the entire widget tree down and
  // causes "ancestor is not our descendant" assertion errors.
  // Instead, read auth state inside the redirect callback each time it runs.
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.signIn,
    debugLogDiagnostics: true,
    refreshListenable: _GoRouterRefreshStream(
      ref.read(authServiceProvider).authStateChanges,
    ),
    redirect: (context, state) async {
      // Read current auth state at redirect time so we always get fresh state
      // without causing the provider (and GoRouter) to rebuild.
      final authState = ref.read(authNotifierProvider);
      final currentAuthState = authState.valueOrNull;
      final matchedLocation = state.matchedLocation;
      final isAuthRoute = AppRoutes.isAuthRoute(matchedLocation);

      // Still loading auth state - don't redirect
      if (authState.isLoading || currentAuthState == null) {
        return null;
      }

      final isAuthenticated = currentAuthState.isAuthenticated;
      final isPendingOtp = currentAuthState.isPendingOtp;

      // Pending OTP - allow OTP screen only
      if (isPendingOtp) {
        if (matchedLocation != AppRoutes.otpVerify) {
          return AppRoutes.otpVerify;
        }
        return null;
      }

      // Unauthenticated users trying to access protected routes
      if (!isAuthenticated && !isAuthRoute) {
        return AppRoutes.signIn;
      }

      if (isAuthenticated && !isAuthRoute) {
        final pendingResult = await _readRouteGuardFuture(
          'pending approval',
          ref.read(isPendingApprovalProvider.future),
        );
        if (!pendingResult.succeeded) return AppRoutes.bootstrapRecovery;

        final isPendingApproval = pendingResult.value ?? false;
        if (isPendingApproval && matchedLocation != AppRoutes.pendingApproval) {
          return AppRoutes.pendingApproval;
        }

        final companyResult = await _readRouteGuardFuture(
          'company id',
          ref.read(companyIdProvider.future),
        );
        if (!companyResult.succeeded) return AppRoutes.bootstrapRecovery;

        final companyId = companyResult.value;
        if (companyId == null && !isPendingApproval) {
          return AppRoutes.registerCompanyId;
        }
      }

      // Authenticated users trying to access auth routes
      // EXCEPT registration routes — the registration flow calls auth.signUp()
      // mid-process, which creates a session. If we redirect here, the
      // remaining company/member inserts would be interrupted.
      // EXCEPT pending-approval — managers need to stay on this screen.
      if (isAuthenticated &&
          isAuthRoute &&
          !matchedLocation.startsWith('/register/') &&
          matchedLocation != AppRoutes.otpVerify &&
          matchedLocation != AppRoutes.pendingApproval) {
        return AppRoutes.dashboard;
      }

      return null;
    },
    routes: [
      // Auth routes (outside shell)
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        redirect: (context, state) => AppRoutes.registerCompanyId,
      ),
      GoRoute(
        path: AppRoutes.otpVerify,
        builder: (context, state) {
          final phoneOrEmail = state.extra as String? ?? '';
          return OtpScreen(phoneOrEmail: phoneOrEmail);
        },
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.bootstrapRecovery,
        builder: (context, state) => const _BootstrapRecoveryScreen(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // NEW 3-STEP REGISTRATION FLOW
      // Step 1: Company ID (country, tax ID, venue type)
      // Step 2: Company Details (legal name, trade name, city, currency, timezone)
      // Step 3: User Account (full name, email, password, role) - ALL writes here
      // ═══════════════════════════════════════════════════════════════════
      GoRoute(
        path: AppRoutes.registerCompanyId,
        builder: (context, state) => const CompanyIdScreen(),
      ),
      GoRoute(
        path: AppRoutes.registerCompanyDetails,
        redirect: (context, state) {
          // Guard: redirect to Step 1 if Step 1 data is missing
          final container = ProviderScope.containerOf(context);
          final notifier = container.read(registrationProvider.notifier);
          if (!notifier.isStep1Complete) {
            return AppRoutes.registerCompanyId;
          }
          return null;
        },
        builder: (context, state) => const registration.CompanyDetailsScreen(),
      ),
      GoRoute(
        path: AppRoutes.registerUserAccount,
        redirect: (context, state) {
          // Guard: redirect to Step 2 if Step 2 data is missing
          final container = ProviderScope.containerOf(context);
          final notifier = container.read(registrationProvider.notifier);
          if (!notifier.isStep2Complete) {
            if (!notifier.isStep1Complete) {
              return AppRoutes.registerCompanyId;
            }
            return AppRoutes.registerCompanyDetails;
          }
          return null;
        },
        builder: (context, state) => const UserAccountScreen(),
      ),

      // Pending approval screen (for managers awaiting owner approval)
      GoRoute(
        path: AppRoutes.pendingApproval,
        builder: (context, state) {
          final companyName = state.extra as String?;
          return PendingApprovalScreen(companyName: companyName);
        },
      ),

      // Expense form (fullscreen, outside shell — no bottom nav)
      GoRoute(
        path: AppRoutes.expenseForm,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          final ExpenseFormArgs args;
          if (extra is ExpenseFormArgs) {
            args = extra;
          } else if (extra is Map<String, dynamic>) {
            args = ExpenseFormArgs.fromMap(extra);
          } else {
            throw ArgumentError(
              'Missing or invalid expense form args in route extra',
            );
          }
          return ExpenseFormScreen(args: args);
        },
      ),

      // Main app shell with bottom navigation
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          // Dashboard
          GoRoute(
            path: AppRoutes.dashboard,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),

          // Review Center
          GoRoute(
            path: AppRoutes.reviewCenter,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReviewCenterScreen(),
            ),
          ),

          // Sales
          GoRoute(
            path: AppRoutes.sales,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SalesScreen(),
            ),
            routes: [
              GoRoute(
                path: 'import',
                builder: (context, state) {
                  final extra = state.extra;
                  final prefill = extra is SalesImportPrefill
                      ? extra
                      : extra is Map<String, dynamic>
                          ? SalesImportPrefill.fromMap(extra)
                          : null;
                  return ImportSalesScreen(prefill: prefill);
                },
              ),
              GoRoute(
                path: 'connect-pos',
                builder: (context, state) => const ConnectPosScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return SalesScreen(saleId: id);
                },
              ),
            ],
          ),

          // Documents
          GoRoute(
            path: AppRoutes.documents,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DocumentsScreen(),
            ),
            routes: [
              GoRoute(
                path: 'review-queue',
                builder: (context, state) => const DocumentMergeReviewScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return DocumentsScreen(documentId: id);
                },
              ),
            ],
          ),

          // Orders
          GoRoute(
            path: AppRoutes.orders,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: OrdersScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return OrdersScreen(orderId: id);
                },
              ),
            ],
          ),

          // Providers (Suppliers)
          GoRoute(
            path: AppRoutes.providers,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProvidersScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return SupplierDetailScreen(supplierId: id);
                },
              ),
            ],
          ),

          // Expense Tracker
          GoRoute(
            path: AppRoutes.expenses,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ExpenseTrackerScreen(),
            ),
          ),

          // Products catalogue
          GoRoute(
            path: AppRoutes.products,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProductListScreen(),
            ),
          ),
        ],
      ),

      // Product detail (fullscreen, outside shell — no bottom nav)
      GoRoute(
        path: AppRoutes.productDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ProductDetailScreen(productId: id);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.error?.toString() ?? 'Unknown error',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.dashboard),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});

/// Helper class to convert a Stream into a ChangeNotifier for GoRouter
/// This allows the router to reactively update on auth state changes
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen(
      (_) {
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('GoRouter auth refresh stream error: $error');
      },
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _RouteGuardResult<T> {
  const _RouteGuardResult._({required this.succeeded, this.value});

  const _RouteGuardResult.success(T value)
      : this._(succeeded: true, value: value);

  const _RouteGuardResult.failure() : this._(succeeded: false);

  final bool succeeded;
  final T? value;
}

Future<_RouteGuardResult<T>> _readRouteGuardFuture<T>(
  String label,
  Future<T> future,
) async {
  try {
    final value = await future.timeout(_routeGuardTimeout);
    return _RouteGuardResult.success(value);
  } catch (error) {
    debugPrint('GoRouter guard $label failed: $error');
    return const _RouteGuardResult.failure();
  }
}

class _BootstrapRecoveryScreen extends StatelessWidget {
  const _BootstrapRecoveryScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not start HospiDash',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Check your connection and try again.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.dashboard),
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await SupabaseService.client.auth.signOut();
                    if (context.mounted) context.go(AppRoutes.signIn);
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
