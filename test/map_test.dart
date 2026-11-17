import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

/// Allows everything, and keeps what it is asked to record, in order.
final class _KeepingAirlock implements DecidesAndRecordsActions<String, int> {
  final kept = <(String, int)>[];

  @override
  Future<Decision> decide(Reach reach, String rules) async =>
      const Allow(by: DecidedBy.rules);

  @override
  Future<void> recordDecision(AirlockDecisionOnAction<int> decision) async =>
      kept.add(('decision', decision.place));

  @override
  Future<void> recordResult(
    AirlockDecisionOnAction<int> decision,
    Outcome<Object?> result, {
    required Object? resultAsJson,
  }) async => kept.add(('result', decision.place));

  @override
  Future<Outcome<String>> recordedOn(
    TrajectoryId trajectory,
    EntryId entry,
  ) async => const Refused('nothing recorded');
}

/// Writes nothing, and says it wrote.
final class _FileDriver implements ReadsAndWritesFiles {
  final written = <RelativePath>[];

  @override
  Future<Outcome<ReadResult>> read(RelativePath path) async =>
      const Ran(ReadMissing());

  @override
  Future<Outcome<Wrote>> write(FileText file) async {
    written.add(file.path);
    return const Ran(Wrote(replaced: false));
  }
}

void main() {
  test(
    'map runs nothing, and applies its function once the action answers',
    () async {
      final airlock = _KeepingAirlock();
      final files = _FileDriver();
      final crux = Trajectory<String, int>(
        id: TrajectoryId.of(utf8.encode('started a')),
        drivers: [files],
        airlock: airlock,
        rules: 'all',
        suit: Suit.parse('suit-1')!,
      ).at(7);
      final path = RelativePath('notes.txt');
      var applied = 0;

      Result<String> result = Program.write
          .runOrRefusal(FileText(path, 'hi'), then: Done.new)
          .map((wrote) {
            applied++;
            return wrote.replaced ? 'replaced' : 'created';
          });

      expect(result, isA<Action<String>>());
      expect(applied, 0);
      expect(files.written, isEmpty);
      expect(airlock.kept, isEmpty);

      while (result is Action<String>) {
        result = await result.next(crux);
      }

      expect(result, isA<Done<String>>());
      expect((result as Done<String>).value, 'created');
      expect(applied, 1);
      expect(files.written, [path]);
      expect(airlock.kept, [('decision', 7), ('result', 7)]);
    },
  );

  test('a failure maps to itself', () {
    const failed = Failed('no');
    expect(identical(failed.map((Never answer) => 'unused'), failed), isTrue);
  });
}
