import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Screen shown to managers after registration while awaiting owner approval.
///
/// Features:
///   - Hourglass icon + "Access Pending" title
///   - Shows which company they requested access to
///   - Supabase Realtime listener: auto-navigates to /dashboard
///     when company_users.is_active flips to true
///   - "Resend Verification Email" button
///   - "Wrong company? Start over" link
class PendingApprovalScreen extends ConsumerStatefulWidget {
  final String? companyName;

  const PendingApprovalScreen({super.key, this.companyName});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  RealtimeChannel? _channel;
  bool _resendingEmail = false;

  @override
  void initState() {
    super.initState();
    _subscribeToApproval();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  /// Listen for realtime changes on the company_users table.
  /// When is_active becomes true, navigate to /dashboard.
  void _subscribeToApproval() {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;

    _channel = SupabaseService.client
        .channel('pending-approval-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'company_users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord['is_active'] == true && mounted) {
              context.go('/dashboard');
            }
          },
        )
        .subscribe();
  }

  Future<void> _resendVerificationEmail() async {
    final email = SupabaseService.currentUser?.email;
    if (email == null) return;

    setState(() => _resendingEmail = true);

    try {
      await SupabaseService.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verification email sent to $email',
            style: EditorialTypography.bodyMedium.copyWith(color: Colors.white),
          ),
          backgroundColor: EditorialColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: EditorialRadius.borderRadiusStandard,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send email. Please try again later.',
            style: EditorialTypography.bodyMedium.copyWith(color: Colors.white),
          ),
          backgroundColor: EditorialColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: EditorialRadius.borderRadiusStandard,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _resendingEmail = false);
    }
  }

  Future<void> _signOutAndRestart() async {
    await SupabaseService.client.auth.signOut();
    if (!mounted) return;
    context.go('/register/company-id');
  }

  @override
  Widget build(BuildContext context) {
    final companyName = widget.companyName ?? 'your company';

    return Scaffold(
      backgroundColor: EditorialColors.background,
      body: Stack(
        children: [
          _buildBackgroundDecorations(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hourglass icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: EditorialColors.warningLight,
                        borderRadius: EditorialRadius.borderRadiusLg,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          size: 40,
                          color: EditorialColors.warning,
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .scale(begin: const Offset(0.8, 0.8)),

                    const SizedBox(height: 32),

                    // Title
                    Text(
                      'Access Pending',
                      style: EditorialTypography.headlineMedium,
                    ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

                    const SizedBox(height: 12),

                    // Description
                    Text(
                      'Your request to join $companyName has been submitted. '
                      'The owner will review and approve your access.',
                      textAlign: TextAlign.center,
                      style: EditorialTypography.bodyLarge.copyWith(
                        color: EditorialColors.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                    const SizedBox(height: 40),

                    // Status info card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: EditorialColors.surfaceContainerLowest,
                        borderRadius: EditorialRadius.borderRadiusStandard,
                        border: Border.all(color: EditorialColors.surfaceContainerHigh),
                      ),
                      child: Column(
                        children: [
                          _buildStatusRow(
                            Icons.check_circle_rounded,
                            EditorialColors.success,
                            'Account created',
                          ),
                          const SizedBox(height: 12),
                          _buildStatusRow(
                            Icons.check_circle_rounded,
                            EditorialColors.success,
                            'Access request sent',
                          ),
                          const SizedBox(height: 12),
                          _buildStatusRow(
                            Icons.hourglass_top_rounded,
                            EditorialColors.warning,
                            'Waiting for owner approval',
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

                    const SizedBox(height: 32),

                    // Realtime hint
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: EditorialColors.infoLight,
                        borderRadius: EditorialRadius.borderRadiusMd,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            size: 18,
                            color: EditorialColors.info,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This page will update automatically once approved.',
                              style: EditorialTypography.bodySmall.copyWith(
                                fontSize: 13,
                                color: EditorialColors.info,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

                    const SizedBox(height: 32),

                    // Resend verification email
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _resendingEmail ? null : _resendVerificationEmail,
                        icon: _resendingEmail
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: EditorialColors.outline,
                                ),
                              )
                            : const Icon(Icons.email_outlined, size: 18),
                        label: Text(
                          _resendingEmail
                              ? 'Sending...'
                              : 'Resend Verification Email',
                          style: EditorialTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: EditorialColors.onSurfaceVariant,
                          side: const BorderSide(color: EditorialColors.surfaceContainerHigh),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: EditorialRadius.borderRadiusStandard,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 500.ms, duration: 400.ms),

                    const SizedBox(height: 16),

                    // Start over link
                    TextButton(
                      onPressed: _signOutAndRestart,
                      child: Text(
                        'Wrong company? Start over',
                        style: EditorialTypography.labelLarge.copyWith(
                          color: EditorialColors.error,
                        ),
                      ),
                    ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(IconData icon, Color iconColor, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: EditorialTypography.bodyMedium.copyWith(
              fontSize: 14,
              color: EditorialColors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundDecorations() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: -MediaQuery.of(context).size.width * 0.1,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.6,
              height: MediaQuery.of(context).size.height * 0.35,
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerLow.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
