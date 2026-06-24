import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/models/auth_result.dart';
import 'package:hospi_dash/models/auth_state.dart';
import 'package:hospi_dash/providers/auth_provider.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';
import 'package:hospi_dash/widgets/auth/auth_text_field.dart';
import 'package:hospi_dash/widgets/auth/primary_button.dart';

/// Forgot password screen with email input to request reset link.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

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

  Future<void> _handleSendReset() async {
    if (!_formKey.currentState!.validate()) return;
    
    final result = await ref.read(authNotifierProvider.notifier).sendPasswordReset(
      _emailController.text.trim(),
    );

    if (result is AuthFailure) {
      _showError(result.message);
    } else {
      _showSuccess('Password reset email sent to ${_emailController.text.trim()}');
      // Go back to sign in
      if (mounted) {
        context.go('/sign-in');
      }
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

    return Scaffold(
      backgroundColor: EditorialColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
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
                  'Forgot Password',
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
                    'Enter your email address and we\'ll send you a link to reset your password.',
                    style: EditorialTypography.bodyMedium.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
                
                // Email field
                AuthTextField(
                  label: 'Email',
                  hint: 'Enter your email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleSendReset(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Email is required';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                
                // Send button
                PrimaryButton(
                  text: 'Send Reset Link',
                  isLoading: isLoading,
                  onPressed: _handleSendReset,
                ),
                const SizedBox(height: 24),
                
                // Back to sign in
                GestureDetector(
                  onTap: () => context.go('/sign-in'),
                  child: RichText(
                    text: TextSpan(
                      style: EditorialTypography.bodyMedium.copyWith(
                        color: EditorialColors.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'Remember your password? '),
                        TextSpan(
                          text: 'Sign in',
                          style: EditorialTypography.labelLarge.copyWith(
                            color: EditorialColors.onSurface,
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
      ),
    );
  }
}
