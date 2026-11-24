import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'contract_test.dart' show LogAirlock, start, throughLogbook;

/// Writes nothing, and says it wrote.
final class _FileDriver implements ReadsAndWritesFiles {
  final written = <RelativePath>[];

  @override
  Future<Outcome<ReadResult>> read(RelativePath path) async =>
      const Ran(ReadMissing());

  @override
  Future<Outcome<BytesReadResult>> readBytes(RelativePath path) async =>
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
      final airlock = LogAirlock();
      final files = _FileDriver();
      final crux = throughLogbook(start(airlock, [files]), airlock, turn: 7);
      final path = RelativePath('notes.txt');
      var applied = 0;

      Result<String> result = Program.write
          .runOrFail(FileText(path, 'hi'), then: Done.new)
          .map((wrote) {
            applied++;
            return wrote.replaced ? 'replaced' : 'created';
          });

      expect(result, isA<Action<String>>());
      expect(applied, 0);
      expect(files.written, isEmpty);
      expect(airlock.log, isEmpty);

      while (result is Action<String>) {
        result = await result.next(crux);
      }

      expect(result, isA<Done<String>>());
      expect((result as Done<String>).value, 'created');
      expect(applied, 1);
      expect(files.written, [path]);
      expect(airlock.log, [
        '7: allow write notes.txt',
        '7: ran write notes.txt',
      ]);
    },
  );

  test('a failure maps to itself', () {
    const failed = Failed('no');
    expect(identical(failed.map((Never answer) => 'unused'), failed), isTrue);
  });
}
