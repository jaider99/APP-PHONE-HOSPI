String normalizeDocumentNumber(String? raw) {
  if (raw == null) return '';
  return raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-/]'), '');
}

String normalizeSupplierName(String? raw) {
  if (raw == null) return '';

  var value = _removeSupplierNoise(raw.trim());
  value = _stripDiacritics(value).toLowerCase();
  value = value.replaceAll(
    RegExp(
      r'\s*(s\.?l\.?u?\.?|s\.?a\.?|ltd\.?|limited|sociedad limitada|sociedad anonima)\s*$',
      caseSensitive: false,
    ),
    '',
  );
  value = value.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return value;
}

String buildNormalizedDuplicateKey({
  String? documentNumber,
  double? totalAmount,
  DateTime? documentDate,
  String? supplierName,
}) {
  final normalizedNumber = normalizeDocumentNumber(documentNumber);
  if (normalizedNumber.isNotEmpty) return normalizedNumber;

  final normalizedSupplier = normalizeSupplierName(supplierName);
  if (normalizedSupplier.isEmpty || totalAmount == null || documentDate == null) {
    return '';
  }

  final cents = (totalAmount * 100).round();
  final y = documentDate.year.toString().padLeft(4, '0');
  final m = documentDate.month.toString().padLeft(2, '0');
  final d = documentDate.day.toString().padLeft(2, '0');
  return 'FALLBACK:$y$m$d:$cents:$normalizedSupplier';
}

String _removeSupplierNoise(String raw) {
  return raw.replaceAll(
    RegExp(
      r'\s+(albar[aá]n|factura|albar[aá]n\s+de\s+entrega|nota\s+de\s+cr[eé]dito|presupuesto|pedido|ticket|recibo|delivery\s+note|invoice)\s*$',
      caseSensitive: false,
    ),
    '',
  );
}

String _stripDiacritics(String input) {
  const replacements = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ç': 'c', 'ñ': 'n', '·': '',
    'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A',
    'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
    'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
    'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O',
    'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
    'Ç': 'C', 'Ñ': 'N',
  };

  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString();
}