import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:observatory/src/domain/policies/redaction_policy.dart';

/// Prepares detached, bounded values for local logs and remote events.
final class LogSanitizer {
  static const maxDepth = 8;
  static const maxElements = 1000;
  static const maxLength = 16384;
  static const redacted = '<redacted>';
  static const truncated = '<truncated>';
  final RedactionPolicy policy;

  const LogSanitizer(this.policy);

  String clip(String value) =>
      value.length <= maxLength ? value : '${value.substring(0, maxLength - truncated.length)}$truncated';

  String boundedMessage(String message, {required int prefixLength}) {
    final result = StringBuffer();
    var renderedLength = 0;
    final lines = message.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final separatorLength = index == 0 ? 0 : 1;
      final available = maxLength - renderedLength - separatorLength - prefixLength - truncated.length;
      if (available < 0) {
        result.write(truncated);
        break;
      }
      if (index > 0) result.write('\n');
      final line = lines[index];
      if (line.length > available) {
        result.write('${line.substring(0, available)}$truncated');
        break;
      }
      result.write(line);
      renderedLength += separatorLength + prefixLength + line.length;
    }
    return result.toString();
  }

  String text(String value) {
    var result = clip(value);
    if (!policy.enabled) return result;
    if (value.trimLeft().startsWith('{') || value.trimLeft().startsWith('[')) {
      if (value.length > maxLength) return '<truncated JSON>';
      try {
        return encode(jsonDecode(value));
      } on FormatException {
        // Non-JSON messages continue through recognizable text scrubbing.
      }
    }
    result = result.replaceAllMapped(RegExp(r'''https?://[^\s<>"']+'''), (match) {
      try {
        final parsed = Uri.tryParse(match[0]!);
        return parsed == null ? '<invalid-uri>' : uri(parsed).toString();
      } on FormatException {
        return '<invalid-uri>';
      }
    });
    // Recognizable key/value text is scrubbed; arbitrary secrets cannot be inferred.
    result = result.replaceAllMapped(
      RegExp(
        r'''(^|[&?\s,{"'])([A-Za-z_][A-Za-z0-9_-]{0,127})(["']?[ \t]*[:=][ \t]*)("[^"\n]*"|'[^'\n]*'|Bearer[ \t]+[^\s,;]+|[^\s,;&}\]]+)''',
        caseSensitive: false,
      ),
      (match) => policy.isSensitiveHeader(match[2]!) || policy.isSensitiveBodyKey(match[2]!)
          ? '${match[1]}${match[2]}${match[3]}$redacted'
          : match[0]!,
    );
    return clip(result);
  }

  Uri uri(Uri value) {
    if (!policy.enabled) return value;
    return value.replace(
      userInfo: value.userInfo.isEmpty ? '' : redacted,
      queryParameters: value.hasQuery
          ? value.queryParametersAll.map(
              (key, values) => MapEntry(
                key,
                policy.isSensitiveBodyKey(key) || policy.isSensitiveHeader(key) ? [redacted] : values,
              ),
            )
          : null,
    );
  }

  Object? value(Object? source) {
    final active = HashSet<Object>.identity();
    var remaining = maxElements;
    Object? visit(Object? item, int depth, [String? key]) {
      if (key != null && (policy.isSensitiveBodyKey(key) || policy.isSensitiveHeader(key))) return redacted;
      if (remaining-- <= 0 || depth > maxDepth) return truncated;
      if (item == null || item is bool || item is num) return item;
      if (item is String) {
        if (policy.enabled &&
            item.length <= maxLength &&
            (item.trimLeft().startsWith('{') || item.trimLeft().startsWith('['))) {
          try {
            return clip(jsonEncode(visit(jsonDecode(item), depth + 1)));
          } on FormatException {
            // Not JSON; retain the bounded text representation.
          }
        }
        return text(item);
      }
      if (item is Uri) return clip(uri(item).toString());
      if (item is DateTime) return item.toUtc().toIso8601String();
      if (item is Uint8List) return '<bytes length=${item.length}>';
      if (!active.add(item)) return '<cycle>';
      try {
        if (item is MultipartFile) {
          return visit({
            'filename': item.filename,
            'contentType': item.contentType?.toString(),
            'bytes': item.length,
          }, depth + 1);
        }
        if (item is FormData) {
          final result = <String, Object?>{};
          for (final entry in <Iterable<MapEntry<String, Object>>>[
            item.fields,
            item.files,
          ].expand((entries) => entries)) {
            if (remaining <= 0) {
              result[truncated] = truncated;
              break;
            }
            final prepared = visit(entry.value, depth + 1, entry.key);
            final previous = result[entry.key];
            result[entry.key] = result.containsKey(entry.key) ? [previous, prepared] : prepared;
          }
          return result;
        }
        if (item is Map) {
          final result = <String, Object?>{};
          for (final entry in item.entries) {
            if (remaining <= 0) {
              result[truncated] = truncated;
              break;
            }
            final name = clip(entry.key.toString());
            result[name] = visit(entry.value, depth + 1, name);
          }
          return result;
        }
        if (item is Iterable<Object?>) {
          final result = <Object?>[];
          for (final entry in item) {
            if (remaining <= 0) {
              result.add(truncated);
              break;
            }
            result.add(visit(entry, depth + 1));
          }
          return result;
        }
        return policy.enabled ? '<object>' : text(item.toString());
      } finally {
        active.remove(item);
      }
    }

    try {
      return visit(source, 0);
    } on Object {
      return '<unavailable>';
    }
  }

  String encode(Object? source) {
    try {
      return clip(const JsonEncoder.withIndent('  ').convert(value(source)));
    } on Object {
      return '<unavailable>';
    }
  }
}
