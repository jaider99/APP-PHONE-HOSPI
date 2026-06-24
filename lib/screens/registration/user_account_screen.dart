import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/models/registration_models.dart';
import 'package:hospi_dash/providers/registration_provider.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';
import 'package:hospi_dash/utils/registration_utils.dart';
import 'package:hospi_dash/widgets/auth/auth_text_field.dart';
import 'package:hospi_dash/widgets/auth/primary_button.dart';
import 'package:hospi_dash/widgets/registration/password_strength_indicator.dart';
import 'package:hospi_dash/widgets/registration/registration_progress_bar.dart';

/// Step 3 of multi-step registration: User Account
/// Collects full name, email, password, and role.
/// THIS IS WHERE ALL SUPABASE WRITES HAPPEN:
/// - auth.signUp()
/// - companies insert (owner) or company_users insert (manager)
/// - user_preferences upsert
class UserAccountScreen extends ConsumerStatefulWidget {
  const UserAccountScreen({super.key});

  @override
  ConsumerState<UserAccountScreen> createState() => _UserAccountScreenState();
}

class _UserAccountScreenState extends ConsumerState<UserAccountScreen> {
  final _scrollController = ScrollController();
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  // Focus nodes
  final _fullNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();
  final _inviteCodeFocus = FocusNode();

  // Selected role
  UserRole _selectedRole = UserRole.owner;

  // UI state
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final Map<String, String?> _fieldErrors = {};

  @override
  void initState() {
    super.initState();

    // Restore from provider state (for back navigation)
    final state = ref.read(registrationProvider);
    if (state.fullName != null) {
      _fullNameController.text = state.fullName!;
    }
    if (state.email != null) {
      _emailController.text = state.email!;
    }
    _selectedRole = state.selectedRole;
    if (state.inviteCode != null) {
      _inviteCodeController.text = state.inviteCode!;
    }
    // NOTE: Password is NEVER stored in state

    // Add listeners for real-time validation
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteCodeController.dispose();
    _fullNameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _inviteCodeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationProvider);

    // Guard: ensure Step 2 data exists
    if (!ref.read(registrationProvider.notifier).isStep2Complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/register/company-details');
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: EditorialColors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _buildBackgroundDecorations(),
          SafeArea(child: _buildContent(state)),
          _buildBottomActionBar(state),
        ],
      ),
    );
  }

  Widget _buildBackgroundDecorations() {
    return IgnorePointer(
      child: Stack(
        children: [
          // Top-right ambient circle
          Positioned(
            top: -50,
            right: -MediaQuery.of(context).size.width * 0.1,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.6,
              height: MediaQuery.of(context).size.height * 0.35,
              decoration: BoxDecoration(
                color:
                    EditorialColors.surfaceContainerLow.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
          // Bottom-left ambient circle
          Positioned(
            bottom: 100,
            left: -MediaQuery.of(context).size.width * 0.1,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.5,
              height: MediaQuery.of(context).size.height * 0.25,
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerHigh
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(RegistrationState state) {
    return Column(
      children: [
        _buildHeader(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: RegistrationProgressBar(),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 160),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStepLabel()
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 8),
                  _buildTitle()
                      .animate()
                      .fadeIn(delay: 80.ms, duration: 400.ms)
                      .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 8),
                  _buildSubtitle()
                      .animate()
                      .fadeIn(delay: 160.ms, duration: 400.ms),
                  const SizedBox(height: 32),
                  _buildRegistrationSummary(state)
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 300.ms),
                  const SizedBox(height: 32),
                  _buildFormFields()
                      .animate()
                      .fadeIn(delay: 280.ms, duration: 400.ms)
                      .slideY(begin: 0.1, end: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          AppBackButton(
            fallbackRoute: AppRoutes.registerCompanyDetails,
            size: 48,
            onPressed: () {
              ref.read(registrationProvider.notifier).goBack();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.registerCompanyDetails);
              }
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                'Registration',
                style: EditorialTypography.titleMedium.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildStepLabel() {
    return Text(
      'STEP 3 OF 3',
      style: EditorialTypography.labelSmall.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.5,
        color: EditorialColors.secondary,
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      'Create Account',
      style: EditorialTypography.displayLarge.copyWith(
        fontSize: 36,
        letterSpacing: -1.0,
        height: 1.1,
      ),
    );
  }

  Widget _buildSubtitle() {
    return Text(
      'Set up your login credentials to complete registration.',
      style: EditorialTypography.bodyLarge.copyWith(
        color: EditorialColors.onSurfaceVariant,
        height: 1.6,
      ),
    );
  }

  Widget _buildRegistrationSummary(RegistrationState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainer,
        borderRadius: EditorialRadius.borderRadiusStandard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              if (state.detectedCountry != null)
                Text(
                  countryFlag(state.detectedCountry!),
                  style: const TextStyle(fontSize: 24),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.legalName ?? '',
                      style: EditorialTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${state.city ?? ''} • ${state.currency ?? ''}',
                      style: EditorialTypography.bodySmall.copyWith(
                        fontSize: 13,
                        color: EditorialColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Tax ID row
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 14,
                color: EditorialColors.success,
              ),
              const SizedBox(width: 6),
              Text(
                'Tax ID: ${state.verifiedTaxId}',
                style: EditorialTypography.bodySmall.copyWith(
                  color: EditorialColors.outline,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: EditorialColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  state.businessType?.name.toUpperCase() ?? 'RESTAURANT',
                  style: EditorialTypography.labelSmall.copyWith(
                    fontSize: 10,
                    color: EditorialColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Full Name
        _buildLabel('Full Name'),
        AuthTextField(
          controller: _fullNameController,
          focusNode: _fullNameFocus,
          hint: 'Enter your full name',
          textCapitalization: TextCapitalization.words,
          prefixIcon: const Icon(Icons.person_outline_rounded),
          errorText: _fieldErrors['fullName'],
        ),
        const SizedBox(height: 24),

        // Email
        _buildLabel('Email Address'),
        AuthTextField(
          controller: _emailController,
          focusNode: _emailFocus,
          hint: 'Enter your email',
          keyboardType: TextInputType.emailAddress,
          prefixIcon: const Icon(Icons.email_outlined),
          errorText: _fieldErrors['email'],
        ),
        const SizedBox(height: 24),

        // Password
        _buildLabel('Password'),
        AuthTextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          hint: 'Create a password',
          obscureText: _obscurePassword,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
          errorText: _fieldErrors['password'],
        ),
        const SizedBox(height: 8),
        PasswordStrengthIndicator(password: _passwordController.text),
        const SizedBox(height: 24),

        // Confirm Password
        _buildLabel('Confirm Password'),
        AuthTextField(
          controller: _confirmPasswordController,
          focusNode: _confirmPasswordFocus,
          hint: 'Confirm your password',
          obscureText: _obscureConfirmPassword,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirmPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
          ),
          errorText: _fieldErrors['confirmPassword'],
        ),
        const SizedBox(height: 32),

        // Role Selector
        _buildLabel('Your Role'),
        _buildRoleSelector(),

        // Invite Code (visible only when Manager is selected)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: _selectedRole == UserRole.manager
              ? Padding(
                  key: const ValueKey('invite-code'),
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Invite Code'),
                      AuthTextField(
                        controller: _inviteCodeController,
                        focusNode: _inviteCodeFocus,
                        hint: 'Enter company invite code',
                        textCapitalization: TextCapitalization.characters,
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        errorText: _fieldErrors['inviteCode'],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ask your company owner for the invite code.',
                        style: EditorialTypography.bodySmall.copyWith(
                          color: EditorialColors.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-invite')),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: EditorialTypography.labelLarge.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Column(
      children: UserRole.values.map((role) {
        final isSelected = _selectedRole == role;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedRole = role;
            });
            ref.read(registrationProvider.notifier).updateStep3Fields(
                  role: role,
                );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? EditorialColors.onSurface.withValues(alpha: 0.06)
                  : EditorialColors.surfaceContainerLowest,
              borderRadius: EditorialRadius.borderRadiusStandard,
              border: Border.all(
                color: isSelected
                    ? EditorialColors.onSurface
                    : EditorialColors.surfaceContainerHigh,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Radio indicator
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? EditorialColors.onSurface
                          : EditorialColors.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: EditorialColors.onSurface,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                // Role info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getRoleLabel(role),
                        style: EditorialTypography.bodyMedium.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? EditorialColors.onSurface
                              : EditorialColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getRoleDescription(role),
                        style: EditorialTypography.bodySmall.copyWith(
                          color: EditorialColors.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _getRoleLabel(UserRole role) {
    return switch (role) {
      UserRole.owner => 'Owner',
      UserRole.manager => 'Manager',
    };
  }

  String _getRoleDescription(UserRole role) {
    return switch (role) {
      UserRole.owner => 'I am registering a new business',
      UserRole.manager => 'I was invited to join an existing business',
    };
  }

  Widget _buildBottomActionBar(RegistrationState state) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: EditorialRadius.borderRadiusTopLg,
          boxShadow: [
            BoxShadow(
              blurRadius: 40,
              color: EditorialColors.onSurface.withValues(alpha: 0.06),
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: EditorialRadius.borderRadiusTopLg,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Row(
                  children: [
                    // Back Button
                    Flexible(
                      child: TextButton.icon(
                        onPressed: state.isLoading
                            ? null
                            : () {
                                ref
                                    .read(registrationProvider.notifier)
                                    .goBack();
                                context.pop();
                              },
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 16,
                          color: EditorialColors.outlineVariant,
                        ),
                        label: Text(
                          'Back',
                          style: EditorialTypography.labelLarge.copyWith(
                            color: EditorialColors.outlineVariant,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Create Account Button
                    Flexible(
                      flex: 2,
                      child: SizedBox(
                        width: double.infinity,
                        child: PrimaryButton(
                          text: _selectedRole == UserRole.owner
                              ? 'Create Account & Register Business'
                              : 'Create Account & Request Access',
                          onPressed: _handleCreateAccount,
                          isLoading: state.isLoading,
                        ),
                      ),
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

  bool _validate() {
    _fieldErrors.clear();

    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validate full name
    if (fullName.isEmpty || fullName.length < 2) {
      _fieldErrors['fullName'] = 'Please enter your full name';
    }

    // Validate email
    if (email.isEmpty) {
      _fieldErrors['email'] = 'Please enter your email';
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _fieldErrors['email'] = 'Please enter a valid email address';
    }

    // Validate password
    final passwordError =
        PasswordStrengthIndicator.getValidationError(password);
    if (passwordError != null) {
      _fieldErrors['password'] = passwordError;
    }

    // Validate confirm password
    if (confirmPassword.isEmpty) {
      _fieldErrors['confirmPassword'] = 'Please confirm your password';
    } else if (confirmPassword != password) {
      _fieldErrors['confirmPassword'] = 'Passwords do not match';
    }

    // Validate invite code for Manager role
    if (_selectedRole == UserRole.manager) {
      final inviteCode = _inviteCodeController.text.trim();
      if (inviteCode.isEmpty) {
        _fieldErrors['inviteCode'] = 'Please enter the invite code';
      }
    }

    setState(() {});

    // Scroll to first error
    if (_fieldErrors.containsKey('fullName')) {
      _scrollToField(_fullNameFocus);
      return false;
    }
    if (_fieldErrors.containsKey('email')) {
      _scrollToField(_emailFocus);
      return false;
    }
    if (_fieldErrors.containsKey('password')) {
      _scrollToField(_passwordFocus);
      return false;
    }
    if (_fieldErrors.containsKey('confirmPassword')) {
      _scrollToField(_confirmPasswordFocus);
      return false;
    }

    return _fieldErrors.isEmpty;
  }

  void _scrollToField(FocusNode focusNode) {
    focusNode.requestFocus();
    if (focusNode.context != null) {
      Scrollable.ensureVisible(
        focusNode.context!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _handleCreateAccount() async {
    // 1. Run client-side validation
    if (!_validate()) return;

    // 2. Dismiss keyboard
    FocusScope.of(context).unfocus();

    // 3. Update invite code in provider state before calling completeStep3
    if (_selectedRole == UserRole.manager) {
      ref.read(registrationProvider.notifier).updateStep3Fields(
            inviteCode: _inviteCodeController.text.trim(),
          );
    }

    // 4. Call completeStep3 — forks based on selectedRole
    final result = await ref.read(registrationProvider.notifier).completeStep3(
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text, // Passed through, never stored
          role: _selectedRole,
        );

    // 5. Handle 3-outcome result
    if (!mounted) return;

    result.when(
      ownerSuccess: (company) {
        // Owner: navigate to dashboard
        context.go('/dashboard');
      },
      managerPending: (companyName) {
        // Manager: navigate to pending approval screen
        context.go('/pending-approval', extra: companyName);
      },
      emailVerificationPending: (email, role) {
        context.go(AppRoutes.otpVerify, extra: email);
      },
      failure: (error, message) {
        if (error == RegistrationError.duplicateTaxId) {
          _showDuplicateTaxIdDialog();
        } else if (error == RegistrationError.emailAlreadyExists) {
          _showEmailExistsDialog();
        } else if (error == RegistrationError.invalidInviteCode) {
          setState(() {
            _fieldErrors['inviteCode'] = message;
          });
        } else {
          // Show snackbar for other errors
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: EditorialTypography.bodyMedium.copyWith(
                  color: Colors.white,
                ),
              ),
              backgroundColor: EditorialColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: EditorialRadius.borderRadiusStandard,
              ),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            ),
          );
        }
      },
    );
  }

  void _showDuplicateTaxIdDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: EditorialRadius.borderRadiusLg,
        ),
        title: Text(
          'Tax ID Already Registered',
          style: EditorialTypography.headlineSmall.copyWith(
            fontSize: 18,
            color: const Color(0xFF1A1C1C),
          ),
        ),
        content: Text(
          'A company with this tax ID is already registered. '
          'Please contact support if you believe this is an error.',
          style: EditorialTypography.bodyMedium.copyWith(
            color: EditorialColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Go back to Step 1 to change tax ID
              ref
                  .read(registrationProvider.notifier)
                  .goBackTo(RegistrationStep.companyId);
              context.go('/register/company-id');
            },
            child: Text(
              'Change Tax ID',
              style: EditorialTypography.labelLarge.copyWith(
                color: EditorialColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEmailExistsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: EditorialRadius.borderRadiusLg,
        ),
        title: Text(
          'Email Already Registered',
          style: EditorialTypography.headlineSmall.copyWith(
            fontSize: 18,
          ),
        ),
        content: Text(
          'An account with this email already exists. '
          'Would you like to sign in instead?',
          style: EditorialTypography.bodyMedium.copyWith(
            color: EditorialColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Use Different Email',
              style: EditorialTypography.labelLarge.copyWith(
                color: EditorialColors.outline,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/sign-in');
            },
            child: Text(
              'Sign In',
              style: EditorialTypography.labelLarge.copyWith(
                color: EditorialColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
