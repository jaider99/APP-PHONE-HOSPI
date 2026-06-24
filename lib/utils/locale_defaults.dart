/// Locale defaults for venue registration.
/// Contains country→currency and country→timezone mappings,
/// plus curated lists of currencies and timezones for the dropdown.
library;

/// Supported currencies with display information
class CurrencyOption {
  final String code;
  final String symbol;
  final String label;

  const CurrencyOption({
    required this.code,
    required this.symbol,
    required this.label,
  });
}

/// All supported currencies for the dropdown
const List<CurrencyOption> supportedCurrencies = [
  CurrencyOption(code: 'EUR', symbol: '€', label: 'EUR (€)'),
  CurrencyOption(code: 'USD', symbol: '\$', label: 'USD (\$)'),
  CurrencyOption(code: 'GBP', symbol: '£', label: 'GBP (£)'),
  CurrencyOption(code: 'CHF', symbol: 'Fr', label: 'CHF (Fr)'),
  CurrencyOption(code: 'MXN', symbol: '\$', label: 'MXN (\$)'),
  CurrencyOption(code: 'BRL', symbol: 'R\$', label: 'BRL (R\$)'),
  CurrencyOption(code: 'ARS', symbol: '\$', label: 'ARS (\$)'),
  CurrencyOption(code: 'COP', symbol: '\$', label: 'COP (\$)'),
];

/// Supported timezones with display format
class TimezoneOption {
  final String iana;
  final String displayName;

  const TimezoneOption({
    required this.iana,
    required this.displayName,
  });
}

/// Curated list of timezones for the dropdown
/// Full IANA names stored, city names displayed
const List<TimezoneOption> supportedTimezones = [
  // Europe
  TimezoneOption(iana: 'Europe/Madrid', displayName: 'Madrid'),
  TimezoneOption(iana: 'Europe/Paris', displayName: 'Paris'),
  TimezoneOption(iana: 'Europe/Berlin', displayName: 'Berlin'),
  TimezoneOption(iana: 'Europe/London', displayName: 'London'),
  TimezoneOption(iana: 'Europe/Rome', displayName: 'Rome'),
  TimezoneOption(iana: 'Europe/Lisbon', displayName: 'Lisbon'),
  TimezoneOption(iana: 'Europe/Amsterdam', displayName: 'Amsterdam'),
  // North America
  TimezoneOption(iana: 'America/New_York', displayName: 'New York'),
  TimezoneOption(iana: 'America/Chicago', displayName: 'Chicago'),
  TimezoneOption(iana: 'America/Denver', displayName: 'Denver'),
  TimezoneOption(iana: 'America/Los_Angeles', displayName: 'Los Angeles'),
  TimezoneOption(iana: 'America/Mexico_City', displayName: 'Mexico City'),
  // South America
  TimezoneOption(iana: 'America/Bogota', displayName: 'Bogotá'),
  TimezoneOption(iana: 'America/Lima', displayName: 'Lima'),
  TimezoneOption(iana: 'America/Santiago', displayName: 'Santiago'),
  TimezoneOption(iana: 'America/Sao_Paulo', displayName: 'São Paulo'),
  TimezoneOption(iana: 'America/Buenos_Aires', displayName: 'Buenos Aires'),
];

/// Convert a currency code (ISO 4217) to its display symbol.
/// Returns '€' if the code is not found in [supportedCurrencies].
String currencySymbolFromCode(String code) {
  try {
    return supportedCurrencies.firstWhere((c) => c.code == code).symbol;
  } catch (_) {
    return '€';
  }
}

/// Country code to default currency mapping
/// ISO 3166-1 alpha-2 → ISO 4217
const Map<String, String> countryToCurrency = {
  // Eurozone countries
  'AT': 'EUR', // Austria
  'BE': 'EUR', // Belgium
  'CY': 'EUR', // Cyprus
  'EE': 'EUR', // Estonia
  'FI': 'EUR', // Finland
  'FR': 'EUR', // France
  'DE': 'EUR', // Germany
  'GR': 'EUR', // Greece
  'IE': 'EUR', // Ireland
  'IT': 'EUR', // Italy
  'LV': 'EUR', // Latvia
  'LT': 'EUR', // Lithuania
  'LU': 'EUR', // Luxembourg
  'MT': 'EUR', // Malta
  'NL': 'EUR', // Netherlands
  'PT': 'EUR', // Portugal
  'SK': 'EUR', // Slovakia
  'SI': 'EUR', // Slovenia
  'ES': 'EUR', // Spain
  'HR': 'EUR', // Croatia (joined 2023)
  // Other currencies
  'GB': 'GBP', // United Kingdom
  'US': 'USD', // United States
  'CH': 'CHF', // Switzerland
  'MX': 'MXN', // Mexico
  'BR': 'BRL', // Brazil
  'AR': 'ARS', // Argentina
  'CO': 'COP', // Colombia
};

/// Country code to default timezone mapping
/// ISO 3166-1 alpha-2 → IANA timezone
const Map<String, String> countryToTimezone = {
  // Europe
  'ES': 'Europe/Madrid',
  'FR': 'Europe/Paris',
  'DE': 'Europe/Berlin',
  'GB': 'Europe/London',
  'IT': 'Europe/Rome',
  'PT': 'Europe/Lisbon',
  'NL': 'Europe/Amsterdam',
  'BE': 'Europe/Paris',
  'AT': 'Europe/Berlin',
  'CH': 'Europe/Berlin',
  'IE': 'Europe/London',
  'GR': 'Europe/Athens',
  // North America
  'US': 'America/New_York',
  'MX': 'America/Mexico_City',
  'CA': 'America/New_York',
  // South America
  'CO': 'America/Bogota',
  'PE': 'America/Lima',
  'CL': 'America/Santiago',
  'BR': 'America/Sao_Paulo',
  'AR': 'America/Buenos_Aires',
};

/// Set of Eurozone country codes
const Set<String> eurozoneCountries = {
  'AT', 'BE', 'CY', 'EE', 'FI', 'FR', 'DE', 'GR', 'IE', 'IT',
  'LV', 'LT', 'LU', 'MT', 'NL', 'PT', 'SK', 'SI', 'ES', 'HR',
};

/// Get the default currency for a country code
/// Returns EUR as fallback for unknown countries
String getDefaultCurrency(String? countryCode) {
  if (countryCode == null || countryCode.isEmpty) return 'EUR';
  final upper = countryCode.toUpperCase();
  return countryToCurrency[upper] ?? 'EUR';
}

/// Get the default timezone for a country code
/// Returns Europe/Madrid as fallback for unknown countries
String getDefaultTimezone(String? countryCode) {
  if (countryCode == null || countryCode.isEmpty) return 'Europe/Madrid';
  final upper = countryCode.toUpperCase();
  return countryToTimezone[upper] ?? 'Europe/Madrid';
}

/// Check if a country is in the Eurozone
bool isEurozoneCountry(String? countryCode) {
  if (countryCode == null || countryCode.isEmpty) return false;
  return eurozoneCountries.contains(countryCode.toUpperCase());
}

/// Get the display name for a timezone IANA identifier
String getTimezoneDisplayName(String iana) {
  for (final tz in supportedTimezones) {
    if (tz.iana == iana) return tz.displayName;
  }
  // Extract city name from IANA as fallback
  final parts = iana.split('/');
  return parts.last.replaceAll('_', ' ');
}

/// Validate that a currency code is supported
bool isValidCurrency(String? code) {
  if (code == null || code.isEmpty) return false;
  return supportedCurrencies.any((c) => c.code == code);
}

/// Validate that a timezone is in the supported list
bool isValidTimezone(String? iana) {
  if (iana == null || iana.isEmpty) return false;
  return supportedTimezones.any((tz) => tz.iana == iana);
}
