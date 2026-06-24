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
import 'package:hospi_dash/utils/locale_defaults.dart';
import 'package:hospi_dash/utils/registration_utils.dart';
import 'package:hospi_dash/widgets/registration/registration_progress_bar.dart';

/// Step 2 of multi-step registration: Company Details
/// Collects legal name, trade name, city, currency, and timezone.
/// NO Supabase writes happen here - just state collection.
/// Advances to Step 3 (User Account) on continue.
class CompanyDetailsScreen extends ConsumerStatefulWidget {
  const CompanyDetailsScreen({super.key});

  @override
  ConsumerState<CompanyDetailsScreen> createState() =>
      _CompanyDetailsScreenState();
}

class _CompanyDetailsScreenState extends ConsumerState<CompanyDetailsScreen> {
  final _scrollController = ScrollController();
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  late final TextEditingController _legalNameController;
  late final TextEditingController _tradeNameController;
  late final TextEditingController _cityController;

  // Dropdown values
  late String _selectedCurrency;
  late String _selectedTimezone;

  // Field-level errors
  final Map<String, String?> _fieldErrors = {};

  // Focus nodes for scrolling to errors
  final _legalNameFocus = FocusNode();
  final _cityFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    // Initialize from provider state (restores on back navigation)
    final state = ref.read(registrationProvider);

    _legalNameController = TextEditingController(text: state.legalName ?? '');
    _tradeNameController = TextEditingController(text: state.tradeName ?? '');
    _cityController = TextEditingController(text: state.city ?? '');

    _selectedCurrency = state.currency;
    _selectedTimezone = state.timezone;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _legalNameController.dispose();
    _tradeNameController.dispose();
    _cityController.dispose();
    _legalNameFocus.dispose();
    _cityFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationProvider);

    // Guard: ensure Step 1 data exists
    if (!ref.read(registrationProvider.notifier).isStep1Complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/register/company-id');
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
          // Center ambient circle
          Positioned(
            top: MediaQuery.of(context).size.height * 0.4,
            left: MediaQuery.of(context).size.width * 0.3,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.4,
              height: MediaQuery.of(context).size.height * 0.2,
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainer.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
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
                  const SizedBox(height: 40),
                  _buildStep1Summary(state)
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 300.ms),
                  const SizedBox(height: 32),
                  _buildFormFields()
                      .animate()
                      .fadeIn(delay: 280.ms, duration: 400.ms)
                      .slideY(begin: 0.1, end: 0),
                  const SizedBox(height: 40),
                  _buildInfoCard()
                      .animate()
                      .fadeIn(delay: 400.ms, duration: 400.ms),
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
            fallbackRoute: AppRoutes.registerCompanyId,
            size: 48,
            onPressed: () {
              ref.read(registrationProvider.notifier).goBack();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.registerCompanyId);
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
      'STEP 2 OF 3',
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
      'Company Details',
      style: EditorialTypography.displayLarge.copyWith(
        fontSize: 36,
        letterSpacing: -1.0,
        height: 1.1,
      ),
    );
  }

  Widget _buildSubtitle() {
    return Text(
      'Tell us about your restaurant or bar.',
      style: EditorialTypography.bodyLarge.copyWith(
        color: EditorialColors.onSurfaceVariant,
        height: 1.6,
      ),
    );
  }

  Widget _buildStep1Summary(RegistrationState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainer,
        borderRadius: EditorialRadius.borderRadiusStandard,
      ),
      child: Row(
        children: [
          // Country flag
          if (state.detectedCountry != null)
            Text(
              countryFlag(state.detectedCountry!),
              style: const TextStyle(fontSize: 24),
            ),
          const SizedBox(width: 12),
          // Tax ID and type
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_outlined,
                      size: 16,
                      color: EditorialColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tax ID: ${state.verifiedTaxId}',
                      style: EditorialTypography.bodySmall.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  state.venueType?.name.toUpperCase() ?? 'RESTAURANT',
                  style: EditorialTypography.labelSmall.copyWith(
                    color: EditorialColors.outline,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          // Edit button
          GestureDetector(
            onTap: () {
              ref.read(registrationProvider.notifier).goBackTo(RegistrationStep.companyId);
              context.go('/register/company-id');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerLowest,
                borderRadius: EditorialRadius.borderRadiusSm,
              ),
              child: Text(
                'Edit',
                style: EditorialTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: EditorialColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legal Company Name
        _buildLabel('Legal Company Name'),
        _buildTextField(
          controller: _legalNameController,
          hint: 'e.g. The Green Bistro LLC',
          focusNode: _legalNameFocus,
          textCapitalization: TextCapitalization.words,
          maxLength: 120,
          error: _fieldErrors['legalName'],
        ),
        const SizedBox(height: 24),

        // Trade Name (Optional)
        _buildLabel('Trade Name', isOptional: true),
        _buildTextField(
          controller: _tradeNameController,
          hint: 'e.g. Green Bistro',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 24),

        // City
        _buildLabel('City'),
        _buildTextField(
          controller: _cityController,
          hint: 'Enter city',
          focusNode: _cityFocus,
          textCapitalization: TextCapitalization.words,
          error: _fieldErrors['city'],
        ),
        const SizedBox(height: 24),

        // Currency + Timezone row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Currency'),
                  _buildCurrencyDropdown(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Timezone'),
                  _buildTimezoneDropdown(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLabel(String text, {bool isOptional = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: RichText(
        text: TextSpan(
          text: text,
          style: EditorialTypography.bodySmall.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          children: isOptional
              ? [
                  TextSpan(
                    text: ' (Optional)',
                    style: EditorialTypography.bodySmall.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: EditorialColors.outline,
                    ),
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    FocusNode? focusNode,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int? maxLength,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          maxLength: maxLength,
          buildCounter: maxLength != null
              ? (context,
                      {required currentLength,
                      required isFocused,
                      required maxLength}) =>
                  null
              : null,
          style: EditorialTypography.bodyMedium.copyWith(
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: EditorialTypography.bodyMedium.copyWith(
              fontSize: 15,
              color: EditorialColors.outline,
            ),
            filled: true,
            fillColor: EditorialColors.surfaceContainerLowest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(
                color: EditorialColors.primary.withValues(alpha: 0.12),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(
                color: EditorialColors.error,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              error,
              style: EditorialTypography.bodySmall.copyWith(
                color: EditorialColors.error,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCurrencyDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: ButtonTheme(
          alignedDropdown: true,
          child: DropdownButton<String>(
            value: _selectedCurrency,
            isExpanded: true,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: EditorialColors.outline,
              size: 20,
            ),
            style: EditorialTypography.bodyMedium,
            dropdownColor: EditorialColors.surfaceContainerLowest,
            borderRadius: EditorialRadius.borderRadiusStandard,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            items: supportedCurrencies.map((currency) {
              return DropdownMenuItem<String>(
                value: currency.code,
                child: Text(currency.label),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCurrency = value);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTimezoneDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: ButtonTheme(
          alignedDropdown: true,
          child: DropdownButton<String>(
            value: _selectedTimezone,
            isExpanded: true,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: EditorialColors.outline,
              size: 20,
            ),
            style: EditorialTypography.bodyMedium,
            dropdownColor: EditorialColors.surfaceContainerLowest,
            borderRadius: EditorialRadius.borderRadiusStandard,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            items: supportedTimezones.map((tz) {
              return DropdownMenuItem<String>(
                value: tz.iana,
                child: Text(tz.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedTimezone = value);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          // Decorative soft circle
          Positioned(
            right: -20,
            bottom: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: EditorialColors.surfaceDim.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: EditorialColors.onSurface,
                size: 28,
              ),
              const SizedBox(height: 12),
              Text(
                'Your data is secure',
                style: EditorialTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'We use industry-standard encryption and row-level security '
                "to ensure your company's data is completely isolated.",
                style: EditorialTypography.bodySmall.copyWith(
                  fontSize: 13,
                  color: EditorialColors.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                        onPressed: () {
                          ref.read(registrationProvider.notifier).goBack();
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
                    // Continue Button
                    Flexible(
                      flex: 2,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: EditorialColors.onSurface,
                            disabledBackgroundColor:
                                EditorialColors.onSurface.withValues(alpha: 0.4),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: EditorialTypography.titleMedium.copyWith(
                                  color: EditorialColors.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                            ],
                          ),
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

    final legalName = _legalNameController.text.trim();
    final city = _cityController.text.trim();

    // Validate legal name
    if (legalName.isEmpty || legalName.length < 2) {
      _fieldErrors['legalName'] = 'Company name must be at least 2 characters';
    } else if (legalName.length > 120) {
      _fieldErrors['legalName'] = 'Company name is too long';
    }

    // Validate city
    if (city.isEmpty || city.length < 2) {
      _fieldErrors['city'] = 'Please enter your city';
    }

    // Currency and timezone should always have defaults
    if (_selectedCurrency.isEmpty) {
      _selectedCurrency = 'EUR';
    }
    if (_selectedTimezone.isEmpty) {
      _selectedTimezone = 'Europe/Madrid';
    }

    setState(() {});

    // Scroll to first error
    if (_fieldErrors.containsKey('legalName')) {
      _scrollToField(_legalNameFocus);
      return false;
    }
    if (_fieldErrors.containsKey('city')) {
      _scrollToField(_cityFocus);
      return false;
    }

    return _fieldErrors.isEmpty;
  }

  void _scrollToField(FocusNode focusNode) {
    focusNode.requestFocus();
    Scrollable.ensureVisible(
      focusNode.context!,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handleContinue() {
    // 1. Run client-side validation
    if (!_validate()) return;

    // 2. Dismiss keyboard
    FocusScope.of(context).unfocus();

    // 3. Complete Step 2 (NO Supabase writes - just state update)
    ref.read(registrationProvider.notifier).completeStep2(
          legalName: _legalNameController.text.trim(),
          tradeName: _tradeNameController.text.trim().isEmpty
              ? null
              : _tradeNameController.text.trim(),
          city: _cityController.text.trim(),
          currency: _selectedCurrency,
          timezone: _selectedTimezone,
        );

    // 4. Navigate to Step 3 (User Account)
    context.push('/register/user-account');
  }
}
