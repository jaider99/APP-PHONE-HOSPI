import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/sales/data/models/pos_provider_definition.dart';
import 'package:hospi_dash/features/sales/data/models/pos_connection_result.dart';
import 'package:hospi_dash/features/sales/presentation/screens/import_sales_screen.dart';
import 'package:hospi_dash/features/sales/presentation/providers/sales_providers.dart';
import 'package:hospi_dash/shared/ui/ui.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';

class ConnectPosScreen extends ConsumerStatefulWidget {
  const ConnectPosScreen({super.key});

  @override
  ConsumerState<ConnectPosScreen> createState() => _ConnectPosScreenState();
}

class _ConnectPosScreenState extends ConsumerState<ConnectPosScreen> {
  PosMarketDefinition _market = posMarketDefinitions.first;
  String? _submittingProviderKey;

  @override
  Widget build(BuildContext context) {
    final providerGroups = groupedProvidersForCountry(_market.countryCode);
    final providerCount = providerGroups.values.fold<int>(
      0,
      (count, providers) => count + providers.length,
    );

    return AppScaffold(
      clampContent: false,
      topBar: const AppTopBar(
        eyebrow: 'sales',
        title: 'Connect POS',
        leading: AppBackButton(fallbackRoute: AppRoutes.sales),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        children: [
          _IntroCard(
            market: _market,
            onImport: () => _openImport(),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(
            eyebrow: 'market',
            title: 'Choose country',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.sm),
          _CountryGrid(
            selected: _market,
            onSelected: (market) => setState(() => _market = market),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            eyebrow: _market.countryName,
            title: 'Smart connection options',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (providerCount == 0)
            _NoProviderCard(onImport: () => _openImport())
          else
            for (final entry in providerGroups.entries) ...[
              _ProviderGroupHeader(group: entry.key),
              const SizedBox(height: AppSpacing.sm),
              for (final provider in entry.value) ...[
                _ProviderCard(
                  provider: provider,
                  countryCode: _market.countryCode,
                  submitting: _submittingProviderKey == provider.key,
                  disabled: _submittingProviderKey != null &&
                      _submittingProviderKey != provider.key,
                  onPrimaryPressed: provider.primaryActionUsesBackend
                      ? () => _handleProvider(provider)
                      : () => _openImport(provider),
                  onRequestPressed: provider.showsRequestAction
                      ? () => _handleProvider(provider)
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _openImport(),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import sales report instead'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleProvider(PosProviderDefinition provider) async {
    setState(() => _submittingProviderKey = provider.key);
    try {
      final result =
          await ref.read(salesRepositoryProvider).requestPosConnection(
                countryCode: _market.countryCode,
                providerKey: provider.key,
                connectionMode: provider.connectionModeKey,
              );
      ref.invalidate(posConnectionsProvider);
      if (!mounted) return;
      _showMessage(result.message);
      if (result.shouldOpenImport) {
        _openImport(provider);
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(_safeConnectPosError(error));
    } finally {
      if (mounted) setState(() => _submittingProviderKey = null);
    }
  }

  void _openImport([PosProviderDefinition? provider]) {
    context.push(
      AppRoutes.salesImport,
      extra: provider == null
          ? null
          : SalesImportPrefill(
              providerKey: provider.key,
              providerName: provider.displayName,
              countryCode: _market.countryCode,
            ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _safeConnectPosError(Object error) {
    if (error is PosConnectionRequestException) return error.message;
    return 'POS connection request could not be completed. Please try again.';
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.market, required this.onImport});

  final PosMarketDefinition market;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose your market first',
            style: EditorialTypography.titleLarge.copyWith(
              color: EditorialColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'HospiDash shows providers relevant to ${market.countryName}. Native sync appears only when a backend adapter exists; report import stays available for every POS.',
            style: EditorialTypography.bodyMedium.copyWith(
              color: EditorialColors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Import sales report'),
          ),
        ],
      ),
    );
  }
}

class _CountryGrid extends StatelessWidget {
  const _CountryGrid({required this.selected, required this.onSelected});

  final PosMarketDefinition selected;
  final ValueChanged<PosMarketDefinition> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth > 560;
        return GridView.count(
          crossAxisCount: twoColumns ? 2 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: twoColumns ? 4.6 : 5.2,
          children: [
            for (final market in posMarketDefinitions)
              _CountryTile(
                market: market,
                selected: selected.countryCode == market.countryCode,
                onTap: () => onSelected(market),
              ),
          ],
        );
      },
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({
    required this.market,
    required this.selected,
    required this.onTap,
  });

  final PosMarketDefinition market;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected
                ? EditorialColors.accent
                : EditorialColors.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  market.countryName,
                  style: EditorialTypography.bodyLarge.copyWith(
                    color: EditorialColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (market.region != null)
                  Text(
                    market.region!,
                    style: EditorialTypography.bodySmall.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            market.countryCode,
            style: EditorialTypography.labelSmall.copyWith(
              color: EditorialColors.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderGroupHeader extends StatelessWidget {
  const _ProviderGroupHeader({required this.group});

  final PosProviderGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          providerGroupTitle(group),
          style: EditorialTypography.titleSmall.copyWith(
            color: EditorialColors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          providerGroupDescription(group),
          style: EditorialTypography.bodySmall.copyWith(
            color: EditorialColors.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.countryCode,
    required this.submitting,
    required this.disabled,
    required this.onPrimaryPressed,
    this.onRequestPressed,
  });

  final PosProviderDefinition provider;
  final String countryCode;
  final bool submitting;
  final bool disabled;
  final VoidCallback onPrimaryPressed;
  final VoidCallback? onRequestPressed;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.displayName,
                      style: EditorialTypography.titleMedium.copyWith(
                        color: EditorialColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      provider.description,
                      style: EditorialTypography.bodyMedium.copyWith(
                        color: EditorialColors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusBadge(
                label: provider.connectionStatusLabel,
                tone: _statusTone(provider.connectionStatus),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(label: provider.connectionModeLabel),
              StatusBadge(
                label: provider.hasBackendAdapter
                    ? 'Backend ready'
                    : 'No live adapter',
                tone: provider.hasBackendAdapter
                    ? BadgeTone.success
                    : BadgeTone.neutral,
              ),
              StatusBadge(label: countryCode),
            ],
          ),
          if (provider.notes != null) ...[
            const SizedBox(height: 12),
            Text(
              provider.notes!,
              style: EditorialTypography.bodySmall.copyWith(
                color: EditorialColors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ProviderButton(
                provider: provider,
                submitting: submitting,
                disabled: disabled,
                onPressed: onPrimaryPressed,
              ),
              if (onRequestPressed != null)
                OutlinedButton.icon(
                  onPressed: disabled || submitting ? null : onRequestPressed,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(provider.requestActionLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.provider,
    required this.submitting,
    required this.disabled,
    required this.onPressed,
  });

  final PosProviderDefinition provider;
  final bool submitting;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = provider.canStartNativeConnection
        ? Icons.link_rounded
        : provider.connectionMode == PosConnectionMode.custom
            ? Icons.tune_rounded
            : Icons.upload_file_outlined;

    return FilledButton.icon(
      onPressed: disabled || submitting ? null : onPressed,
      icon: submitting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(submitting ? 'Working...' : provider.primaryActionLabel),
    );
  }
}

class _NoProviderCard extends StatelessWidget {
  const _NoProviderCard({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No direct POS integrations yet',
            style: EditorialTypography.titleMedium.copyWith(
              color: EditorialColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use Custom POS or import sales reports while we add direct integrations for this market.',
            style: EditorialTypography.bodyMedium.copyWith(
              color: EditorialColors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import sales report'),
          ),
        ],
      ),
    );
  }
}

BadgeTone _statusTone(PosConnectionStatus status) {
  switch (status) {
    case PosConnectionStatus.live:
    case PosConnectionStatus.beta:
    case PosConnectionStatus.importOnly:
      return BadgeTone.success;
    case PosConnectionStatus.setupRequired:
    case PosConnectionStatus.requested:
      return BadgeTone.info;
    case PosConnectionStatus.unavailable:
      return BadgeTone.neutral;
  }
}
