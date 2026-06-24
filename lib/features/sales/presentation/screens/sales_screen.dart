import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/sales/data/models/pos_connection.dart';
import 'package:hospi_dash/features/sales/data/models/pos_connection_result.dart';
import 'package:hospi_dash/features/sales/data/models/sale.dart';
import 'package:hospi_dash/features/sales/data/models/sales_import.dart';
import 'package:hospi_dash/features/sales/data/models/sales_summary.dart';
import 'package:hospi_dash/features/sales/data/repositories/sales_repository.dart';
import 'package:hospi_dash/features/sales/presentation/providers/sales_providers.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/services/step_up_auth_service.dart';
import 'package:hospi_dash/shared/ui/ui.dart';

enum _ImportAction { manage, delete }

enum _SaleAction { edit, delete }

enum _ConnectionAction { disconnect, delete }

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key, this.saleId});

  final String? saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(salesSummaryProvider);
    final imports = ref.watch(salesImportsProvider);
    final connections = ref.watch(posConnectionsProvider);
    final period = ref.watch(salesPeriodProvider);

    return AppScaffold(
      clampContent: false,
      topBar: AppTopBar(
        eyebrow: 'revenue',
        title: 'Sales',
        actions: [
          IconButton(
            tooltip: 'Import sales report',
            onPressed: () => context.push(AppRoutes.salesImport),
            icon: const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _PeriodFilters(selected: period)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: SectionHeader(
                eyebrow: _periodLabel(period),
                title: 'Revenue',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: summary.when(
                data: (data) => _SummaryGrid(summary: data),
                loading: () => const _SummarySkeleton(),
                error: (error, _) => ErrorState(
                  title: 'Could not load sales',
                  message: '$error',
                  onRetry: () => ref.invalidate(salesSummaryProvider),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: summary.maybeWhen(
                data: (data) => data.hasSales
                    ? const SizedBox.shrink()
                    : const _SalesEmptyActions(),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: SectionHeader(
                eyebrow: 'pipeline',
                title: 'Imports and POS',
                trailing: TextButton(
                  onPressed: () => context.push(AppRoutes.salesConnectPos),
                  child: const Text('Connect POS'),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              child: _PipelinePanel(
                imports: imports,
                connections: connections,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodFilters extends ConsumerWidget {
  const _PeriodFilters({required this.selected});

  final SalesPeriod selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final period in SalesPeriod.values)
            ChoiceChip(
              label: Text(_periodLabel(period)),
              selected: selected == period,
              onSelected: (_) {
                ref.read(salesPeriodProvider.notifier).state = period;
              },
            ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth > 620;
        return GridView.count(
          crossAxisCount: twoColumns ? 2 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: twoColumns ? 2.8 : 3.6,
          children: [
            _MetricCard(
              label: 'gross revenue',
              amount: summary.grossRevenue,
              emphasized: true,
            ),
            _MetricCard(label: 'net revenue', amount: summary.netRevenue),
            _MetricCard(label: 'tax', amount: summary.taxAmount),
            _CountCard(
              value: summary.transactionCount.toString(),
              amount: summary.averageTicket,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final double amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: FinancialValue(
        amount: amount,
        caption: label,
        size: emphasized ? MetricSize.large : MetricSize.medium,
        locale: 'es_ES',
        symbol: 'EUR ',
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.value, required this.amount});

  final String value;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'transactions',
                  style: EditorialTypography.labelSmall.copyWith(
                    color: EditorialColors.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                MetricText(value, size: MetricSize.large),
              ],
            ),
          ),
          FinancialValue(
            amount: amount,
            caption: 'average ticket',
            size: MetricSize.small,
            locale: 'es_ES',
            symbol: 'EUR ',
          ),
        ],
      ),
    );
  }
}

class _SalesEmptyActions extends StatelessWidget {
  const _SalesEmptyActions();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No sales yet',
            style: EditorialTypography.titleLarge.copyWith(
              color: EditorialColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect your POS or import a daily sales report to start tracking revenue.',
            style: TextStyle(
              color: EditorialColors.onSurfaceVariant,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.salesConnectPos),
                icon: const Icon(Icons.point_of_sale_outlined),
                label: const Text('Connect POS'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.salesImport),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import sales report'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelinePanel extends ConsumerWidget {
  const _PipelinePanel({required this.imports, required this.connections});

  final AsyncValue<List<SalesImport>> imports;
  final AsyncValue<List<PosConnection>> connections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          connections.when(
            data: (items) => _ConnectionRows(items: items),
            loading: () => const _PanelMessage('Loading POS connections...'),
            error: (error, _) =>
                _PanelMessage('POS status unavailable: $error'),
          ),
          const Divider(height: 1, color: EditorialColors.hairline),
          imports.when(
            data: (items) => _ImportRows(items: items),
            loading: () => const _PanelMessage('Loading imports...'),
            error: (error, _) => _PanelMessage('Imports unavailable: $error'),
          ),
        ],
      ),
    );
  }
}

class _ConnectionRows extends ConsumerWidget {
  const _ConnectionRows({required this.items});

  final List<PosConnection> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const _PanelMessage('No POS connected yet.');
    return Column(
      children: [
        for (final item in items)
          _PanelRow(
            icon: Icons.point_of_sale_outlined,
            title: item.providerName ?? item.provider,
            subtitle: item.syncStatus ?? 'connection ${item.status}',
            trailing: item.status,
            action: PopupMenuButton<_ConnectionAction>(
              tooltip: 'Manage POS connection',
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) {
                switch (action) {
                  case _ConnectionAction.disconnect:
                    _disconnectPosConnection(context, ref, item);
                  case _ConnectionAction.delete:
                    _deletePosConnection(context, ref, item);
                }
              },
              itemBuilder: (context) => [
                if (item.status.toLowerCase() != 'disconnected')
                  const PopupMenuItem(
                    value: _ConnectionAction.disconnect,
                    child: Text('Disconnect'),
                  ),
                const PopupMenuItem(
                  value: _ConnectionAction.delete,
                  child: Text('Delete connection'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ImportRows extends ConsumerWidget {
  const _ImportRows({required this.items});

  final List<SalesImport> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const _PanelMessage('No sales reports imported yet.');
    }
    return Column(
      children: [
        for (final item in items.take(5))
          _PanelRow(
            icon: Icons.description_outlined,
            title: item.sourceName ?? 'Sales report',
            subtitle: item.notes ?? _formatImportPeriod(item),
            trailing: item.status,
            action: PopupMenuButton<_ImportAction>(
              tooltip: 'Manage sales import',
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) {
                switch (action) {
                  case _ImportAction.manage:
                    _showImportManageSheet(context, item);
                  case _ImportAction.delete:
                    _deleteSalesImport(context, ref, item);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _ImportAction.manage,
                  child: Text('Manage records'),
                ),
                PopupMenuItem(
                  value: _ImportAction.delete,
                  child: Text('Delete import'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: EditorialColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: EditorialTypography.bodyLarge.copyWith(
                    color: EditorialColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: EditorialTypography.bodySmall.copyWith(
                    color: EditorialColors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          StatusBadge(label: trailing, tone: _toneForStatus(trailing)),
          if (action != null) ...[
            const SizedBox(width: 4),
            action!,
          ],
        ],
      ),
    );
  }
}

class _SalesImportManageSheet extends ConsumerWidget {
  const _SalesImportManageSheet({required this.import});

  final SalesImport import;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(importedSalesProvider(import.id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      shrinkWrap: true,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(
                eyebrow: import.status,
                title: import.sourceName ?? 'Sales report',
              ),
            ),
            StatusBadge(
              label: import.status,
              tone: _toneForStatus(import.status),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _formatImportPeriod(import),
          style: EditorialTypography.bodyMedium.copyWith(
            color: EditorialColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        sales.when(
          data: (items) {
            if (items.isEmpty) {
              return const _PanelMessage(
                'No canonical sales records found for this import.',
              );
            }
            return Column(
              children: [
                for (final sale in items)
                  _ImportedSaleRow(sale: sale, salesImportId: import.id),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _PanelMessage('Sales records unavailable: $error'),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => _deleteSalesImport(
            context,
            ref,
            import,
            closeOnSuccess: true,
          ),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete import'),
        ),
      ],
    );
  }
}

class _ImportedSaleRow extends ConsumerWidget {
  const _ImportedSaleRow({required this.sale, required this.salesImportId});

  final Sale sale;
  final String salesImportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: EditorialColors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(sale.saleDate),
                  style: EditorialTypography.bodyLarge.copyWith(
                    color: EditorialColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${sale.transactionCount} transaction${sale.transactionCount == 1 ? '' : 's'}',
                  style: EditorialTypography.bodySmall.copyWith(
                    color: EditorialColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'EUR ${sale.grossAmount.toStringAsFixed(2)}',
            style: EditorialTypography.bodyLarge.copyWith(
              color: EditorialColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_SaleAction>(
            tooltip: 'Manage sales record',
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) {
              switch (action) {
                case _SaleAction.edit:
                  _showSaleEditSheet(context, sale, salesImportId);
                case _SaleAction.delete:
                  _deleteSale(context, ref, sale, salesImportId);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: _SaleAction.edit, child: Text('Edit')),
              PopupMenuItem(value: _SaleAction.delete, child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaleEditSheet extends ConsumerStatefulWidget {
  const _SaleEditSheet({required this.sale, required this.salesImportId});

  final Sale sale;
  final String salesImportId;

  @override
  ConsumerState<_SaleEditSheet> createState() => _SaleEditSheetState();
}

class _SaleEditSheetState extends ConsumerState<_SaleEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _dateController;
  late final TextEditingController _grossController;
  late final TextEditingController _netController;
  late final TextEditingController _taxController;
  late final TextEditingController _discountController;
  late final TextEditingController _tipController;
  late final TextEditingController _transactionController;
  late final TextEditingController _paymentController;
  late final TextEditingController _notesController;
  late String _channel;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final sale = widget.sale;
    _dateController =
        TextEditingController(text: _formatDateInput(sale.saleDate));
    _grossController =
        TextEditingController(text: _formatAmountInput(sale.grossAmount));
    _netController =
        TextEditingController(text: _formatAmountInput(sale.netAmount));
    _taxController =
        TextEditingController(text: _formatAmountInput(sale.taxAmount));
    _discountController =
        TextEditingController(text: _formatAmountInput(sale.discountAmount));
    _tipController =
        TextEditingController(text: _formatAmountInput(sale.tipAmount));
    _transactionController =
        TextEditingController(text: sale.transactionCount.toString());
    _paymentController = TextEditingController(text: sale.paymentMethod ?? '');
    _notesController = TextEditingController(text: sale.notes ?? '');
    _channel = _safeChannel(sale.channel);
  }

  @override
  void dispose() {
    _dateController.dispose();
    _grossController.dispose();
    _netController.dispose();
    _taxController.dispose();
    _discountController.dispose();
    _tipController.dispose();
    _transactionController.dispose();
    _paymentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        shrinkWrap: true,
        children: [
          const SectionHeader(eyebrow: 'sales record', title: 'Edit sale'),
          const SizedBox(height: 14),
          TextFormField(
            controller: _dateController,
            decoration: const InputDecoration(labelText: 'Sale date'),
            validator: (value) => _parseDateInput(value ?? '') == null
                ? 'Use YYYY-MM-DD or DD/MM/YYYY'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _grossController,
            decoration: const InputDecoration(labelText: 'Gross revenue'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) => _parseMoneyInput(value ?? '') == null
                ? 'Enter a valid amount'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _netController,
            decoration: const InputDecoration(labelText: 'Net revenue'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _optionalMoneyValidator,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _taxController,
            decoration: const InputDecoration(labelText: 'Tax'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _optionalMoneyValidator,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _discountController,
                  decoration: const InputDecoration(labelText: 'Discount'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _optionalMoneyValidator,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _tipController,
                  decoration: const InputDecoration(labelText: 'Tips'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _optionalMoneyValidator,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _transactionController,
            decoration: const InputDecoration(labelText: 'Transactions'),
            keyboardType: TextInputType.number,
            validator: (value) {
              final count = int.tryParse((value ?? '').trim());
              return count == null || count < 1 ? 'Enter at least 1' : null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _channel,
            decoration: const InputDecoration(labelText: 'Channel'),
            items: const [
              DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
              DropdownMenuItem(value: 'dine_in', child: Text('Dine in')),
              DropdownMenuItem(value: 'takeaway', child: Text('Takeaway')),
              DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _channel = value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _paymentController,
            decoration: const InputDecoration(labelText: 'Payment method'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes'),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Saving...' : 'Save changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final saleDate = _parseDateInput(_dateController.text)!;
    final grossAmount = _parseMoneyInput(_grossController.text)!;
    final transactionCount = int.parse(_transactionController.text.trim());
    setState(() => _saving = true);

    try {
      final companyId = await ref.read(companyIdProvider.future);
      if (companyId == null) throw StateError('No active company selected.');
      await ref.read(salesRepositoryProvider).updateSale(
            companyId: companyId,
            saleId: widget.sale.id,
            saleDate: saleDate,
            grossAmount: grossAmount,
            netAmount: _parseOptionalMoneyInput(_netController.text),
            taxAmount: _parseOptionalMoneyInput(_taxController.text),
            discountAmount: _parseOptionalMoneyInput(_discountController.text),
            tipAmount: _parseOptionalMoneyInput(_tipController.text),
            transactionCount: transactionCount,
            channel: _channel,
            paymentMethod: _blankToNull(_paymentController.text),
            notes: _blankToNull(_notesController.text),
          );
      invalidateSalesSurfaces(ref, salesImportId: widget.salesImportId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger
          .showSnackBar(const SnackBar(content: Text('Sales record updated')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update sale: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          message,
          style: EditorialTypography.bodyMedium.copyWith(
            color: EditorialColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: SizedBox(
        height: 132,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

String _periodLabel(SalesPeriod period) {
  switch (period) {
    case SalesPeriod.today:
      return 'Today';
    case SalesPeriod.thisWeek:
      return 'This week';
    case SalesPeriod.thisMonth:
      return 'This month';
    case SalesPeriod.custom:
      return 'Custom';
  }
}

String _formatImportPeriod(SalesImport item) {
  final start = item.periodStart;
  final end = item.periodEnd;
  if (start == null || end == null) return 'Processing sales report';
  return '${start.day}/${start.month}/${start.year} - '
      '${end.day}/${end.month}/${end.year}';
}

void _showImportManageSheet(BuildContext context, SalesImport item) {
  showAppSheet<void>(
    context: context,
    fullHeight: true,
    builder: (_) => _SalesImportManageSheet(import: item),
  );
}

void _showSaleEditSheet(
  BuildContext context,
  Sale sale,
  String salesImportId,
) {
  showAppSheet<void>(
    context: context,
    fullHeight: true,
    builder: (_) => _SaleEditSheet(sale: sale, salesImportId: salesImportId),
  );
}

Future<void> _deleteSalesImport(
  BuildContext context,
  WidgetRef ref,
  SalesImport item, {
  bool closeOnSuccess = false,
}) async {
  final confirmed = await _confirmDestructiveAction(
    context,
    title: 'Delete sales import?',
    message:
        'This removes the import and linked sales records from revenue analytics.',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref
        .read(stepUpAuthServiceProvider)
        .requireStepUp(action: StepUpAction.deleteSalesData, required: false);
    final companyId = await ref.read(companyIdProvider.future);
    if (companyId == null) throw StateError('No active company selected.');
    await ref.read(salesRepositoryProvider).deleteSalesImport(
          companyId: companyId,
          salesImportId: item.id,
        );
    invalidateSalesSurfaces(ref, salesImportId: item.id);
    if (!context.mounted) return;
    if (closeOnSuccess) Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sales import deleted')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _safeSalesDeleteMessage(
            error,
            fallback: 'Could not delete sales import. Try again.',
          ),
        ),
      ),
    );
  }
}

Future<void> _deleteSale(
  BuildContext context,
  WidgetRef ref,
  Sale sale,
  String salesImportId,
) async {
  final confirmed = await _confirmDestructiveAction(
    context,
    title: 'Delete sales record?',
    message: 'This removes this sales record from revenue analytics.',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref
        .read(stepUpAuthServiceProvider)
        .requireStepUp(action: StepUpAction.deleteSalesData, required: false);
    await ref.read(salesRepositoryProvider).deleteSale(
          companyId: sale.companyId,
          saleId: sale.id,
        );
    invalidateSalesSurfaces(ref, salesImportId: salesImportId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sales record deleted')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _safeSalesDeleteMessage(
            error,
            fallback: 'Could not delete sale. Try again.',
          ),
        ),
      ),
    );
  }
}

Future<void> _disconnectPosConnection(
  BuildContext context,
  WidgetRef ref,
  PosConnection item,
) async {
  final confirmed = await _confirmDestructiveAction(
    context,
    title: 'Disconnect POS?',
    message:
        'This stops sync and clears stored POS credentials. Historical sales stay in place.',
    actionLabel: 'Disconnect',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(stepUpAuthServiceProvider).requireStepUp(
          action: StepUpAction.managePosConnection,
          required: false,
        );
    await ref.read(salesRepositoryProvider).disconnectPosConnection(item.id);
    invalidateSalesSurfaces(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('POS disconnected')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _safeSalesDeleteMessage(
            error,
            fallback: 'Could not disconnect POS. Try again.',
          ),
        ),
      ),
    );
  }
}

Future<void> _deletePosConnection(
  BuildContext context,
  WidgetRef ref,
  PosConnection item,
) async {
  final confirmed = await _confirmDestructiveAction(
    context,
    title: 'Delete POS connection?',
    message:
        'This removes the connection record. Historical sales stay in place.',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(stepUpAuthServiceProvider).requireStepUp(
          action: StepUpAction.managePosConnection,
          required: false,
        );
    await ref.read(salesRepositoryProvider).deletePosConnection(
          companyId: item.companyId,
          connectionId: item.id,
        );
    invalidateSalesSurfaces(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('POS connection deleted')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _safeSalesDeleteMessage(
            error,
            fallback: 'Could not delete POS connection. Try again.',
          ),
        ),
      ),
    );
  }
}

String _safeSalesDeleteMessage(Object error, {required String fallback}) {
  if (error is SalesDeleteException) return error.message;
  if (error is StepUpAuthException) return error.message;
  if (error is PosConnectionRequestException) return error.message;
  return fallback;
}

Future<bool> _confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'Delete',
}) async {
  return await showAppSheet<bool>(
        context: context,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: EditorialTypography.titleLarge.copyWith(
                  color: EditorialColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: EditorialTypography.bodyMedium.copyWith(
                  color: EditorialColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You may be asked to confirm this action.',
                style: EditorialTypography.bodySmall.copyWith(
                  color: EditorialColors.outline,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;
}

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/'
    '${date.year.toString().padLeft(4, '0')}';

String _formatDateInput(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _parseDateInput(String value) {
  final trimmed = value.trim();
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(trimmed);
  if (iso != null) {
    return _validDate(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  final dayFirst = RegExp(r'^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2}|\d{4})$')
      .firstMatch(trimmed);
  if (dayFirst == null) return null;
  final yearToken = int.parse(dayFirst.group(3)!);
  return _validDate(
    dayFirst.group(3)!.length == 2 ? 2000 + yearToken : yearToken,
    int.parse(dayFirst.group(2)!),
    int.parse(dayFirst.group(1)!),
  );
}

DateTime? _validDate(int year, int month, int day) {
  if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1) {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

String _formatAmountInput(double? value) =>
    value == null ? '' : value.toStringAsFixed(2);

double? _parseMoneyInput(String value) {
  final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final parsed = double.tryParse(normalized);
  return parsed == null || parsed < 0 ? null : parsed;
}

double? _parseOptionalMoneyInput(String value) =>
    value.trim().isEmpty ? null : _parseMoneyInput(value);

String? _optionalMoneyValidator(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return _parseMoneyInput(value) == null ? 'Enter a valid amount' : null;
}

String _safeChannel(String? value) {
  switch (value) {
    case 'dine_in':
    case 'takeaway':
    case 'delivery':
    case 'unknown':
      return value!;
    default:
      return 'unknown';
  }
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

BadgeTone _toneForStatus(String status) {
  switch (status.toLowerCase()) {
    case 'completed':
    case 'active':
    case 'connected':
      return BadgeTone.success;
    case 'processing':
    case 'pending':
      return BadgeTone.info;
    case 'failed':
    case 'revoked':
      return BadgeTone.error;
    default:
      return BadgeTone.neutral;
  }
}
