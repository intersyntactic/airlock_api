import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

/// Allows everything, and keeps each entry it is asked to record.
final class _KeepingAirlock implements DecidesAndRecordsActions<String, int> {
  final kept = <Entry<int>>[];

  @override
  Future<Decision> decide(Reach reach, String rules) async =>
      const Allow(by: DecidedBy.rules);

  @override
  Future<void> record(Entry<int> entry) async => kept.add(entry);

  @override
  Future<Renderer?> renderer(RendererName name) async => null;

  @override
  Future<Outcome<String>> rendered(Decided<int> decided) async =>
      const Refused('no renderer');

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
      expect(airlock.kept.map((e) => (e.runtimeType, e.place)), [
        (Decided<int>, 7),
        (Returned<int>, 7),
      ]);
    },
  );

  test('a failure maps to itself', () {
    const failed = Failed('no');
    expect(identical(failed.map((Never answer) => 'unused'), failed), isTrue);
  });
}
