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

String reachOf(Run<Object?> run) => switch (run.reach) {
  Reads(:final path) => 'read $path',
  Writes(:final file) => 'write ${file.path}',
  Starts(:final program, :final args) => [
    program.value,
    ...args.args,
  ].join(' '),
  Sends(:final origin, :final signIn) => 'send to $origin as $signIn',
};

/// Rules: what a journey path may do, by name, and the sites it may send to
/// as `<origin> as <sign-in>`. Places are step numbers. Keeps a line per
/// entry, and can be told to fail writing one kind of entry.
final class LogAirlock implements Airlock<Set<String>, int> {
  LogAirlock({this.failOn});

  final Type? failOn;
  final log = <String>[];

  @override
  Future<Decision> decide(Run<Object?> run, Set<String> rules) async =>
      rules.contains(switch (run.reach) {
        Reads() => 'read',
        Writes() => 'write',
        Starts(:final program) => program.value,
        Sends(:final origin, :final signIn) => '$origin as $signIn',
      })
      ? const Allow(by: DecidedBy.rules)
      : const Deny('not in the rules', by: DecidedBy.rules);

  @override
  bool narrows(Set<String> fewer, Set<String> rules) =>
      rules.containsAll(fewer);

  @override
  Future<void> record(Entry<Set<String>, int> entry) async {
    if (entry.runtimeType == failOn) throw StateError('disk full');
    log.add(
      '${entry.place}: ${switch (entry) {
        Decided(:final run, decision: Allow()) => 'allow ${reachOf(run)}',
        Decided(:final run, decision: Deny(:final why)) => 'deny ${reachOf(run)}: $why',
        Returned(:final run, outcome: Ran()) => 'ran ${reachOf(run)}',
        Returned(:final run, outcome: Refused(:final why)) => 'refused ${reachOf(run)}: $why',
        Narrowed(:final journeyPathId, :final child, :final rules, :final granted) => '${granted ? 'narrowed' : 'refused to widen'} $journeyPathId to $child '
            '${rules.toList()..sort()}',
      }}',
    );
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

JourneyPath<Set<String>, int> start(
  LogAirlock airlock,
  List<Driver> drivers, {
  Set<String> rules = const {'read', 'write', 'dart'},
}) => JourneyPath.start(
  id: JourneyPathId.parse('root')!,
  drivers: drivers,
  airlock: airlock,
  rules: rules,
);

final hart = SignIn.parse('hart-bot')!;
final teams = Origin.parse('https://smba.trafficmanager.net')!;

Result<String> post(Origin site, SignIn signIn) => Program.web.runOrRefusal(
  Request(
    site,
    method: Method.post,
    path: '/v3/conversations/c/activities',
    signIn: signIn,
    body: '{"text":"done"}',
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
        start(LogAirlock(failOn: Decided<Set<String>, int>), [files]).at(1),
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
        start(LogAirlock(failOn: Returned<Set<String>, int>), [
          files,
          programs,
        ]).at(1),
      ),
      throwsStateError,
    );
    // The write reached the world; the record's Decided entry says so. The
    // continuation never saw it, so dart was never started.
    expect(files.files, {'lib/a.dart': 'void main() {}'});
    expect(programs.started, isEmpty);
  });

  test('a journey path narrows, never widens, and both are recorded', () async {
    final airlock = LogAirlock();
    final root = start(airlock, [MemoryFiles()], rules: {'read', 'write'});
    final reader = await root.narrowed(
      {'read'},
      id: JourneyPathId.parse('reader')!,
      at: 1,
    );
    expect(reader?.rules, {'read'});
    expect(
      await root.narrowed(
        {'read', 'write', 'dart'},
        id: JourneyPathId.parse('wide')!,
        at: 2,
      ),
      isNull,
    );
    expect(
      await reader!.narrowed(
        {'write'},
        id: JourneyPathId.parse('writer')!,
        at: 3,
      ),
      isNull,
    );
    expect(airlock.log, [
      '1: narrowed root to reader [read]',
      '2: refused to widen root to wide [dart, read, write]',
      '3: refused to widen reader to writer [write]',
    ]);
  });

  test('an id names one journey path, and a blank one names none', () async {
    expect(JourneyPathId.parse(''), isNull);
    expect(JourneyPathId.parse('  '), isNull);
    final root = start(LogAirlock(), [MemoryFiles()]);
    final a = JourneyPathId.parse('a')!;
    expect(await root.narrowed({'read'}, id: a, at: 1), isNotNull);
    // Again from the root, from a child, after a refusal, and the root's own.
    await expectLater(
      root.narrowed({'read'}, id: a, at: 1),
      throwsArgumentError,
    );
    final b = (await root.narrowed(
      {'write'},
      id: JourneyPathId.parse('b')!,
      at: 1,
    ))!;
    await expectLater(b.narrowed({'write'}, id: a, at: 1), throwsArgumentError);
    final wide = JourneyPathId.parse('wide')!;
    expect(await b.narrowed({'read'}, id: wide, at: 1), isNull);
    await expectLater(
      b.narrowed({'write'}, id: wide, at: 1),
      throwsArgumentError,
    );
    await expectLater(
      b.narrowed({'write'}, id: JourneyPathId.parse('root')!, at: 1),
      throwsArgumentError,
    );
  });

  test('a narrowing that cannot be recorded makes no journey path', () async {
    final root = start(LogAirlock(failOn: Narrowed<Set<String>, int>), [
      MemoryFiles(),
    ]);
    await expectLater(
      root.narrowed({'read'}, id: JourneyPathId.parse('child')!, at: 1),
      throwsStateError,
    );
  });

  test('stopping a journey path stops those narrowed from it', () async {
    final files = MemoryFiles();
    final airlock = LogAirlock();
    final root = start(airlock, [files]);
    final child = (await root.narrowed(
      {'write'},
      id: JourneyPathId.parse('child')!,
      at: 1,
    ))!;
    airlock.log.clear();
    root.stop();
    expect(
      await follow(writeAndFormat('lib/a.dart'), child.at(2)),
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

  test(
    'entries reach the journey path they came from and its parents',
    () async {
      final root = start(LogAirlock(), [MemoryFiles()], rules: {'write'});
      final seenAtRoot = <String>[];
      final seenAtChild = <String>[];
      root.entries.listen(
        (e) => seenAtRoot.add('${e.journeyPathId} ${e.runtimeType}'),
      );
      final child = (await root.narrowed(
        {'write'},
        id: JourneyPathId.parse('child')!,
        at: 1,
      ))!;
      child.entries.listen(
        (e) => seenAtChild.add('${e.journeyPathId} ${e.runtimeType}'),
      );
      Result<String> write(String path) => Program.write.runOrRefusal(
        FileText(RelativePath(path), ''),
        then: (_) => const Done('ok'),
      );
      await follow(write('a'), child.at(2));
      await follow(write('b'), root.at(3));
      expect(seenAtChild, [
        'child Decided<Set<String>, int>',
        'child Returned<Set<String>, int>',
      ]);
      expect(seenAtRoot, [
        'root Narrowed<Set<String>, int>',
        ...seenAtChild,
        'root Decided<Set<String>, int>',
        'root Returned<Set<String>, int>',
      ]);
    },
  );

  test('what drivers report while running reaches the live view', () async {
    final root = start(LogAirlock(), [RecordedPrograms()]);
    final child = (await root.narrowed(
      {'dart'},
      id: JourneyPathId.parse('tests')!,
      at: 1,
    ))!;
    final seen = <String>[];
    root.underway.listen(
      (u) => seen.add(
        '${u.journeyPathId} at ${u.place}: ${switch (u.progress) {
          Printed(:final channel, :final text) => '${channel.name}: $text',
        }}',
      ),
    );
    Result<String> format() =>
        dart.runOrRefusal(const Args(['format']), then: (e) => Done(e.stdout));
    await follow(format(), root.at(2));
    await follow(format(), child.at(3));
    expect(seen, [
      'root at 2: stdout: Formatted 1 file',
      'tests at 3: stdout: Formatted 1 file',
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
    expect(await follow(post(teams, hart), path.at(1)), '201 activity-1');
    expect(
      await follow(post(teams, SignIn.parse('other-bot')!), path.at(2)),
      'failed: not in the rules',
    );
    expect(web.sent.map((r) => r.signIn), [hart]);
    expect(airlock.log, [
      '1: allow send to $teams as hart-bot',
      '1: ran send to $teams as hart-bot',
      '2: deny send to $teams as other-bot: not in the rules',
      '2: refused send to $teams as other-bot: not in the rules',
    ]);
  });

  test('a send shows its sign-in, and null only when it has none', () {
    Run<String> send(SignIn? signIn) => Program.web.run(
      Request(teams, signIn: signIn),
      then: (_) => const Done(''),
    );
    expect(
      [hart, null].map(
        (signIn) => switch (send(signIn).reach) {
          Sends(:final origin, :final signIn) => (origin, signIn),
          _ => null,
        },
      ),
      [(teams, hart), (teams, null)],
    );
  });

  test('a machine with no web driver cannot send', () async {
    expect(
      await follow(
        post(teams, hart),
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
