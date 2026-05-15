/// Normalizes user input to a single IDX-style ticker (letters only).
String normalizeTicker(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    if (RegExp(r'[A-Za-z]').hasMatch(ch)) buffer.write(ch);
  }
  return buffer.toString().toUpperCase();
}
