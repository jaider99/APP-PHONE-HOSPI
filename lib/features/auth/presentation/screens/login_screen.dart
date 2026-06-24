import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/shared/ui/ui.dart';

/// Editorial login screen — warm bone background, deep-teal accent.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final result = await authService.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    result.when(
      success: (_) {
        context.go(AppRoutes.dashboard);
      },
      failure: (error) {
        setState(() => _errorMessage = error.toString());
      },
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Brand mark ───────────────────────────────────────
                    const _BrandMark(),

                    const SizedBox(height: AppSpacing.xl),

                    // ── Eyebrow + title ──────────────────────────────────
                    Text(
                      'welcome back',
                      style: EditorialTypography.labelSmall.copyWith(
                        color: EditorialColors.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in',
                      style: EditorialTypography.headlineMedium.copyWith(
                        color: EditorialColors.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: AppSpacing.xxl),

                    // ── Error ────────────────────────────────────────────
                    if (_errorMessage != null) ...[
                      InlineHint(
                        eyebrow: 'sign-in failed',
                        message: _errorMessage!,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // ── Email ────────────────────────────────────────────
                    _EditorialField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'you@company.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      prefixIcon: Icons.email_outlined,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── Password ─────────────────────────────────────────
                    _EditorialField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: '••••••••',
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _signIn(),
                      prefixIcon: Icons.lock_outline,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: EditorialColors.onSurfaceVariant,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    // ── Forgot ───────────────────────────────────────────
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          // TODO: navigate to forgot password
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          foregroundColor: EditorialColors.accent,
                        ),
                        child: Text(
                          'Forgot password?',
                          style: EditorialTypography.labelMedium.copyWith(
                            color: EditorialColors.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // ── Submit ───────────────────────────────────────────
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: EditorialColors.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              EditorialColors.surfaceContainerHigh,
                          disabledForegroundColor:
                              EditorialColors.onSurfaceVariant,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(EditorialRadius.md),
                          ),
                          textStyle:
                              EditorialTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    // ── Divider ──────────────────────────────────────────
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(
                            color: EditorialColors.hairline,
                            height: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Text(
                            'or continue with',
                            style: EditorialTypography.labelSmall.copyWith(
                              color: EditorialColors.onSurfaceVariant,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(
                            color: EditorialColors.hairline,
                            height: 1,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // ── Social ───────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _SocialButton(
                            label: 'Google',
                            icon: Icons.g_mobiledata,
                            onPressed: () {
                              // TODO: Google sign in
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _SocialButton(
                            label: 'Apple',
                            icon: Icons.apple,
                            onPressed: () {
                              // TODO: Apple sign in
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BRAND MARK (flat — no gradient)
// ─────────────────────────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: EditorialColors.accent,
          borderRadius: BorderRadius.circular(EditorialRadius.md),
        ),
        child: const Icon(
          Icons.restaurant_menu,
          size: 28,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDITORIAL TEXT FIELD
// ─────────────────────────────────────────────────────────────────────────────

class _EditorialField extends StatelessWidget {
  const _EditorialField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.obscureText = false,
    this.prefixIcon,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toLowerCase(),
          style: EditorialTypography.labelSmall.copyWith(
            color: EditorialColors.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          obscureText: obscureText,
          cursorColor: EditorialColors.accent,
          style: EditorialTypography.bodyMedium.copyWith(
            color: EditorialColors.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: EditorialTypography.bodyMedium.copyWith(
              color: EditorialColors.onSurfaceVariant,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    size: 18,
                    color: EditorialColors.onSurfaceVariant,
                  )
                : null,
            suffixIcon: suffix,
            filled: true,
            fillColor: EditorialColors.surfaceContainerLowest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(EditorialRadius.md),
              borderSide:
                  const BorderSide(color: EditorialColors.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(EditorialRadius.md),
              borderSide:
                  const BorderSide(color: EditorialColors.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(EditorialRadius.md),
              borderSide: const BorderSide(
                color: EditorialColors.accent,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(EditorialRadius.md),
              borderSide:
                  const BorderSide(color: EditorialColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(EditorialRadius.md),
              borderSide: const BorderSide(
                color: EditorialColors.error,
                width: 1.5,
              ),
            ),
            errorStyle: EditorialTypography.labelSmall.copyWith(
              color: EditorialColors.error,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SOCIAL BUTTON (flat, hairline border)
// ─────────────────────────────────────────────────────────────────────────────

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22, color: EditorialColors.onSurface),
        label: Text(
          label,
          style: EditorialTypography.labelLarge.copyWith(
            color: EditorialColors.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: EditorialColors.surfaceContainerLowest,
          side: const BorderSide(color: EditorialColors.hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EditorialRadius.md),
          ),
        ),
      ),
    );
  }
}
