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
import 'package:hospi_dash/widgets/registration/registration_progress_bar.dart';

/// Step 1 of multi-step registration: Company ID
/// Collects country, tax ID, and venue type.
/// NO Supabase writes happen here - just state collection.
class CompanyIdScreen extends ConsumerStatefulWidget {
  const CompanyIdScreen({super.key});

  @override
  ConsumerState<CompanyIdScreen> createState() => _CompanyIdScreenState();
}

class _CompanyIdScreenState extends ConsumerState<CompanyIdScreen> {
  final _scrollController = ScrollController();
  final _formKey = GlobalKey<FormState>();
  final _taxIdController = TextEditingController();
  final _taxIdFocus = FocusNode();

  // Selected values
  String? _selectedCountry;
  VenueType _selectedVenueType = VenueType.restaurant;

  // Tax ID validation state
  String? _taxIdError;
  bool _isTaxIdValid = false;

  @override
  void initState() {
    super.initState();

    // Restore from provider state (for back navigation)
    final state = ref.read(registrationProvider);
    if (state.detectedCountry != null) {
      _selectedCountry = state.detectedCountry;
    }
    if (state.verifiedTaxId != null) {
      _taxIdController.text = state.verifiedTaxId!;
      _isTaxIdValid = true;
    }
    if (state.venueType != null) {
      _selectedVenueType = state.venueType!;
    }

    // Add listener for tax ID validation
    _taxIdController.addListener(_validateTaxId);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _taxIdController.dispose();
    _taxIdFocus.dispose();
    super.dispose();
  }

  void _validateTaxId() {
    if (_selectedCountry == null || _taxIdController.text.isEmpty) {
      setState(() {
        _taxIdError = null;
        _isTaxIdValid = false;
      });
      return;
    }

    final error = validateTaxIdWithMessage(_selectedCountry!, _taxIdController.text);
    setState(() {
      _taxIdError = error;
      _isTaxIdValid = error == null;
    });
  }

  void _onCountryChanged(String? value) {
    setState(() {
      _selectedCountry = value;
    });
    _validateTaxId();
  }

  void _handleContinue() {
    if (_formKey.currentState?.validate() != true) return;
    if (_selectedCountry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a country'),
          backgroundColor: EditorialColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_isTaxIdValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_taxIdError ?? 'Please enter a valid tax ID'),
          backgroundColor: EditorialColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Save to provider and advance to Step 2
    ref.read(registrationProvider.notifier).completeStep1(
          country: _selectedCountry!,
          taxId: _taxIdController.text.trim().toUpperCase(),
          businessType: _selectedVenueType,
        );

    // Navigate to Step 2
    context.push('/register/company-details');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EditorialColors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _buildBackgroundDecorations(),
          SafeArea(child: _buildContent()),
          _buildBottomActionBar(),
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
                color: EditorialColors.surfaceContainerLow.withValues(alpha: 0.5),
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
                color: EditorialColors.surfaceContainerHigh.withValues(alpha: 0.15),
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

  Widget _buildContent() {
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Back button
              _buildBackButton(),

              const SizedBox(height: 24),

              // Progress bar
              const RegistrationProgressBar()
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: -0.2, end: 0),

              const SizedBox(height: 32),

              // Header
              _buildHeader()
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms)
                  .slideY(begin: 0.1, end: 0),

              const SizedBox(height: 32),

              // Country selector
              _buildCountrySelector()
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 200.ms)
                  .slideY(begin: 0.1, end: 0),

              const SizedBox(height: 24),

              // Tax ID field
              _buildTaxIdField()
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 300.ms)
                  .slideY(begin: 0.1, end: 0),

              const SizedBox(height: 24),

              // Venue type selector
              _buildVenueTypeSelector()
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 400.ms)
                  .slideY(begin: 0.1, end: 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return const AppBackButton(
      fallbackRoute: AppRoutes.signIn,
      size: 48,
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Company Identification',
          style: EditorialTypography.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Select your country and enter your company\'s legal identifier to get started.',
          style: EditorialTypography.bodyMedium.copyWith(
            fontSize: 15,
            color: EditorialColors.outline,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildCountrySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Country',
          style: EditorialTypography.titleSmall,
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: EditorialColors.surfaceContainerLowest,
            borderRadius: EditorialRadius.borderRadiusStandard,
            border: Border.all(
              color: _selectedCountry != null
                  ? EditorialColors.primary.withValues(alpha: 0.12)
                  : EditorialColors.surfaceContainerHigh,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedCountry,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: InputBorder.none,
            ),
            hint: Text(
              'Select your country',
              style: EditorialTypography.bodyMedium.copyWith(
                fontSize: 15,
                color: EditorialColors.outline,
              ),
            ),
            isExpanded: true,
            dropdownColor: EditorialColors.surfaceContainerLowest,
            borderRadius: EditorialRadius.borderRadiusStandard,
            items: supportedCountries.map((country) {
              return DropdownMenuItem<String>(
                value: country.code,
                child: Row(
                  children: [
                    Text(
                      country.flag,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        country.name,
                        style: EditorialTypography.bodyMedium.copyWith(
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: _onCountryChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildTaxIdField() {
    const label = 'Legal Identifier';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: EditorialTypography.titleSmall,
        ),
        const SizedBox(height: 8),
        AuthTextField(
          controller: _taxIdController,
          focusNode: _taxIdFocus,
          hint: _selectedCountry != null
              ? 'Enter your legal identifier'
              : 'Select country first',
          enabled: _selectedCountry != null,
          textCapitalization: TextCapitalization.characters,
          prefixIcon: Icon(
            Icons.badge_outlined,
            color: _isTaxIdValid
                ? EditorialColors.success
                : EditorialColors.outline,
          ),
          suffixIcon: _isTaxIdValid
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: EditorialColors.success,
                )
              : null,
        ),
        if (_taxIdError != null) ...[
          const SizedBox(height: 8),
          Text(
            _taxIdError!,
            style: EditorialTypography.bodySmall.copyWith(
              color: EditorialColors.error,
            ),
          ),
        ],
        if (_selectedCountry != null && _taxIdController.text.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _getTaxIdHint(_selectedCountry!),
            style: EditorialTypography.bodySmall.copyWith(
              color: EditorialColors.outline,
            ),
          ),
        ],
      ],
    );
  }

  String _getTaxIdHint(String country) {
    return switch (country) {
      'ES' => 'Format: A12345678 (CIF) or 12345678A (NIF)',
      'FR' => 'Format: 14 digits (SIRET)',
      'GB' => 'Format: 8 digits (Company Number)',
      'US' => 'Format: 12-3456789 (EIN)',
      'MX' => 'Format: ABC123456789 (RFC)',
      'DE' => 'Format: DE123456789 (VAT ID)',
      'IT' => 'Format: IT12345678901 (Partita IVA)',
      'PT' => 'Format: 123456789 (NIF)',
      _ => 'Enter your official tax/company registration number',
    };
  }

  Widget _buildVenueTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Business Type',
          style: EditorialTypography.titleSmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: VenueType.values.map((type) {
            final isSelected = _selectedVenueType == type;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedVenueType = type;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? EditorialColors.primary.withValues(alpha: 0.06)
                      : EditorialColors.surfaceContainerLowest,
                  borderRadius: EditorialRadius.borderRadiusMd,
                  border: Border.all(
                    color: isSelected
                        ? EditorialColors.primary
                        : EditorialColors.surfaceContainerHigh,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getVenueTypeIcon(type),
                      size: 20,
                      color: isSelected
                          ? EditorialColors.primary
                          : EditorialColors.outline,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getVenueTypeLabel(type),
                      style: EditorialTypography.bodyMedium.copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? EditorialColors.primary
                            : EditorialColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  IconData _getVenueTypeIcon(VenueType type) {
    return switch (type) {
      VenueType.restaurant => Icons.restaurant_rounded,
      VenueType.cafe => Icons.local_cafe_rounded,
      VenueType.bar => Icons.local_bar_rounded,
      VenueType.bakery => Icons.bakery_dining_rounded,
      VenueType.other => Icons.store_rounded,
    };
  }

  String _getVenueTypeLabel(VenueType type) {
    return switch (type) {
      VenueType.restaurant => 'Restaurant',
      VenueType.cafe => 'Café',
      VenueType.bar => 'Bar',
      VenueType.bakery => 'Bakery',
      VenueType.other => 'Other',
    };
  }

  Widget _buildBottomActionBar() {
    final isValid = _selectedCountry != null && _isTaxIdValid;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerLowest,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: PrimaryButton(
          text: 'Continue',
          onPressed: isValid ? _handleContinue : null,
          isEnabled: isValid,
        ).animate().fadeIn(duration: 300.ms, delay: 500.ms).slideY(
              begin: 0.3,
              end: 0,
            ),
      ),
    );
  }
}
