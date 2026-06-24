import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/sales/presentation/providers/sales_providers.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/shared/ui/ui.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';

class SalesImportPrefill {
  const SalesImportPrefill({
    required this.providerKey,
    required this.providerName,
    required this.countryCode,
  });

  final String providerKey;
  final String providerName;
  final String countryCode;

  String get sourceName => '$providerName sales report';

  factory SalesImportPrefill.fromMap(Map<String, dynamic> map) {
    return SalesImportPrefill(
      providerKey: map['provider_key'] as String? ?? 'custom',
      providerName: map['provider_name'] as String? ?? 'POS',
      countryCode: map['country_code'] as String? ?? 'OTHER',
    );
  }
}

class ImportSalesScreen extends ConsumerStatefulWidget {
  const ImportSalesScreen({super.key, this.prefill});

  final SalesImportPrefill? prefill;

  @override
  ConsumerState<ImportSalesScreen> createState() => _ImportSalesScreenState();
}

class _ImportSalesScreenState extends ConsumerState<ImportSalesScreen> {
  PlatformFile? _file;
  Uint8List? _bytes;
  double _progress = 0;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final hasFile = _file != null && _bytes != null;
    final prefill = widget.prefill;

    return AppScaffold(
      clampContent: false,
      topBar: const AppTopBar(
        eyebrow: 'sales',
        title: 'Import report',
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
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prefill == null ? 'Daily sales report' : prefill.sourceName,
                  style: EditorialTypography.titleLarge.copyWith(
                    color: EditorialColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  prefill == null
                      ? 'Upload a POS export, closing report, or sales screenshot. Processing runs server-side and stays scoped to the active company.'
                      : 'Upload an export, closing report, or sales screenshot from ${prefill.providerName}. Processing runs server-side and stays scoped to the active company.',
                  style: const TextStyle(
                    color: EditorialColors.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickFile,
                  icon: const Icon(Icons.attach_file_outlined),
                  label: Text(hasFile ? 'Change file' : 'Choose report'),
                ),
                if (_file != null) ...[
                  const SizedBox(height: 16),
                  _SelectedFile(file: _file!),
                ],
                if (_submitting) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: _progress.clamp(0, 1)),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: hasFile && !_submitting ? _submit : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Import sales report'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const AppCard(
            child: Text(
              'Accepted formats: PDF, CSV, JPG, PNG, and WebP. POS API credentials are never entered here.',
              style: TextStyle(
                color: EditorialColors.onSurfaceVariant,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'csv', 'jpg', 'jpeg', 'png', 'webp'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (!mounted || bytes == null) return;

    setState(() {
      _file = file;
      _bytes = bytes;
      _progress = 0;
    });
  }

  Future<void> _submit() async {
    final file = _file;
    final bytes = _bytes;
    if (file == null || bytes == null) return;

    setState(() {
      _submitting = true;
      _progress = 0.05;
    });

    try {
      final companyId = await ref.read(companyIdProvider.future);
      if (companyId == null) {
        throw StateError('No active company. Please sign in again.');
      }

      await ref.read(salesRepositoryProvider).createSalesReportImport(
            companyId: companyId,
            fileName: file.name,
            fileBytes: bytes,
            mimeType: _mimeTypeForFile(file.name),
            sourceName: widget.prefill?.sourceName,
            providerKey: widget.prefill?.providerKey,
            providerName: widget.prefill?.providerName,
            countryCode: widget.prefill?.countryCode,
            onProgress: (value) {
              if (mounted) setState(() => _progress = value);
            },
          );

      ref.invalidate(salesImportsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sales report queued for processing')),
      );
      context.pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progress = 0;
        });
      }
    }
  }
}

class _SelectedFile extends StatelessWidget {
  const _SelectedFile({required this.file});

  final PlatformFile file;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.description_outlined, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EditorialTypography.bodyMedium,
          ),
        ),
        Text(
          _formatBytes(file.size),
          style: EditorialTypography.bodySmall.copyWith(
            color: EditorialColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _mimeTypeForFile(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  switch (extension) {
    case 'pdf':
      return 'application/pdf';
    case 'csv':
      return 'text/csv';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    default:
      return 'application/octet-stream';
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}