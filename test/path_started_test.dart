import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'proposal_test.dart' show ServiceLink;
import 'contract_test.dart' show LogAirlock, MemoryFiles, follow;

/// The airlock service, in memory: its side of each journey path it is
/// told has started ([told]), with the path's rules read as a list of
/// names. Its [link] takes the loops' proposals to them.
final class AirlockService {
  AirlockService(this.airlock, this.files);

  final LogAirlock airlock;
  final MemoryFiles files;
  final link = ServiceLink([]);

  /// The answer to [message], a [PathStarted] from loop_launcher,
  /// through JSON text both ways.
  Object? told(Object? message) {
    final PathStartedAnswer answer = switch (PathStarted.read(_wire(message))) {
      final Rejected rejected => rejected,
      PathStarted(
        :final journeyPath,
        :final rules,
        :final loopUser,
        :final journeyUser,
        :final stopped,
      ) =>
        switch (rules) {
          final List<Object?> names when names.every((n) => n is String) => () {
            final path = link.paths[journeyPath];
            if (path != null) {
              path.reissue(loopUser: loopUser);
            }
            final side =
                path ??
                (link.paths[journeyPath] = JourneyPath(
                  id: journeyPath,
                  drivers: [files],
                  airlock: airlock,
                  rules: {...names.cast<String>()},
                  loopUser: loopUser,
                  journeyUser: journeyUser,
                ));
            if (stopped) side.stop();
            return Ready.of(side);
          }(),
          _ => const Rejected('rules: not a list of names'),
        },
    };
    return _wire(answer.json);
  }

  Object? _wire(Object? json) => jsonDecode(jsonEncode(json));
}

/// What loop_launcher does when the docking station has started a journey
/// path: tells the airlock service, and launches the loop with an apex
/// built from the token it is answered with.
Apex loopLauncherLaunches(
  AirlockService service,
  JourneyPathId id, {
  List<String> rules = const ['write'],
  String loopUser = 'loop-1',
  bool stopped = false,
}) => switch (PathStartedAnswer.read(
  service.told(
    PathStarted(
      id,
      rules: rules,
      loopUser: LoopUser.parse(loopUser)!,
      journeyUser: JourneyUser.parse('journey-1')!,
      stopped: stopped,
    ).toJson(),
  ),
)) {
  Ready(:final token) => Apex.through(
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
  test("a path's loop proposes runs with the token the airlock service "
      'answered loop_launcher with', () async {
    final service = AirlockService(LogAirlock(), MemoryFiles());
    final apex = loopLauncherLaunches(service, thread);
    expect(await follow(write('a'), apex), 'wrote');
    expect(service.files.files.keys, ['a']);
  });

  test('told again of a path whose side is set up, the airlock service gives '
      'a new token, and the old one is rejected from then on', () async {
    final service = AirlockService(LogAirlock(), MemoryFiles());
    final before = loopLauncherLaunches(service, thread);
    final after = loopLauncherLaunches(service, thread);
    expect(
      await follow(write('a'), before),
      contains("not this journey path's token"),
    );
    expect(await follow(write('b'), after), 'wrote');
    expect(service.files.files.keys, ['b']);
  });

  test('a loop launched again may run as another user, and the old one is '
      'rejected even with the new token', () async {
    final service = AirlockService(LogAirlock(), MemoryFiles());
    loopLauncherLaunches(service, thread);
    final again = loopLauncherLaunches(service, thread, loopUser: 'loop-2');
    final path = service.link.paths[thread]!;
    expect(path.loopUser, LoopUser.parse('loop-2'));
    expect(path.journeyUser, JourneyUser.parse('journey-1'));
    expect(await follow(write('a'), again), 'wrote');
    final oldUser = Apex.through(
      ServiceLink([path], peer: LoopUser.parse('loop-1')),
      journeyPath: thread,
      token: path.token,
      place: 1,
    );
    expect(
      await follow(write('b'), oldUser),
      contains("not this journey path's loop user: loop-1"),
    );
    expect(service.files.files.keys, ['a']);
  });

  test('after the airlock service restarts, being told again sets up the '
      'same path with a new token', () async {
    final files = MemoryFiles();
    final first = AirlockService(LogAirlock(), files);
    loopLauncherLaunches(first, thread);
    final oldToken = first.link.paths[thread]!.token;
    final restarted = AirlockService(LogAirlock(), files);
    final again = loopLauncherLaunches(restarted, thread);
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
    'a stop survives a restart, and being told again never un-stops a path',
    () async {
      final service = AirlockService(LogAirlock(), MemoryFiles());
      final stopped = loopLauncherLaunches(service, thread, stopped: true);
      expect(await follow(write('a'), stopped), 'failed: stopped');
      final unstopped = loopLauncherLaunches(service, thread);
      expect(await follow(write('b'), unstopped), 'failed: stopped');
      expect(service.files.files, isEmpty);
    },
  );

  test('what is not a path started is rejected, and loop_launcher reads '
      'why', () {
    final service = AirlockService(LogAirlock(), MemoryFiles());
    final good = {
      'pathStarted': thread.hex,
      'rules': ['write'],
      'loopUser': 'loop-1',
      'journeyUser': 'journey-1',
      'stopped': false,
    };
    for (final (message, why) in [
      (null, 'not a path started'),
      ({'pathStarted': thread.hex}, 'not a path started'),
      ({...good}..remove('loopUser'), 'not a path started'),
      ({...good, 'pathStarted': 'nope'}, 'not a journey path: nope'),
      ({...good, 'loopUser': 'journey-1'}, 'not a loop user: journey-1'),
      ({...good, 'loopUser': 'loop-0'}, 'not a loop user: loop-0'),
      ({...good, 'journeyUser': 'root'}, 'not a journey user: root'),
      ({...good, 'rules': 'write'}, 'rules: not a list of names'),
    ]) {
      expect(switch (PathStartedAnswer.read(service.told(message))) {
        Rejected(:final why) => why,
        Ready() => 'ready',
      }, why);
    }
    expect(service.link.paths, isEmpty);
    expect(
      () => PathStartedAnswer.read({'kind': 'maybe'}),
      throwsFormatException,
    );
    expect(
      () => PathStartedAnswer.read({'kind': 'ready', 'token': 'short'}),
      throwsFormatException,
    );
  });
}
