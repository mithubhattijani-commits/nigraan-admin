// Tolerant parser for the JS array/object literals the Nigraan TV site
// and admin panel use (window.ARTICLES_DATA in /articles.js and
// var BREAKING_TICKER in the homepage HTML).
//
// The literals are NOT JSON: keys are unquoted identifiers, strings use
// single quotes, numbers are bare. This parser handles: objects,
// arrays, single/double-quoted strings with backslash escapes, numbers,
// true/false/null, and // + /* */ comments. On any syntax problem it
// throws FormatException with the position — callers treat that as
// "could not load" and show the stored error, never a crash.
//
// The web admin panel does the same job in JS (parseJsArrayLiteral /
// extractArrayLiteral); this is the Dart port of that behaviour.
library;

/// Extract the array literal that follows [marker] in [text].
/// Finds the first '[' after the marker, then returns the balanced
/// bracket substring (string-aware, so brackets inside quotes do not
/// count). Throws FormatException when the marker or the closing
/// bracket cannot be found.
String extractArrayLiteral(String text, String marker) {
  final m = text.indexOf(marker);
  if (m < 0) throw FormatException('marker not found: $marker');
  final start = text.indexOf('[', m);
  if (start < 0) throw FormatException('no array after marker: $marker');
  var depth = 0;
  var i = start;
  String? quote;
  while (i < text.length) {
    final c = text[i];
    if (quote != null) {
      if (c == '\\') {
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      i++;
      continue;
    }
    if (c == '[') depth++;
    if (c == ']') {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
    i++;
  }
  throw const FormatException('unterminated array literal');
}

/// Parse a JS value literal (object, array, string, number, bool, null).
dynamic parseJsLiteral(String src) => _JsParser(src).parse();

class _JsParser {
  _JsParser(this.src);
  final String src;
  int pos = 0;

  dynamic parse() {
    _ws();
    final v = _value();
    _ws();
    return v;
  }

  void _ws() {
    while (pos < src.length) {
      final c = src[pos];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        pos++;
        continue;
      }
      if (src.startsWith('//', pos)) {
        final nl = src.indexOf('\n', pos);
        pos = nl < 0 ? src.length : nl + 1;
        continue;
      }
      if (src.startsWith('/*', pos)) {
        final end = src.indexOf('*/', pos + 2);
        pos = end < 0 ? src.length : end + 2;
        continue;
      }
      break;
    }
  }

  dynamic _value() {
    _ws();
    if (pos >= src.length) throw FormatException('unexpected end at $pos');
    final c = src[pos];
    if (c == '[') return _array();
    if (c == '{') return _object();
    if (c == "'" || c == '"') return _string();
    if (c == '-' || (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57)) {
      return _number();
    }
    if (src.startsWith('true', pos)) {
      pos += 4;
      return true;
    }
    if (src.startsWith('false', pos)) {
      pos += 5;
      return false;
    }
    if (src.startsWith('null', pos)) {
      pos += 4;
      return null;
    }
    if (src.startsWith('undefined', pos)) {
      pos += 9;
      return null;
    }
    throw FormatException('unexpected char "$c" at $pos');
  }

  List<dynamic> _array() {
    pos++; // [
    final out = <dynamic>[];
    _ws();
    if (pos < src.length && src[pos] == ']') {
      pos++;
      return out;
    }
    while (true) {
      _ws();
      if (pos < src.length && src[pos] == ',') {
        // JS elision: [a,,b] or a stray extra comma -> undefined element.
        // (The live articles.js has one such hole; treat it as null.)
        out.add(null);
        pos++;
        _ws();
        if (pos < src.length && src[pos] == ']') {
          pos++;
          return out;
        }
        continue;
      }
      out.add(_value());
      _ws();
      if (pos >= src.length) throw FormatException('unterminated array');
      if (src[pos] == ',') {
        pos++;
        _ws();
        // Trailing comma before ] is legal in JS.
        if (pos < src.length && src[pos] == ']') {
          pos++;
          return out;
        }
        continue;
      }
      if (src[pos] == ']') {
        pos++;
        return out;
      }
      throw FormatException('expected , or ] at $pos');
    }
  }

  Map<String, dynamic> _object() {
    pos++; // {
    final out = <String, dynamic>{};
    _ws();
    if (pos < src.length && src[pos] == '}') {
      pos++;
      return out;
    }
    while (true) {
      _ws();
      String key;
      if (pos < src.length && (src[pos] == "'" || src[pos] == '"')) {
        key = _string();
      } else {
        final start = pos;
        while (pos < src.length &&
            (src.codeUnitAt(pos) == 95 || // _
                src.codeUnitAt(pos) == 36 || // $
                (src.codeUnitAt(pos) >= 48 && src.codeUnitAt(pos) <= 57) ||
                (src.codeUnitAt(pos) >= 65 && src.codeUnitAt(pos) <= 90) ||
                (src.codeUnitAt(pos) >= 97 && src.codeUnitAt(pos) <= 122) ||
                src.codeUnitAt(pos) > 127)) {
          pos++;
        }
        if (pos == start) {
          throw FormatException('expected object key at $pos');
        }
        key = src.substring(start, pos);
      }
      _ws();
      if (pos >= src.length || src[pos] != ':') {
        throw FormatException('expected : after key at $pos');
      }
      pos++;
      out[key] = _value();
      _ws();
      if (pos >= src.length) throw FormatException('unterminated object');
      if (src[pos] == ',') {
        pos++;
        _ws();
        if (pos < src.length && src[pos] == '}') {
          pos++;
          return out;
        }
        continue;
      }
      if (src[pos] == '}') {
        pos++;
        return out;
      }
      throw FormatException('expected , or } at $pos');
    }
  }

  String _string() {
    final quote = src[pos];
    pos++;
    final buf = StringBuffer();
    while (pos < src.length) {
      final c = src[pos];
      if (c == '\\') {
        if (pos + 1 >= src.length) break;
        final e = src[pos + 1];
        switch (e) {
          case 'n':
            buf.write('\n');
            break;
          case 't':
            buf.write('\t');
            break;
          case 'r':
            buf.write('\r');
            break;
          case 'u':
            if (pos + 5 < src.length) {
              final hex = src.substring(pos + 2, pos + 6);
              final code = int.tryParse(hex, radix: 16);
              if (code != null) buf.writeCharCode(code);
              pos += 4;
            }
            break;
          default:
            buf.write(e);
        }
        pos += 2;
        continue;
      }
      if (c == quote) {
        pos++;
        return buf.toString();
      }
      buf.write(c);
      pos++;
    }
    throw FormatException('unterminated string at $pos');
  }

  num _number() {
    final start = pos;
    if (pos < src.length && src[pos] == '-') pos++;
    while (pos < src.length &&
        ((src.codeUnitAt(pos) >= 48 && src.codeUnitAt(pos) <= 57) ||
            src[pos] == '.' ||
            src[pos] == 'e' ||
            src[pos] == 'E' ||
            src[pos] == '+' ||
            src[pos] == '-')) {
      pos++;
    }
    final text = src.substring(start, pos);
    return int.tryParse(text) ?? double.parse(text);
  }
}
