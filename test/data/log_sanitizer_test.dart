import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observatory/observatory.dart';
import 'package:observatory/src/feature/_common/infrastructure/log_sanitizer.dart';

void main() {
  const sanitizer = LogSanitizer(RedactionPolicy());
  test('sanitizes nested maps, JSON, FormData, repeated fields and URI without mutation', () {
    final original = {
      'Authorization': 'header-secret',
      'nested': [
        {'private_key': 'private-secret'},
      ],
      'label': 'public',
    };
    final json = sanitizer.encode(original);
    expect(json, contains('public'));
    expect(json, isNot(contains('header-secret')));
    expect(json, isNot(contains('private-secret')));
    expect(original['Authorization'], 'header-secret');
    expect(sanitizer.encode('{"token":"json-secret"}'), isNot(contains('json-secret')));
    final form = FormData()
      ..fields.addAll([
        const MapEntry('token', 'form-secret'),
        const MapEntry('name', 'a'),
        const MapEntry('name', 'b'),
      ])
      ..files.add(MapEntry('file', MultipartFile.fromBytes([1, 2], filename: 'file.txt')));
    final prepared = sanitizer.encode(form);
    expect(prepared, isNot(contains('form-secret')));
    expect(prepared, contains('file.txt'));
    expect(prepared, contains('"a"'));
    expect(prepared, contains('"b"'));
    final uri = Uri.parse('https://username:password@example.com/path?token=uri-secret&name=a&name=b');
    final clean = sanitizer.uri(uri);
    expect(Uri.decodeComponent(clean.userInfo), '<redacted>');
    expect(clean.queryParametersAll['name'], ['a', 'b']);
    expect(clean.toString(), isNot(contains('uri-secret')));
    expect(uri.userInfo, 'username:password');
    expect(sanitizer.encode(Uint8List(20)), contains('<bytes length=20>'));
  });
  test('bounds cyclic structures, depth, element count and output length', () {
    final cycle = <Object?>[];
    cycle.add(cycle);
    expect(sanitizer.encode(cycle), contains('<cycle>'));
    Object deep = 'leaf';
    for (var i = 0; i < 20; i++) {
      deep = [deep];
    }
    expect(sanitizer.encode(deep), contains('<truncated>'));
    expect(sanitizer.encode(List.filled(2000, 1)), contains('<truncated>'));
    expect(sanitizer.encode('x' * 30000).length, lessThanOrEqualTo(LogSanitizer.maxLength));
    expect(sanitizer.encode(_BadValue()), isNot(contains('secret')));
    const disabled = LogSanitizer(RedactionPolicy.disabled());
    expect(disabled.encode({'token': 'visible'}), contains('visible'));
    expect(disabled.encode(cycle), contains('<cycle>'));
  });
}

final class _BadValue {
  @override
  String toString() => throw StateError('secret');
}
