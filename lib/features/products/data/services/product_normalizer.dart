class ProductNormalizer {
  const ProductNormalizer();

  String normalizeKey(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'^\d+\s*[x×*]\s*'), '')
        .replaceAll(RegExp(r'^\d+\s+'), '')
        .replaceAll(
          RegExp(r'\s+\d+(\.\d+)?\s*(ml|cl|dl|l|g|kg|oz|lb|fl\.?\s*oz)\b'),
          '',
        )
        .replaceAll(RegExp(r'\s*\(\d[\w./×x\s]*\)'), '')
        .replaceAll(RegExp(r'\s+x\s*\d+$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(' ', '');
  }

  String normalizeDisplayName(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'^\d+\s*[x×*]\s*'), '')
        .replaceAll(RegExp(r'^\d+\s+'), '')
        .replaceAll(
          RegExp(r'\s+\d+(\.\d+)?\s*(ml|cl|dl|l|g|kg|oz|lb|fl\.?\s*oz)\b'),
          '',
        )
        .replaceAll(RegExp(r'\s*\(\d[\w./×x\s]*\)'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  List<String> extractAliasSeeds(String raw, {String? normalized}) {
    final values = <String>{
      raw.trim(),
      if (normalized != null && normalized.trim().isNotEmpty) normalized.trim(),
      normalizeDisplayName(raw),
    };

    return values.where((value) => value.isNotEmpty).toList();
  }
}