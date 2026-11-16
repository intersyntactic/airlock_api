import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'proposal_test.dart' show ServiceLink;
import 'contract_test.dart' show LogAirlock, MemoryFiles, follow;

/// The airlock service, in memory: the journey paths it holds, started by
/// [start] as the service would on a [StartPath], with its rules read as a
/// list of names. Its [link] takes the loops' proposals to them.
final class AirlockService {
  AirlockService(this.airlock, this.files);

  final LogAirlock airlock;
  final MemoryFiles files;
  final link = ServiceLink([]);

  /// The answer to [request], through JSON text both ways.
  Object? start(Object? request) {
    final StartAnswer answer = switch (StartPath.read(_wire(request))) {
      final Rejected rejected => rejected,
      StartPath(:final journeyPath, :final rules, :final stopped) =>
        switch (rules) {
          final List<Object?> names when names.every((n) => n is String) => () {
            final path = link.paths[journeyPath];
            if (path != null) {
              path.reissue();
            }
            final live =
                path ??
                (link.paths[journeyPath] = JourneyPath.start(
                  id: journeyPath,
                  drivers: [files],
                  airlock: airlock,
                  rules: {...names.cast<String>()},
                ));
            if (stopped) live.stop();
            return Started.of(live);
          }(),
          _ => const Rejected('rules: not a list of names'),
        },
    };
    return _wire(answer.json);
  }

  Object? _wire(Object? json) => jsonDecode(jsonEncode(json));
}

/// What the service that starts journey paths does: sends a start, and
/// builds the loop's apex from the token it is answered with.
Apex startLoop(
  AirlockService service,
  JourneyPathId id, {
  List<String> rules = const ['write'],
  bool stopped = false,
}) => switch (StartAnswer.read(
  service.start(StartPath(id, rules: rules, stopped: stopped).toJson()),
)) {
  Started(:final token) => Apex.through(
    service.link,
    journeyPath: id,
    token: token,
    place: 1,
  ),
  Rejected(:final why) => throw StateError(why),
};

final thread = JourneyPathId.of(utf8.encode('started thread'));

Result<String> write(String path) => Program.write.runOrRefusal(
  FileText(RelativePath(path), ''),
  then: (_) => const Done('wrote'),
);

void main() {
  test("a started path's loop proposes runs with the token it was "
      'answered with', () async {
    final service = AirlockService(LogAirlock(), MemoryFiles());
    final apex = startLoop(service, thread);
    expect(await follow(write('a'), apex), 'wrote');
    expect(service.files.files.keys, ['a']);
  });

  test('a start for a live path gives a new token, and the old one is '
      'rejected from then on', () async {
    final service = AirlockService(LogAirlock(), MemoryFiles());
    final before = startLoop(service, thread);
    final after = startLoop(service, thread);
    expect(
      await follow(write('a'), before),
      contains("not this journey path's token"),
    );
    expect(await follow(write('b'), after), 'wrote');
    expect(service.files.files.keys, ['b']);
  });

  test('after the airlock service restarts, a start brings back the same '
      'path with a new token', () async {
    final files = MemoryFiles();
    final first = AirlockService(LogAirlock(), files);
    startLoop(first, thread);
    final oldToken = first.link.paths[thread]!.token;
    final restarted = AirlockService(LogAirlock(), files);
    final again = startLoop(restarted, thread);
    expect(restarted.link.paths.keys, [thread]);
    expect(await follow(write('a'), again), 'wrote');
    // A loop still holding the token from before the restart reaches the
    // restarted path, which never issued it.
    final stale = Apex.through(
      restarted.link,
      journeyPath: thread,
      token: oldToken,
      place: 1,
    );
    expect(
      await follow(write('b'), stale),
      contains("not this journey path's token"),
    );
    expect(files.files.keys, ['a']);
  });

  test(
    'a stop survives a restart, and a start never un-stops a path',
    () async {
      final service = AirlockService(LogAirlock(), MemoryFiles());
      final stopped = startLoop(service, thread, stopped: true);
      expect(await follow(write('a'), stopped), 'failed: stopped');
      final unstopped = startLoop(service, thread);
      expect(await follow(write('b'), unstopped), 'failed: stopped');
      expect(service.files.files, isEmpty);
    },
  );

  test('what is not a start is rejected, and the starter reads why', () {
    final service = AirlockService(LogAirlock(), MemoryFiles());
    for (final (request, why) in [
      (null, 'not a start'),
      ({'start': thread.hex}, 'not a start'),
      ({'start': 'nope', 'stopped': false}, 'not a journey path: nope'),
      (
        {'start': thread.hex, 'rules': 'write', 'stopped': false},
        'rules: not a list of names',
      ),
    ]) {
      expect(switch (StartAnswer.read(service.start(request))) {
        Rejected(:final why) => why,
        Started() => 'started',
      }, why);
    }
    expect(service.link.paths, isEmpty);
    expect(() => StartAnswer.read({'kind': 'maybe'}), throwsFormatException);
    expect(
      () => StartAnswer.read({'kind': 'started', 'token': 'short'}),
      throwsFormatException,
    );
  });
}
