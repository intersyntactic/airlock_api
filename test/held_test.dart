import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:test/test.dart';

void main() {
  final path = JourneyPathId.of(utf8.encode('started root'));

  test('a held entry reads back as it was written', () {
    final back = Held.fromJson(jsonDecode(jsonEncode(Held(path).toJson())));
    expect(back.journeyPath, path);
  });

  test('a held entry is read strictly', () {
    for (final json in [
      null,
      'held',
      <String, Object?>{},
      {'journeyPath': 'nope'},
      {'journeyPath': 7},
      {'journeyPath': path.hex, 'why': 'headroom'},
    ]) {
      expect(() => Held.fromJson(json), throwsFormatException, reason: '$json');
    }
  });
}
