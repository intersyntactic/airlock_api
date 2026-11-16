import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

/// Files in memory. Refuses to write under `.git/`, in its own words.
final class MemoryFiles implements FileDriver {
  final files = <String, String>{};

  @override
  Future<Outcome<ReadResult>> read(RelativePath path) async =>
      switch (files[path.value]) {
        null => const Ran(ReadMissing()),
        final text => Ran(ReadText(text)),
      };

  @override
  Future<Outcome<Wrote>> write(FileText file) async {
    if (file.path.value.startsWith('.git/')) {
      return Refused("${file.path} is git's own");
    }
    final replaced = files.containsKey(file.path.value);
    files[file.path.value] = file.text;
    return Ran(Wrote(replaced: replaced));
  }
}

/// Starts nothing, keeps what it was asked to start, and reports while it
/// runs.
final class RecordedPrograms implements ProgramDriver {
  final started = <List<String>>[];

  @override
  Future<Outcome<ExecResult>> start(
    ProgramName program,
    Args args, {
    required Report report,
  }) async {
    started.add([program.value, ...args.args]);
    report(const Printed(Channel.stdout, 'Formatted 1 file'));
    return const Ran(Exited(0, stdout: 'Formatted 1 file', stderr: ''));
  }
}

/// Sends nothing, keeps what it was asked to send, and says the destination
/// made `activity-1`.
final class RecordedWeb implements WebDriver {
  final sent = <Request>[];

  @override
  Future<Outcome<Sent>> send(Request request) async {
    sent.add(request);
    return const Ran(Sent(status: 201, created: 'activity-1'));
  }
}

String reachOf(Reach reach) => switch (reach) {
  Reads(:final path) => 'read $path',
  Writes(:final file) => 'write ${file.path}',
  Starts(:final program, :final args) => [
    program.value,
    ...args.args,
  ].join(' '),
  Sends(:final origin, :final signIn, :final renderer) =>
    'send to $origin as $signIn'
        '${renderer == null ? ' with no renderer' : ''}',
};

/// Rules: what a journey path may do, by name, and the sites it may send to
/// as `<origin> as <sign-in>`. Places are step numbers. Keeps a line per
/// entry, and can be told to fail writing one kind of entry.
///
/// Knows `teams-reply` only. Its journal holds the text of each entry a
/// test [remember]s, and its renderer draws a body by joining the texts of
/// the entries a send names, logging `render <n>` when the airlock follows
/// the journal to what it recorded.
final class LogAirlock implements Airlock<Set<String>, int> {
  LogAirlock({this.failOn});

  final Type? failOn;
  final log = <String>[];
  final _journal = <EntryId, String>{};

  /// Records [text], as the journal would, and gives its id.
  EntryId remember(String text) {
    final id = EntryId.of(utf8.encode(text));
    _journal[id] = text;
    return id;
  }

  @override
  Future<Renderer?> renderer(RendererName name) async =>
      name == teamsReply.name ? teamsReply.renderer : null;

  @override
  Future<Outcome<String>> rendered(Decided<int> decided) async {
    final Sends(:send) = decided.reach as Sends;
    log.add('render ${send.entries.length}');
    final texts = <String>[];
    for (final id in send.entries) {
      final text = _journal[id];
      if (text == null) return Refused('entry $id is not recorded');
      texts.add(text);
    }
    return Ran(texts.join(' '));
  }

  @override
  Future<Decision> decide(Reach reach, Set<String> rules) async =>
      rules.contains(switch (reach) {
        Reads() => 'read',
        Writes() => 'write',
        Starts(:final program) => program.value,
        Sends(:final origin, :final signIn) => '$origin as $signIn',
      })
      ? const Allow(by: DecidedBy.rules)
      : const Deny('not in the rules', by: DecidedBy.rules);

  @override
  Future<void> record(Entry<int> entry) async {
    if (entry.runtimeType == failOn) throw StateError('disk full');
    log.add(
      '${entry.place}: ${switch (entry) {
        Decided(:final reach, decision: Allow()) => 'allow ${reachOf(reach)}',
        Decided(:final reach, decision: Deny(:final why)) => 'deny ${reachOf(reach)}: $why',
        Returned(:final reach, outcome: Ran()) => 'ran ${reachOf(reach)}',
        Returned(:final reach, outcome: Refused(:final why)) => 'refused ${reachOf(reach)}: $why',
      }}',
    );
  }
}

/// A [LogAirlock] that keeps each [Decided] entry it follows the journal
/// from to a body.
final class _FollowingAirlock extends LogAirlock {
  final followedTo = <Decided<int>>[];

  @override
  Future<Outcome<String>> rendered(Decided<int> decided) {
    followedTo.add(decided);
    return super.rendered(decided);
  }
}

final dart = Executable.parse('dart')!;

/// Writes [path], then formats it: two runs, and what the second printed.
Result<String> writeAndFormat(String path) => Program.write.runOrRefusal(
  FileText(RelativePath(path), 'void main() {}'),
  then: (wrote) => dart.runOrRefusal(
    Args(['format', path]),
    then: (exec) => Done(exec.stdout),
  ),
);

/// [result] followed at [apex] to an answer, or why there is none.
Future<String> follow(Result<String> result, Apex apex) async {
  while (result is Run<String>) {
    result = await result.next(apex);
  }
  return switch (result) {
    Done(:final value) => value,
    Failed(:final why) => 'failed: $why',
    Run() => throw StateError('followed to an answer'),
  };
}

/// The id of a journey path started by the entry [startedBy], as the
/// docking port names it: by that entry's hash.
JourneyPathId idOf(String startedBy) =>
    JourneyPathId.of(utf8.encode(startedBy));

/// A journey path as the docking port starts one, with the airlock's side
/// of it set up in this process.
JourneyPath<Set<String>, int> start(
  LogAirlock airlock,
  List<Driver> drivers, {
  Set<String> rules = const {'read', 'write', 'dart'},
}) => JourneyPath(
  id: idOf('started root'),
  drivers: drivers,
  airlock: airlock,
  rules: rules,
  loopUser: loop1,
  journeyUser: journey1,
);

/// The users loop_launcher hands a path in these tests.
final loop1 = LoopUser.parse('loop-1')!;
final journey1 = JourneyUser.parse('journey-1')!;

final hart = SignIn.parse('hart-bot')!;
final teams = Origin.parse('https://smba.trafficmanager.net')!;

/// The one renderer [LogAirlock] knows, as a send names it and as the
/// airlock resolves it.
final teamsReply = (
  name: RendererName.parse('teams-reply')!,
  renderer: Renderer(
    RendererId.parse('1' * 64)!,
    executable: ObjectId.parse('2' * 64)!,
  ),
);

Result<String> send(
  Origin site,
  SignIn signIn, {
  List<EntryId> entries = const [],
  String renderer = 'teams-reply',
}) => Program.web.runOrRefusal(
  Send(
    site,
    path: WebPath.parse('/v3/conversations/c/activities')!,
    signIn: signIn,
    renderer: RendererName.parse(renderer)!,
    entries: entries,
  ),
  then: (sent) => Done('${sent.status} ${sent.created}'),
);

void main() {
  test('every entry is at the place its apex was given', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles(), RecordedPrograms()]);
    expect(
      await follow(writeAndFormat('a.dart'), path.at(1)),
      'Formatted 1 file',
    );
    expect(
      await follow(writeAndFormat('b.dart'), path.at(2)),
      'Formatted 1 file',
    );
    expect(airlock.log, [
      '1: allow write a.dart',
      '1: ran write a.dart',
      '1: allow dart format a.dart',
      '1: ran dart format a.dart',
      '2: allow write b.dart',
      '2: ran write b.dart',
      '2: allow dart format b.dart',
      '2: ran dart format b.dart',
    ]);
  });

  test(
    'a machine with no program driver writes, and cannot run dart',
    () async {
      final files = MemoryFiles();
      final airlock = LogAirlock();
      final answer = await follow(
        writeAndFormat('lib/a.dart'),
        start(airlock, [files]).at(1),
      );
      expect(files.files, {'lib/a.dart': 'void main() {}'});
      expect(answer, 'failed: this machine cannot run dart');
      expect(airlock.log, [
        '1: allow write lib/a.dart',
        '1: ran write lib/a.dart',
        '1: allow dart format lib/a.dart',
        '1: refused dart format lib/a.dart: this machine cannot run dart',
      ]);
    },
  );

  test('a denied run reaches no driver, is recorded, and fails', () async {
    final files = MemoryFiles();
    final airlock = LogAirlock();
    final answer = await follow(
      writeAndFormat('lib/a.dart'),
      start(airlock, [files], rules: {'read'}).at(1),
    );
    expect(files.files, isEmpty);
    expect(answer, 'failed: not in the rules');
    expect(airlock.log, [
      '1: deny write lib/a.dart: not in the rules',
      '1: refused write lib/a.dart: not in the rules',
    ]);
  });

  test('a driver refuses in its own words, and nothing after runs', () async {
    final programs = RecordedPrograms();
    final answer = await follow(
      writeAndFormat('.git/config'),
      start(LogAirlock(), [MemoryFiles(), programs]).at(1),
    );
    expect(answer, "failed: .git/config is git's own");
    expect(programs.started, isEmpty);
  });

  test('no driver is reached when the decision cannot be recorded', () async {
    final files = MemoryFiles();
    await expectLater(
      follow(
        writeAndFormat('lib/a.dart'),
        start(LogAirlock(failOn: Decided<int>), [files]).at(1),
      ),
      throwsStateError,
    );
    expect(files.files, isEmpty);
  });

  test('an outcome that cannot be recorded does not flow on', () async {
    final files = MemoryFiles();
    final programs = RecordedPrograms();
    await expectLater(
      follow(
        writeAndFormat('lib/a.dart'),
        start(LogAirlock(failOn: Returned<int>), [files, programs]).at(1),
      ),
      throwsStateError,
    );
    // The write reached the world; the record's Decided entry says so. The
    // continuation never saw it, so dart was never started.
    expect(files.files, {'lib/a.dart': 'void main() {}'});
    expect(programs.started, isEmpty);
  });

  test('stopping a journey path refuses what it has not yet run', () async {
    final files = MemoryFiles();
    final airlock = LogAirlock();
    final path = start(airlock, [files])..stop();
    expect(
      await follow(writeAndFormat('lib/a.dart'), path.at(2)),
      'failed: stopped',
    );
    expect(files.files, isEmpty);
    expect(airlock.log, [
      '2: deny write lib/a.dart: stopped',
      '2: refused write lib/a.dart: stopped',
    ]);
  });

  test('the record says who decided: the rules, or the person', () async {
    final decided = <String>[];
    final root = start(LogAirlock(), [MemoryFiles(), RecordedPrograms()]);
    root.entries.listen((e) {
      if (e case Decided(:final decision)) {
        decided.add('${decision.runtimeType} by ${decision.by.name}');
      }
    });
    await follow(writeAndFormat('a.dart'), root.at(1));
    root.stop();
    await follow(writeAndFormat('a.dart'), root.at(2));
    expect(decided, ['Allow by rules', 'Allow by rules', 'Deny by person']);
  });

  test('each entry reaches the journey path, naming it', () async {
    final path = start(LogAirlock(), [MemoryFiles()], rules: {'write'});
    final seen = <String>[];
    path.entries.listen(
      (e) => seen.add(
        '${e.journeyPathId == path.id} ${e.runtimeType} at ${e.place}',
      ),
    );
    await follow(
      Program.write.runOrRefusal(
        FileText(RelativePath('a'), ''),
        then: (_) => const Done('ok'),
      ),
      path.at(2),
    );
    expect(seen, ['true Decided<int> at 2', 'true Returned<int> at 2']);
  });

  test('what drivers report while running reaches the live view', () async {
    final path = start(LogAirlock(), [RecordedPrograms()], rules: {'dart'});
    final seen = <String>[];
    path.underway.listen(
      (u) => seen.add(
        'at ${u.place}: ${switch (u.progress) {
          Printed(:final channel, :final text) => '${channel.name}: $text',
        }}',
      ),
    );
    Result<String> format() =>
        dart.runOrRefusal(const Args(['format']), then: (e) => Done(e.stdout));
    await follow(format(), path.at(2));
    await follow(format(), path.at(3));
    expect(seen, [
      'at 2: stdout: Formatted 1 file',
      'at 3: stdout: Formatted 1 file',
    ]);
  });

  test('a read finds the file a write replaced', () async {
    final files = MemoryFiles()..files['notes.txt'] = 'old';
    final notes = RelativePath('notes.txt');
    final Result<String> result = Program.write.runOrRefusal(
      FileText(notes, 'new'),
      then: (wrote) => Program.read.run(
        notes,
        then: (read) => switch (read) {
          Ran(output: ReadText(:final text)) => Done(
            'replaced ${wrote.replaced}: $text',
          ),
          Ran(output: ReadMissing()) => const Failed('missing'),
          Refused(:final why) => Failed(why),
        },
      ),
    );
    expect(
      await follow(result, start(LogAirlock(), [files]).at(1)),
      'replaced true: new',
    );
  });

  test('a send is decided by its origin and sign-in together', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final path = start(airlock, [web], rules: {'$teams as $hart'});
    expect(await follow(send(teams, hart), path.at(1)), '201 activity-1');
    expect(
      await follow(send(teams, SignIn.parse('other-bot')!), path.at(2)),
      'failed: not in the rules',
    );
    expect(web.sent.map((r) => r.signIn), [hart]);
    expect(airlock.log, [
      '1: allow send to $teams as hart-bot',
      'render 0',
      '1: ran send to $teams as hart-bot',
      '2: deny send to $teams as other-bot: not in the rules',
      '2: refused send to $teams as other-bot: not in the rules',
    ]);
  });

  test('a send shows its sign-in, and null only when it has none', () async {
    final path = start(LogAirlock(), [RecordedWeb()]);
    final seen = <(Origin, SignIn?)>[];
    path.entries.listen((e) {
      if (e case Decided(reach: Sends(:final origin, :final signIn))) {
        seen.add((origin, signIn));
      }
    });
    for (final (i, signIn) in [hart, null].indexed) {
      await Program.web
          .run(
            Send(teams, signIn: signIn, renderer: teamsReply.name),
            then: (_) => const Done(''),
          )
          .next(path.at(i));
    }
    expect(seen, [(teams, hart), (teams, null)]);
  });

  test("a send's body is what its renderer recorded, from recorded entries, "
      'only once its decision is kept', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final turn = airlock.remember('the tests pass');
    final chunk = airlock.remember('and the build is green');
    final path = start(airlock, [web], rules: {'$teams as $hart'});
    expect(
      await follow(send(teams, hart, entries: [turn, chunk]), path.at(1)),
      '201 activity-1',
    );
    expect(web.sent.single.body, 'the tests pass and the build is green');
    expect(airlock.log, [
      '1: allow send to $teams as hart-bot',
      'render 2',
      '1: ran send to $teams as hart-bot',
    ]);
  });

  test('the decision records the exact renderer and the entries, and is '
      'what the airlock follows to the body', () async {
    final airlock = _FollowingAirlock();
    final turn = airlock.remember('done');
    final path = JourneyPath<Set<String>, int>(
      id: idOf('started root'),
      drivers: [RecordedWeb()],
      airlock: airlock,
      rules: {'$teams as $hart'},
      loopUser: loop1,
      journeyUser: journey1,
    );
    final decided = <Decided<int>>[];
    path.entries.listen((e) {
      if (e case final Decided<int> d) decided.add(d);
    });
    await follow(send(teams, hart, entries: [turn]), path.at(1));
    final Sends(:renderer, send: sent) = decided.single.reach as Sends;
    expect(renderer, same(teamsReply.renderer));
    expect(sent.renderer, teamsReply.name);
    expect(sent.entries, [turn]);
    expect(airlock.followedTo, [same(decided.single)]);
  });

  test('a renderer named nowhere is denied before the rules, and nothing '
      'is rendered or sent', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final answer = await follow(
      send(teams, hart, renderer: 'slack-reply'),
      start(airlock, [web], rules: {'$teams as $hart'}).at(1),
    );
    expect(answer, 'failed: no renderer named slack-reply');
    expect(web.sent, isEmpty);
    expect(airlock.log, [
      '1: deny send to $teams as hart-bot with no renderer: '
          'no renderer named slack-reply',
      '1: refused send to $teams as hart-bot with no renderer: '
          'no renderer named slack-reply',
    ]);
  });

  test('a denied send is never followed to a body', () async {
    final airlock = _FollowingAirlock();
    final answer = await follow(
      send(teams, hart),
      JourneyPath<Set<String>, int>(
        id: idOf('started root'),
        drivers: [RecordedWeb()],
        airlock: airlock,
        rules: const {},
        loopUser: loop1,
        journeyUser: journey1,
      ).at(1),
    );
    expect(answer, 'failed: not in the rules');
    expect(airlock.followedTo, isEmpty);
  });

  test('an entry the journal does not hold refuses the send', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final unrecorded = EntryId.of(utf8.encode('never written'));
    final answer = await follow(
      send(teams, hart, entries: [unrecorded]),
      start(airlock, [web], rules: {'$teams as $hart'}).at(1),
    );
    expect(answer, 'failed: entry $unrecorded is not recorded');
    expect(web.sent, isEmpty);
    expect(
      airlock.log.last,
      '1: refused send to $teams as hart-bot: '
      'entry $unrecorded is not recorded',
    );
  });

  test('nothing is rendered when the decision cannot be recorded', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock(failOn: Decided<int>);
    await expectLater(
      follow(
        send(teams, hart),
        start(airlock, [web], rules: {'$teams as $hart'}).at(1),
      ),
      throwsStateError,
    );
    expect(airlock.log, isEmpty);
    expect(web.sent, isEmpty);
  });

  test('a send cannot hold a credential, or a path to another site', () {
    expect(
      () => Send(
        teams,
        renderer: teamsReply.name,
        headers: {'Authorization': 'Bearer x'},
      ),
      throwsArgumentError,
    );
    expect(
      ['//evil.example', '/a/../b', '/@evil.example', 'v3'].map(WebPath.parse),
      everyElement(isNull),
    );
  });

  test('renderer names are checked once, at the boundary', () {
    expect(
      [
        '',
        'Teams',
        'teams reply',
        '-teams',
        '1teams',
        'teams_reply',
      ].map(RendererName.parse),
      everyElement(isNull),
    );
    expect(RendererName.parse('teams-reply'), teamsReply.name);
  });

  test('a machine with no web driver cannot send', () async {
    expect(
      await follow(
        send(teams, hart),
        start(LogAirlock(), [MemoryFiles()], rules: {'$teams as $hart'}).at(1),
      ),
      'failed: this machine cannot run web',
    );
  });

  test('names are checked once, at the boundary', () {
    expect(
      ['', ' ', 'git status', 'git\tlog'].map(Executable.parse),
      everyElement(isNull),
    );
    expect(Executable.parse('git'), Executable.parse('git'));
    expect(Executable.parse('git'), isNot(Executable.parse('dart')));
  });
}
