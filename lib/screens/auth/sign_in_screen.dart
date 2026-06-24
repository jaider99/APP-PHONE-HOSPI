import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/models/auth_result.dart';
import 'package:hospi_dash/models/auth_state.dart';
import 'package:hospi_dash/providers/auth_provider.dart';
import 'package:hospi_dash/widgets/auth/auth_text_field.dart';
import 'package:hospi_dash/widgets/auth/custom_checkbox.dart';
import 'package:hospi_dash/widgets/auth/oauth_button.dart';
import 'package:hospi_dash/widgets/auth/primary_button.dart';

/// Sign in screen with email/password form, OAuth options, and biometric login.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _rememberMe = false;
  bool _showBiometric = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkBiometricAvailability();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricAvailability() async {
    final biometricService = ref.read(biometricServiceProvider);
    final shouldShow = await biometricService.shouldShowBiometricPrompt();
    if (mounted) {
      setState(() => _showBiometric = shouldShow);
    }
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

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    
    final result = await ref.read(authNotifierProvider.notifier).signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      rememberMe: _rememberMe,
    );

    if (!mounted) return;

    switch (result) {
      case AuthSuccess():
        context.go('/dashboard');
      case AuthFailure(message: final msg):
        _showError(msg);
      case AuthPendingVerification(email: final email):
        context.push('/otp-verify', extra: email);
    }
  }

  // SAFETY: always check mounted after every await
  Future<void> _handleBiometricSignIn() async {
    final result = await ref.read(authNotifierProvider.notifier).signInWithBiometrics();
    if (!mounted) return;
    
    if (result is AuthFailure) {
      _showError(result.message);
    }
  }

  // SAFETY: always check mounted after every await
  Future<void> _handleGoogleSignIn() async {
    final result = await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    
    if (result is AuthFailure) {
      _showError(result.message);
    }
  }

  // SAFETY: always check mounted after every await
  Future<void> _handleAppleSignIn() async {
    final result = await ref.read(authNotifierProvider.notifier).signInWithApple();
    if (!mounted) return;
    
    if (result is AuthFailure) {
      _showError(result.message);
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 64),
                  
                  // Title
                  Text(
                    'Welcome back',
                    style: EditorialTypography.headlineMedium.copyWith(
                      color: EditorialColors.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  
                  // Subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Access your orders, wishlist, and exclusive offers by logging in.',
                      style: EditorialTypography.bodyMedium.copyWith(
                        color: EditorialColors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Email field
                  AuthTextField(
                    label: 'Email',
                    hint: 'Enter your email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Email is required';
                      }
                      if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(value.trim())) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  // Password field
                  AuthTextField(
                    label: 'Password',
                    hint: 'Enter your password',
                    controller: _passwordController,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleSignIn(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Remember me + Forgot password row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CustomCheckbox(
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() => _rememberMe = value);
                        },
                      ),
                      GestureDetector(
                        onTap: () => context.push('/forgot-password'),
                        child: Text(
                          'Forgot password?',
                          style: EditorialTypography.bodyMedium.copyWith(
                            color: EditorialColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Sign in button
                  PrimaryButton(
                    text: 'Sign in',
                    isLoading: isLoading,
                    onPressed: _handleSignIn,
                  ),
                  
                  // Biometric login button
                  if (_showBiometric) ...[
                    const SizedBox(height: 16),
                    _BiometricButton(onPressed: _handleBiometricSignIn),
                  ],
                  const SizedBox(height: 24),
                  
                  // OR divider
                  const _OrDivider(),
                  const SizedBox(height: 24),
                  
                  // Google OAuth
                  OAuthButton(
                    provider: OAuthProvider.google,
                    onPressed: _handleGoogleSignIn,
                  ),
                  const SizedBox(height: 12),
                  
                  // Apple OAuth
                  OAuthButton(
                    provider: OAuthProvider.apple,
                    onPressed: _handleAppleSignIn,
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Sign up link
                  GestureDetector(
                    onTap: () => context.push('/register/company-id'),
                    child: RichText(
                      text: TextSpan(
                        style: EditorialTypography.bodyMedium.copyWith(
                          color: EditorialColors.onSurfaceVariant,
                        ),
                        children: [
                          const TextSpan(text: "Don't have an account? "),
                          TextSpan(
                            text: 'Sign up',
                            style: EditorialTypography.labelLarge.copyWith(
                              color: EditorialColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(color: EditorialColors.dividerLight),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: EditorialTypography.labelSmall.copyWith(
              color: EditorialColors.outline,
            ),
          ),
        ),
        Expanded(
          child: Divider(color: EditorialColors.dividerLight),
        ),
      ],
    );
  }
}

class _BiometricButton extends StatelessWidget {
  const _BiometricButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = Platform.isIOS ? Icons.face : Icons.fingerprint;
    final label = Platform.isIOS ? 'Sign in with Face ID' : 'Sign in with Fingerprint';

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: EditorialColors.dividerLight),
          borderRadius: EditorialRadius.borderRadiusStandard,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: EditorialColors.onSurface),
            const SizedBox(width: 8),
            Text(
              label,
              style: EditorialTypography.labelLarge.copyWith(
                color: EditorialColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
