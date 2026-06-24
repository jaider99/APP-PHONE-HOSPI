enum PosConnectionMode {
  nativeOAuth,
  nativeApiKey,
  assistedCredentials,
  importReports,
  requestOnly,
  custom,
}

enum PosConnectionStatus {
  live,
  beta,
  setupRequired,
  importOnly,
  requested,
  unavailable,
}

enum PosProviderGroup {
  connectAutomatically,
  importReports,
  guidedSetup,
  requestIntegration,
}

class PosMarketDefinition {
  const PosMarketDefinition({
    required this.countryCode,
    required this.countryName,
    this.region,
  });

  final String countryCode;
  final String countryName;
  final String? region;
}

class PosProviderDefinition {
  const PosProviderDefinition({
    required this.key,
    required this.displayName,
    required this.countries,
    required this.connectionMode,
    required this.connectionStatus,
    required this.description,
    this.supportsOAuth = false,
    this.supportsApiKey = false,
    this.supportsFileImport = true,
    this.supportsEmailInvite = false,
    this.hasBackendAdapter = false,
    this.edgeFunctionName,
    this.documentationUrl,
    this.notes,
  });

  final String key;
  final String displayName;
  final List<String> countries;
  final PosConnectionMode connectionMode;
  final PosConnectionStatus connectionStatus;
  final String description;
  final bool supportsOAuth;
  final bool supportsApiKey;
  final bool supportsFileImport;
  final bool supportsEmailInvite;
  final bool hasBackendAdapter;
  final String? edgeFunctionName;
  final String? documentationUrl;
  final String? notes;

  bool supportsCountry(String countryCode) {
    return countries.contains(countryCode) || countries.contains('OTHER');
  }

  bool get canStartNativeConnection {
    return hasBackendAdapter &&
        (connectionStatus == PosConnectionStatus.live ||
            connectionStatus == PosConnectionStatus.beta) &&
        (connectionMode == PosConnectionMode.nativeOAuth ||
            connectionMode == PosConnectionMode.nativeApiKey);
  }

  bool get primaryActionUsesBackend {
    return connectionMode == PosConnectionMode.custom || canStartNativeConnection;
  }

  bool get showsRequestAction {
    return !canStartNativeConnection && connectionMode != PosConnectionMode.custom;
  }

  PosProviderGroup get group {
    if (canStartNativeConnection) return PosProviderGroup.connectAutomatically;
    if (connectionMode == PosConnectionMode.custom ||
        connectionMode == PosConnectionMode.importReports ||
        connectionStatus == PosConnectionStatus.importOnly) {
      return PosProviderGroup.importReports;
    }
    if (connectionMode == PosConnectionMode.assistedCredentials ||
        connectionMode == PosConnectionMode.nativeOAuth ||
        connectionMode == PosConnectionMode.nativeApiKey) {
      return PosProviderGroup.guidedSetup;
    }
    return PosProviderGroup.requestIntegration;
  }

  String get connectionModeKey {
    switch (connectionMode) {
      case PosConnectionMode.nativeOAuth:
        return 'native_oauth';
      case PosConnectionMode.nativeApiKey:
        return 'native_api_key';
      case PosConnectionMode.assistedCredentials:
        return 'assisted_credentials';
      case PosConnectionMode.importReports:
        return 'import_reports';
      case PosConnectionMode.requestOnly:
        return 'request_only';
      case PosConnectionMode.custom:
        return 'custom';
    }
  }

  String get connectionModeLabel {
    switch (connectionMode) {
      case PosConnectionMode.nativeOAuth:
        return 'OAuth candidate';
      case PosConnectionMode.nativeApiKey:
        return 'API candidate';
      case PosConnectionMode.assistedCredentials:
        return 'Guided setup';
      case PosConnectionMode.importReports:
        return 'Report import';
      case PosConnectionMode.requestOnly:
        return 'Request only';
      case PosConnectionMode.custom:
        return 'Custom import';
    }
  }

  String get connectionStatusKey {
    switch (connectionStatus) {
      case PosConnectionStatus.live:
        return 'live';
      case PosConnectionStatus.beta:
        return 'beta';
      case PosConnectionStatus.setupRequired:
        return 'setup_required';
      case PosConnectionStatus.importOnly:
        return 'import_only';
      case PosConnectionStatus.requested:
        return 'requested';
      case PosConnectionStatus.unavailable:
        return 'unavailable';
    }
  }

  String get connectionStatusLabel {
    switch (connectionStatus) {
      case PosConnectionStatus.live:
        return 'Live';
      case PosConnectionStatus.beta:
        return 'Beta';
      case PosConnectionStatus.setupRequired:
        return 'Setup required';
      case PosConnectionStatus.importOnly:
        return 'Import only';
      case PosConnectionStatus.requested:
        return 'Request only';
      case PosConnectionStatus.unavailable:
        return 'Unavailable';
    }
  }

  String get primaryActionLabel {
    if (canStartNativeConnection) return 'Connect';
    if (connectionMode == PosConnectionMode.custom) return 'Set up import';
    return 'Import reports';
  }

  String get requestActionLabel {
    switch (connectionMode) {
      case PosConnectionMode.nativeOAuth:
      case PosConnectionMode.nativeApiKey:
        return 'Request native sync';
      case PosConnectionMode.assistedCredentials:
        return 'Request guided setup';
      case PosConnectionMode.requestOnly:
        return 'Request integration';
      case PosConnectionMode.importReports:
        return 'Request automation';
      case PosConnectionMode.custom:
        return 'Set up import';
    }
  }
}

const posMarketDefinitions = <PosMarketDefinition>[
  PosMarketDefinition(
    countryCode: 'ES',
    countryName: 'Spain',
    region: 'Europe',
  ),
  PosMarketDefinition(
    countryCode: 'US',
    countryName: 'United States',
    region: 'North America',
  ),
  PosMarketDefinition(
    countryCode: 'GB',
    countryName: 'United Kingdom',
    region: 'Europe',
  ),
  PosMarketDefinition(
    countryCode: 'FR',
    countryName: 'France',
    region: 'Europe',
  ),
  PosMarketDefinition(
    countryCode: 'IT',
    countryName: 'Italy',
    region: 'Europe',
  ),
  PosMarketDefinition(
    countryCode: 'DE',
    countryName: 'Germany',
    region: 'Europe',
  ),
  PosMarketDefinition(
    countryCode: 'CO',
    countryName: 'Colombia',
    region: 'LATAM',
  ),
  PosMarketDefinition(
    countryCode: 'MX',
    countryName: 'Mexico',
    region: 'LATAM',
  ),
  PosMarketDefinition(
    countryCode: 'PT',
    countryName: 'Portugal',
    region: 'Europe',
  ),
  PosMarketDefinition(
    countryCode: 'NL',
    countryName: 'Netherlands',
    region: 'Europe',
  ),
  PosMarketDefinition(
    countryCode: 'OTHER',
    countryName: 'Other',
    region: 'Global',
  ),
];

const posProviderDefinitions = <PosProviderDefinition>[
  PosProviderDefinition(
    key: 'custom',
    displayName: 'Custom POS',
    countries: _allCountries,
    connectionMode: PosConnectionMode.custom,
    connectionStatus: PosConnectionStatus.importOnly,
    description: 'Use sales reports from any POS without entering credentials.',
    edgeFunctionName: 'connect-pos',
    notes: 'Creates a tenant-scoped import connection with no POS secrets.',
  ),
  PosProviderDefinition(
    key: 'square',
    displayName: 'Square',
    countries: ['ES', 'US', 'GB', 'FR'],
    connectionMode: PosConnectionMode.nativeOAuth,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Official OAuth and Orders APIs exist; HospiDash sync is not live yet.',
    supportsOAuth: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://developer.squareup.com/docs/oauth-api/overview',
    notes: 'Use report imports until the Square adapter is implemented.',
  ),
  PosProviderDefinition(
    key: 'lightspeed',
    displayName: 'Lightspeed',
    countries: ['ES', 'US', 'GB', 'FR', 'IT', 'DE', 'PT', 'NL'],
    connectionMode: PosConnectionMode.nativeOAuth,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Retail OAuth/Sales APIs are public; restaurant setup may require portal access.',
    supportsOAuth: true,
    supportsEmailInvite: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://developers.lightspeedhq.com/retail/authentication/authentication-overview/',
    notes: 'Treat K-Series as assisted setup until credentials and scope are confirmed.',
  ),
  PosProviderDefinition(
    key: 'toast',
    displayName: 'Toast',
    countries: ['US'],
    connectionMode: PosConnectionMode.assistedCredentials,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Toast API access depends on approved integration type and permissions.',
    supportsOAuth: true,
    supportsEmailInvite: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://doc.toasttab.com/doc/devguide/apiOverview.html',
    notes: 'US-only in the current catalog.',
  ),
  PosProviderDefinition(
    key: 'clover',
    displayName: 'Clover',
    countries: ['US', 'GB'],
    connectionMode: PosConnectionMode.nativeOAuth,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Official Orders API exists, but no HospiDash adapter is live.',
    supportsOAuth: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://docs.clover.com/dev/reference/orders',
  ),
  PosProviderDefinition(
    key: 'sumup',
    displayName: 'SumUp',
    countries: ['GB', 'FR', 'IT', 'DE', 'PT', 'NL'],
    connectionMode: PosConnectionMode.nativeApiKey,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Transaction APIs exist; secure server-side credential storage is required first.',
    supportsApiKey: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://developer.sumup.com/api/transactions',
    notes: 'Do not collect API keys in Flutter.',
  ),
  PosProviderDefinition(
    key: 'zettle',
    displayName: 'Zettle',
    countries: ['GB', 'FR', 'IT', 'DE', 'NL'],
    connectionMode: PosConnectionMode.nativeOAuth,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Purchase and Finance APIs exist; HospiDash sync is not live yet.',
    supportsOAuth: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://developer.zettle.com/docs/api/purchase/overview',
  ),
  PosProviderDefinition(
    key: 'glop',
    displayName: 'Glop',
    countries: ['ES'],
    connectionMode: PosConnectionMode.assistedCredentials,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Official API entry point exists and requires developer registration.',
    supportsApiKey: true,
    supportsEmailInvite: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://www.glop.es/api/',
  ),
  PosProviderDefinition(
    key: 'agora',
    displayName: 'Agora',
    countries: ['ES'],
    connectionMode: PosConnectionMode.assistedCredentials,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Official partner/integration flow exists; no self-serve API was verified.',
    supportsEmailInvite: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://www.agorapos.com/integraciones/',
  ),
  PosProviderDefinition(
    key: 'revo',
    displayName: 'Revo',
    countries: ['ES'],
    connectionMode: PosConnectionMode.requestOnly,
    connectionStatus: PosConnectionStatus.requested,
    description: 'Public API details were not verified in this pass.',
    edgeFunctionName: 'connect-pos',
    notes: 'Save demand signal and use report import for immediate value.',
  ),
  PosProviderDefinition(
    key: 'covermanager',
    displayName: 'CoverManager',
    countries: ['ES'],
    connectionMode: PosConnectionMode.assistedCredentials,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Developer/API entry points appear gated; sales sync needs verification.',
    supportsEmailInvite: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://developers.covermanager.com/',
  ),
  PosProviderDefinition(
    key: 'lastapp',
    displayName: 'Last.app',
    countries: ['ES'],
    connectionMode: PosConnectionMode.assistedCredentials,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Developer portal is login-gated; setup must be assisted.',
    supportsEmailInvite: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://developers.last.app/',
  ),
  PosProviderDefinition(
    key: 'poster',
    displayName: 'Poster',
    countries: ['CO', 'MX', 'PT'],
    connectionMode: PosConnectionMode.nativeApiKey,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Transaction APIs exist; secure credential validation is not implemented yet.',
    supportsApiKey: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://dev.joinposter.com/en/docs/v3/web/transactions/getTransactions',
    notes: 'Do not collect integration tokens in Flutter.',
  ),
  PosProviderDefinition(
    key: 'alegra_pos',
    displayName: 'Alegra POS',
    countries: ['CO', 'MX'],
    connectionMode: PosConnectionMode.assistedCredentials,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Alegra APIs exist, but credentials and accounting setup require guidance.',
    supportsApiKey: true,
    supportsEmailInvite: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://developer.alegra.com/reference/autenticaci%C3%B3n',
  ),
  PosProviderDefinition(
    key: 'siigo',
    displayName: 'Siigo',
    countries: ['CO'],
    connectionMode: PosConnectionMode.assistedCredentials,
    connectionStatus: PosConnectionStatus.setupRequired,
    description: 'Siigo API requires username/access key and Partner-Id; setup is assisted.',
    supportsApiKey: true,
    supportsEmailInvite: true,
    edgeFunctionName: 'connect-pos',
    documentationUrl: 'https://siigoapi.docs.apiary.io/',
  ),
];

const _allCountries = [
  'ES',
  'US',
  'GB',
  'FR',
  'IT',
  'DE',
  'CO',
  'MX',
  'PT',
  'NL',
  'OTHER',
];

List<PosProviderDefinition> providersForCountry(String countryCode) {
  final providers = posProviderDefinitions
      .where((provider) => provider.supportsCountry(countryCode))
      .toList();
  providers.sort((a, b) {
    final rank = _groupRank(a.group).compareTo(_groupRank(b.group));
    if (rank != 0) return rank;
    return a.displayName.compareTo(b.displayName);
  });
  return providers;
}

Map<PosProviderGroup, List<PosProviderDefinition>> groupedProvidersForCountry(
  String countryCode,
) {
  final grouped = <PosProviderGroup, List<PosProviderDefinition>>{};
  for (final provider in providersForCountry(countryCode)) {
    grouped.putIfAbsent(provider.group, () => []).add(provider);
  }
  return grouped;
}

String providerGroupTitle(PosProviderGroup group) {
  switch (group) {
    case PosProviderGroup.connectAutomatically:
      return 'Connect automatically';
    case PosProviderGroup.importReports:
      return 'Import reports';
    case PosProviderGroup.guidedSetup:
      return 'Guided setup';
    case PosProviderGroup.requestIntegration:
      return 'Request integration';
  }
}

String providerGroupDescription(PosProviderGroup group) {
  switch (group) {
    case PosProviderGroup.connectAutomatically:
      return 'Live adapters that can start a server-side connection now.';
    case PosProviderGroup.importReports:
      return 'Immediate sales ingestion without POS credentials.';
    case PosProviderGroup.guidedSetup:
      return 'Official APIs or partner paths exist, but HospiDash needs assisted setup or an adapter first.';
    case PosProviderGroup.requestIntegration:
      return 'Providers without verified self-serve support yet. Save the request and import reports meanwhile.';
  }
}

int _groupRank(PosProviderGroup group) {
  switch (group) {
    case PosProviderGroup.connectAutomatically:
      return 0;
    case PosProviderGroup.importReports:
      return 1;
    case PosProviderGroup.guidedSetup:
      return 2;
    case PosProviderGroup.requestIntegration:
      return 3;
  }
}
