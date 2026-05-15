import 'package:flutter/services.dart';

import 'ticker_utils.dart';

/// Only letters A–Z (no icons, #, dots, or spaces in the field).
class TickerInputFormatter extends TextInputFormatter {
  static final RegExp _letter = RegExp(r'[A-Za-z]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    for (final rune in newValue.text.runes) {
      final ch = String.fromCharCode(rune);
      if (_letter.hasMatch(ch)) buffer.write(ch);
    }
    var text = buffer.toString().toUpperCase();
    if (text.length > 12) text = text.substring(0, 12);

    if (text == newValue.text) return newValue;

    final offset = newValue.selection.end.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}

TextEditingValue canonicalTickerValue(String raw) {
  final n = normalizeTicker(raw);
  return TextEditingValue(
    text: n,
    selection: TextSelection.collapsed(offset: n.length),
  );
}
