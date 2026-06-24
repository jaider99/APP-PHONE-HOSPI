import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/models/auth_result.dart';
import 'package:hospi_dash/models/auth_state.dart';
import 'package:hospi_dash/models/registration_models.dart';
import 'package:hospi_dash/providers/auth_provider.dart';
import 'package:hospi_dash/providers/registration_provider.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';
import 'package:hospi_dash/widgets/auth/otp_input.dart';
import 'package:hospi_dash/widgets/auth/primary_button.dart';

/// OTP verification screen for SMS/email code entry.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    super.key,
    required this.phoneOrEmail,
  });

  final String phoneOrEmail;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _otpCode = '';

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: EditorialColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: EditorialColors.accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // SAFETY: always check mounted after every await
  Future<void> _handleVerify() async {
    if (_otpCode.length < 5) return;

    final result = await ref.read(authNotifierProvider.notifier).verifyOtp(
          email: widget.phoneOrEmail,
          token: _otpCode,
        );

    if (!mounted) return;

    if (result is AuthFailure) {
      _showError(result.message);
    } else if (result is AuthSuccess) {
      final registrationState = ref.read(registrationProvider);
      if (registrationState.step == RegistrationStep.emailVerification) {
        final setupResult = await ref
            .read(registrationProvider.notifier)
            .completePendingSetup();

        if (!mounted) return;

        setupResult.when(
          ownerSuccess: (_) => context.go(AppRoutes.dashboard),
          managerPending: (companyName) => context.go(
            AppRoutes.pendingApproval,
            extra: companyName,
          ),
          emailVerificationPending: (email, role) => _showError(
            'Your email is verified, but your session is not active yet. Please sign in again to finish setup.',
          ),
          failure: (_, message) => _showError(message),
        );
      } else {
        context.go(AppRoutes.dashboard);
      }
    }
  }

  // SAFETY: always check mounted after every await
  Future<void> _handleResend() async {
    final result = await ref.read(authNotifierProvider.notifier).resendOtp(
          widget.phoneOrEmail,
        );

    if (!mounted) return;

    if (result is AuthFailure) {
      _showError(result.message);
    } else {
      _showSuccess('Verification code sent to ${widget.phoneOrEmail}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.maybeWhen(
      data: (state) => state.status == AuthStatus.loading,
      loading: () => true,
      orElse: () => false,
    );

    // Get resend cooldown from state (60 second cooldown)
    final canResend = authState.maybeWhen(
      data: (state) =>
          state.lastOtpSentAt == null ||
          DateTime.now().difference(state.lastOtpSentAt!).inSeconds >= 60,
      orElse: () => true,
    );

    return Scaffold(
      backgroundColor: EditorialColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),

              // Back button row
              Align(
                alignment: Alignment.centerLeft,
                child: const AppBackButton(
                  fallbackRoute: AppRoutes.signIn,
                  size: 48,
                ),
              ),
              const SizedBox(height: 40),

              // Title
              Text(
                'Enter OTP Code',
                style: EditorialTypography.headlineMedium.copyWith(
                  color: EditorialColors.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Check your SMS! We\'ve sent a one-time verification code to ${widget.phoneOrEmail}. Enter the code below to verify your account.',
                  style: EditorialTypography.bodyMedium.copyWith(
                    color: EditorialColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 40),

              // OTP input
              OtpInput(
                onCompleted: (code) {
                  setState(() => _otpCode = code);
                  _handleVerify();
                },
                onChanged: (code) {
                  setState(() => _otpCode = code);
                },
              ),
              const SizedBox(height: 40),

              // Continue button
              PrimaryButton(
                text: 'Continue',
                isLoading: isLoading,
                isEnabled: _otpCode.length == 5,
                onPressed: _handleVerify,
              ),
              const SizedBox(height: 24),

              // Resend OTP
              GestureDetector(
                onTap: canResend ? _handleResend : null,
                child: RichText(
                  text: TextSpan(
                    style: EditorialTypography.bodyMedium.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                    ),
                    children: [
                      const TextSpan(text: "Didn't get OTP? "),
                      TextSpan(
                        text: canResend ? 'Resend OTP' : 'Wait to resend',
                        style: EditorialTypography.labelLarge.copyWith(
                          color: canResend
                              ? EditorialColors.onSurface
                              : EditorialColors.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
