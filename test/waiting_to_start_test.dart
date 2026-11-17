import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:test/test.dart';

void main() {
  final path = TrajectoryId.of(utf8.encode('started root'));

  test('a waiting-to-start entry reads back as it was written', () {
    final back = WaitingToStart.fromJson(
      jsonDecode(jsonEncode(WaitingToStart(path).toJson())),
    );
    expect(back.trajectory, path);
    expect(WaitingToStart.kind, 'waiting-to-start');
  });

  test('a waiting-to-start entry is read strictly', () {
    for (final json in [
      null,
      'waiting-to-start',
      <String, Object?>{},
      {'trajectory': 'nope'},
      {'trajectory': 7},
      {'trajectory': path.hex, 'why': 'headroom'},
    ]) {
      expect(
        () => WaitingToStart.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
