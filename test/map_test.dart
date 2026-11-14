import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

/// Allows everything, and keeps each entry it is asked to record.
final class _KeepingAirlock implements Airlock<String, int> {
  final kept = <Entry<String, int>>[];

  @override
  Future<Decision> decide(Run<Object?> run, String rules) async =>
      const Allow(by: DecidedBy.rules);

  @override
  bool narrows(String fewer, String rules) => true;

  @override
  Future<void> record(Entry<String, int> entry) async => kept.add(entry);
}

/// Writes nothing, and says it wrote.
final class _FileDriver implements FileDriver {
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
    'map runs nothing, and applies its function once the run answers',
    () async {
      final airlock = _KeepingAirlock();
      final files = _FileDriver();
      final apex = JourneyPath<String, int>.start(
        id: JourneyPathId.parse('a')!,
        drivers: [files],
        airlock: airlock,
        rules: 'all',
      ).at(7);
      final path = RelativePath('notes.txt');
      var applied = 0;

      Result<String> result = Program.write
          .runOrRefusal(FileText(path, 'hi'), then: Done.new)
          .map((wrote) {
            applied++;
            return wrote.replaced ? 'replaced' : 'created';
          });

      expect(result, isA<Run<String>>());
      expect(applied, 0);
      expect(files.written, isEmpty);
      expect(airlock.kept, isEmpty);

      while (result is Run<String>) {
        result = await result.next(apex);
      }

      expect(result, isA<Done<String>>());
      expect((result as Done<String>).value, 'created');
      expect(applied, 1);
      expect(files.written, [path]);
      expect(airlock.kept.map((e) => (e.runtimeType, e.place)), [
        (Decided<String, int>, 7),
        (Returned<String, int>, 7),
      ]);
    },
  );

  test('a failure maps to itself', () {
    const failed = Failed('no');
    expect(identical(failed.map((Never answer) => 'unused'), failed), isTrue);
  });
}
