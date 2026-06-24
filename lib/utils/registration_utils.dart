/// Registration utilities for the multi-step onboarding flow.
/// 
/// Contains:
/// - Country list with tax ID configurations
/// - Tax ID validation regexes per country
/// - Country → currency/timezone mappings
/// - Flag emoji helpers
library;

import 'package:hospi_dash/models/registration_models.dart';

// ============================================================================
// COUNTRY TAX CONFIGURATIONS
// ============================================================================

/// All supported countries for venue registration.
/// Curated list of 40+ countries most common for hospitality businesses.
final List<CountryTaxConfig> supportedCountries = [
  // ── Europe ────────────────────────────────────────────────────────────────
  CountryTaxConfig(
    code: 'ES',
    name: 'Spain',
    flag: '🇪🇸',
    taxIdLabel: 'CIF / NIF',
    validationRegex: RegExp(r'^[A-Z]\d{7}[A-Z0-9]$', caseSensitive: false),
    placeholder: 'B12345678',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Madrid',
  ),
  CountryTaxConfig(
    code: 'FR',
    name: 'France',
    flag: '🇫🇷',
    taxIdLabel: 'SIRET / SIREN',
    validationRegex: RegExp(r'^\d{9}$|^\d{14}$'),
    placeholder: '123456789 or 12345678901234',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Paris',
  ),
  CountryTaxConfig(
    code: 'IT',
    name: 'Italy',
    flag: '🇮🇹',
    taxIdLabel: 'Partita IVA',
    validationRegex: RegExp(r'^\d{11}$'),
    placeholder: '12345678901',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Rome',
  ),
  CountryTaxConfig(
    code: 'DE',
    name: 'Germany',
    flag: '🇩🇪',
    taxIdLabel: 'Steuernummer / USt-IdNr',
    validationRegex: RegExp(r'^DE\d{9}$|^\d{10,13}$', caseSensitive: false),
    placeholder: 'DE123456789',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Berlin',
  ),
  CountryTaxConfig(
    code: 'GB',
    name: 'United Kingdom',
    flag: '🇬🇧',
    taxIdLabel: 'Company Number',
    validationRegex: RegExp(r'^\d{8}$|^[A-Z]{2}\d{6}$', caseSensitive: false),
    placeholder: '12345678',
    defaultCurrency: 'GBP',
    defaultTimezone: 'Europe/London',
  ),
  CountryTaxConfig(
    code: 'PT',
    name: 'Portugal',
    flag: '🇵🇹',
    taxIdLabel: 'NIF / NIPC',
    validationRegex: RegExp(r'^\d{9}$'),
    placeholder: '123456789',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Lisbon',
  ),
  CountryTaxConfig(
    code: 'NL',
    name: 'Netherlands',
    flag: '🇳🇱',
    taxIdLabel: 'BTW-nummer / KVK',
    validationRegex: RegExp(r'^NL\d{9}B\d{2}$|^\d{8}$', caseSensitive: false),
    placeholder: 'NL123456789B01',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Amsterdam',
  ),
  CountryTaxConfig(
    code: 'BE',
    name: 'Belgium',
    flag: '🇧🇪',
    taxIdLabel: 'Numéro TVA / BTW',
    validationRegex: RegExp(r'^BE0?\d{9,10}$', caseSensitive: false),
    placeholder: 'BE0123456789',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Brussels',
  ),
  CountryTaxConfig(
    code: 'AT',
    name: 'Austria',
    flag: '🇦🇹',
    taxIdLabel: 'UID-Nummer',
    validationRegex: RegExp(r'^ATU\d{8}$', caseSensitive: false),
    placeholder: 'ATU12345678',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Vienna',
  ),
  CountryTaxConfig(
    code: 'CH',
    name: 'Switzerland',
    flag: '🇨🇭',
    taxIdLabel: 'UID / MWST',
    validationRegex: RegExp(r'^CHE-?\d{3}\.?\d{3}\.?\d{3}\s?MWST$|^\d{9}$', caseSensitive: false),
    placeholder: 'CHE-123.456.789 MWST',
    defaultCurrency: 'CHF',
    defaultTimezone: 'Europe/Zurich',
  ),
  CountryTaxConfig(
    code: 'IE',
    name: 'Ireland',
    flag: '🇮🇪',
    taxIdLabel: 'VAT Number',
    validationRegex: RegExp(r'^IE\d{7}[A-Z]{1,2}$|^\d{7}[A-Z]{1,2}$', caseSensitive: false),
    placeholder: 'IE1234567A',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Dublin',
  ),
  CountryTaxConfig(
    code: 'GR',
    name: 'Greece',
    flag: '🇬🇷',
    taxIdLabel: 'ΑΦΜ',
    validationRegex: RegExp(r'^\d{9}$'),
    placeholder: '123456789',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Athens',
  ),
  CountryTaxConfig(
    code: 'PL',
    name: 'Poland',
    flag: '🇵🇱',
    taxIdLabel: 'NIP',
    validationRegex: RegExp(r'^\d{10}$'),
    placeholder: '1234567890',
    defaultCurrency: 'PLN',
    defaultTimezone: 'Europe/Warsaw',
  ),
  CountryTaxConfig(
    code: 'SE',
    name: 'Sweden',
    flag: '🇸🇪',
    taxIdLabel: 'Organisationsnummer',
    validationRegex: RegExp(r'^\d{10}$|^\d{6}-\d{4}$'),
    placeholder: '1234567890',
    defaultCurrency: 'SEK',
    defaultTimezone: 'Europe/Stockholm',
  ),
  CountryTaxConfig(
    code: 'NO',
    name: 'Norway',
    flag: '🇳🇴',
    taxIdLabel: 'Organisasjonsnummer',
    validationRegex: RegExp(r'^\d{9}$'),
    placeholder: '123456789',
    defaultCurrency: 'NOK',
    defaultTimezone: 'Europe/Oslo',
  ),
  CountryTaxConfig(
    code: 'DK',
    name: 'Denmark',
    flag: '🇩🇰',
    taxIdLabel: 'CVR-nummer',
    validationRegex: RegExp(r'^\d{8}$'),
    placeholder: '12345678',
    defaultCurrency: 'DKK',
    defaultTimezone: 'Europe/Copenhagen',
  ),
  CountryTaxConfig(
    code: 'FI',
    name: 'Finland',
    flag: '🇫🇮',
    taxIdLabel: 'Y-tunnus',
    validationRegex: RegExp(r'^\d{7}-\d$'),
    placeholder: '1234567-8',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Helsinki',
  ),
  CountryTaxConfig(
    code: 'CZ',
    name: 'Czech Republic',
    flag: '🇨🇿',
    taxIdLabel: 'DIČ / IČO',
    validationRegex: RegExp(r'^CZ\d{8,10}$|^\d{8}$', caseSensitive: false),
    placeholder: 'CZ12345678',
    defaultCurrency: 'CZK',
    defaultTimezone: 'Europe/Prague',
  ),
  CountryTaxConfig(
    code: 'HU',
    name: 'Hungary',
    flag: '🇭🇺',
    taxIdLabel: 'Adószám',
    validationRegex: RegExp(r'^\d{8}-\d-\d{2}$|^\d{11}$'),
    placeholder: '12345678-1-23',
    defaultCurrency: 'HUF',
    defaultTimezone: 'Europe/Budapest',
  ),
  CountryTaxConfig(
    code: 'RO',
    name: 'Romania',
    flag: '🇷🇴',
    taxIdLabel: 'CUI / CIF',
    validationRegex: RegExp(r'^RO\d{2,10}$|^\d{2,10}$', caseSensitive: false),
    placeholder: 'RO12345678',
    defaultCurrency: 'RON',
    defaultTimezone: 'Europe/Bucharest',
  ),
  CountryTaxConfig(
    code: 'HR',
    name: 'Croatia',
    flag: '🇭🇷',
    taxIdLabel: 'OIB',
    validationRegex: RegExp(r'^\d{11}$'),
    placeholder: '12345678901',
    defaultCurrency: 'EUR',
    defaultTimezone: 'Europe/Zagreb',
  ),
  
  // ── North America ─────────────────────────────────────────────────────────
  CountryTaxConfig(
    code: 'US',
    name: 'United States',
    flag: '🇺🇸',
    taxIdLabel: 'EIN',
    validationRegex: RegExp(r'^\d{2}-\d{7}$'),
    placeholder: '12-3456789',
    defaultCurrency: 'USD',
    defaultTimezone: 'America/New_York',
  ),
  CountryTaxConfig(
    code: 'CA',
    name: 'Canada',
    flag: '🇨🇦',
    taxIdLabel: 'Business Number (BN)',
    validationRegex: RegExp(r'^\d{9}(RC\d{4})?$'),
    placeholder: '123456789RC0001',
    defaultCurrency: 'CAD',
    defaultTimezone: 'America/Toronto',
  ),
  CountryTaxConfig(
    code: 'MX',
    name: 'Mexico',
    flag: '🇲🇽',
    taxIdLabel: 'RFC',
    validationRegex: RegExp(r'^[A-Z&Ñ]{3,4}\d{6}[A-Z0-9]{3}$', caseSensitive: false),
    placeholder: 'XAXX010101000',
    defaultCurrency: 'MXN',
    defaultTimezone: 'America/Mexico_City',
  ),
  
  // ── South America ─────────────────────────────────────────────────────────
  CountryTaxConfig(
    code: 'BR',
    name: 'Brazil',
    flag: '🇧🇷',
    taxIdLabel: 'CNPJ',
    validationRegex: RegExp(r'^\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}$'),
    placeholder: '12.345.678/0001-90',
    defaultCurrency: 'BRL',
    defaultTimezone: 'America/Sao_Paulo',
  ),
  CountryTaxConfig(
    code: 'AR',
    name: 'Argentina',
    flag: '🇦🇷',
    taxIdLabel: 'CUIT',
    validationRegex: RegExp(r'^\d{2}-?\d{8}-?\d$'),
    placeholder: '20-12345678-9',
    defaultCurrency: 'ARS',
    defaultTimezone: 'America/Argentina/Buenos_Aires',
  ),
  CountryTaxConfig(
    code: 'CO',
    name: 'Colombia',
    flag: '🇨🇴',
    taxIdLabel: 'NIT',
    validationRegex: RegExp(r'^\d{9,10}(-\d)?$'),
    placeholder: '900123456-7',
    defaultCurrency: 'COP',
    defaultTimezone: 'America/Bogota',
  ),
  CountryTaxConfig(
    code: 'CL',
    name: 'Chile',
    flag: '🇨🇱',
    taxIdLabel: 'RUT',
    validationRegex: RegExp(r'^\d{1,2}\.?\d{3}\.?\d{3}-?[0-9Kk]$'),
    placeholder: '12.345.678-9',
    defaultCurrency: 'CLP',
    defaultTimezone: 'America/Santiago',
  ),
  CountryTaxConfig(
    code: 'PE',
    name: 'Peru',
    flag: '🇵🇪',
    taxIdLabel: 'RUC',
    validationRegex: RegExp(r'^\d{11}$'),
    placeholder: '20123456789',
    defaultCurrency: 'PEN',
    defaultTimezone: 'America/Lima',
  ),
  CountryTaxConfig(
    code: 'EC',
    name: 'Ecuador',
    flag: '🇪🇨',
    taxIdLabel: 'RUC',
    validationRegex: RegExp(r'^\d{13}$'),
    placeholder: '1234567890001',
    defaultCurrency: 'USD',
    defaultTimezone: 'America/Guayaquil',
  ),
  CountryTaxConfig(
    code: 'UY',
    name: 'Uruguay',
    flag: '🇺🇾',
    taxIdLabel: 'RUT',
    validationRegex: RegExp(r'^\d{12}$'),
    placeholder: '123456789012',
    defaultCurrency: 'UYU',
    defaultTimezone: 'America/Montevideo',
  ),
  
  // ── Asia Pacific ──────────────────────────────────────────────────────────
  CountryTaxConfig(
    code: 'AU',
    name: 'Australia',
    flag: '🇦🇺',
    taxIdLabel: 'ABN',
    validationRegex: RegExp(r'^\d{11}$'),
    placeholder: '12345678901',
    defaultCurrency: 'AUD',
    defaultTimezone: 'Australia/Sydney',
  ),
  CountryTaxConfig(
    code: 'NZ',
    name: 'New Zealand',
    flag: '🇳🇿',
    taxIdLabel: 'NZBN / IRD',
    validationRegex: RegExp(r'^\d{8,13}$'),
    placeholder: '123456789',
    defaultCurrency: 'NZD',
    defaultTimezone: 'Pacific/Auckland',
  ),
  CountryTaxConfig(
    code: 'SG',
    name: 'Singapore',
    flag: '🇸🇬',
    taxIdLabel: 'UEN',
    validationRegex: RegExp(r'^[A-Z0-9]{9,10}$', caseSensitive: false),
    placeholder: '12345678A',
    defaultCurrency: 'SGD',
    defaultTimezone: 'Asia/Singapore',
  ),
  CountryTaxConfig(
    code: 'JP',
    name: 'Japan',
    flag: '🇯🇵',
    taxIdLabel: '法人番号',
    validationRegex: RegExp(r'^\d{13}$'),
    placeholder: '1234567890123',
    defaultCurrency: 'JPY',
    defaultTimezone: 'Asia/Tokyo',
  ),
  CountryTaxConfig(
    code: 'KR',
    name: 'South Korea',
    flag: '🇰🇷',
    taxIdLabel: '사업자등록번호',
    validationRegex: RegExp(r'^\d{3}-\d{2}-\d{5}$|^\d{10}$'),
    placeholder: '123-45-67890',
    defaultCurrency: 'KRW',
    defaultTimezone: 'Asia/Seoul',
  ),
  CountryTaxConfig(
    code: 'AE',
    name: 'United Arab Emirates',
    flag: '🇦🇪',
    taxIdLabel: 'TRN',
    validationRegex: RegExp(r'^\d{15}$'),
    placeholder: '100000000000003',
    defaultCurrency: 'AED',
    defaultTimezone: 'Asia/Dubai',
  ),
  CountryTaxConfig(
    code: 'IL',
    name: 'Israel',
    flag: '🇮🇱',
    taxIdLabel: 'מספר עוסק',
    validationRegex: RegExp(r'^\d{9}$'),
    placeholder: '123456789',
    defaultCurrency: 'ILS',
    defaultTimezone: 'Asia/Jerusalem',
  ),
  CountryTaxConfig(
    code: 'ZA',
    name: 'South Africa',
    flag: '🇿🇦',
    taxIdLabel: 'VAT Number',
    validationRegex: RegExp(r'^\d{10}$'),
    placeholder: '1234567890',
    defaultCurrency: 'ZAR',
    defaultTimezone: 'Africa/Johannesburg',
  ),
];

/// Default configuration for countries not in the list
final CountryTaxConfig defaultCountryConfig = CountryTaxConfig(
  code: 'XX',
  name: 'Other',
  flag: '🏳️',
  taxIdLabel: 'Tax ID / VAT Number',
  validationRegex: RegExp(r'^.{4,30}$'),
  placeholder: 'Enter your tax identifier',
  defaultCurrency: 'EUR',
  defaultTimezone: 'Europe/London',
);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Get country config by ISO 3166-1 alpha-2 code
CountryTaxConfig getCountryConfig(String? countryCode) {
  if (countryCode == null || countryCode.isEmpty) return defaultCountryConfig;
  
  final upper = countryCode.toUpperCase();
  return supportedCountries.firstWhere(
    (c) => c.code == upper,
    orElse: () => defaultCountryConfig,
  );
}

/// Get flag emoji for country code
String getFlagEmoji(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) return '🏳️';
  
  // Convert country code to regional indicator symbols
  final upper = countryCode.toUpperCase();
  final firstLetter = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
  final secondLetter = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
  
  return String.fromCharCodes([firstLetter, secondLetter]);
}

/// Alias for getFlagEmoji - get flag emoji from country code
String countryFlag(String? countryCode) => getFlagEmoji(countryCode);

/// Validate tax ID for a specific country (returns true if valid)
bool validateTaxId(String taxId, String countryCode) {
  final config = getCountryConfig(countryCode);
  return config.validate(taxId);
}

/// Validate tax ID and return error message if invalid, null if valid
String? validateTaxIdWithMessage(String countryCode, String taxId) {
  if (taxId.isEmpty) return null; // Don't show error for empty field
  
  final config = getCountryConfig(countryCode);
  if (config.validate(taxId)) {
    return null; // Valid
  }
  
  return 'Invalid ${config.taxIdLabel} format. Example: ${config.placeholder}';
}

/// Get tax ID label for a country (e.g., "CIF / NIF" for Spain)
String getTaxIdLabel(String? countryCode) {
  return getCountryConfig(countryCode).taxIdLabel;
}

/// Get tax ID placeholder/example for a country
String getTaxIdPlaceholder(String? countryCode) {
  return getCountryConfig(countryCode).placeholder;
}

/// Get default currency for a country
String getDefaultCurrencyForCountry(String? countryCode) {
  return getCountryConfig(countryCode).defaultCurrency;
}

/// Get default timezone for a country
String getDefaultTimezoneForCountry(String? countryCode) {
  return getCountryConfig(countryCode).defaultTimezone;
}

// ============================================================================
// PASSWORD STRENGTH
// ============================================================================

/// Calculate password strength score (0-4)
int calculatePasswordStrength(String password) {
  if (password.isEmpty) return 0;
  
  int score = 0;
  
  // Length checks
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  
  // Has uppercase
  if (RegExp(r'[A-Z]').hasMatch(password)) score++;
  
  // Has number or symbol
  if (RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) score++;
  
  return score.clamp(0, 4);
}

/// Get password strength label
String getPasswordStrengthLabel(int score) {
  switch (score) {
    case 0:
    case 1:
      return 'Weak';
    case 2:
      return 'Fair';
    case 3:
      return 'Good';
    case 4:
      return 'Strong';
    default:
      return '';
  }
}

// ============================================================================
// EMAIL VALIDATION
// ============================================================================

/// Simple email format validation
bool isValidEmail(String email) {
  return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
      .hasMatch(email);
}
