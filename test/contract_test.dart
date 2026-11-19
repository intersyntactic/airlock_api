import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

/// Files in memory. Refuses to write under `.git/`, in its own words.
final class MemoryFiles implements ReadsAndWritesFiles {
  final files = <String, String>{};

  @override
  Future<Outcome<ReadResult>> read(RelativePath path) async =>
      switch (files[path.value]) {
        null => const Ran(ReadMissing()),
        final text => Ran(ReadText(text)),
      };

  @override
  Future<Outcome<BytesReadResult>> readBytes(RelativePath path) async =>
      switch (files[path.value]) {
        null => const Ran(ReadMissing()),
        final text => Ran(ReadBytes(utf8.encode(text))),
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
final class RecordedPrograms implements RunsPrograms {
  final started = <List<String>>[];

  @override
  Future<Outcome<ExecResult>> runProgram(
    ProgramName program,
    Args args, {
    required Report report,
  }) async {
    started.add([program.value, ...args.args]);
    report(const Printed(Channel.stdout, 'Formatted 1 file'));
    return const Ran(Exited(0, stdout: 'Formatted 1 file', stderr: ''));
  }
}

/// Makes no request, keeps each one it was asked to make, and says the
/// destination made `activity-1`.
final class RecordedWeb implements CarriesOutWebRequests {
  final requests = <Request>[];

  @override
  Future<Outcome<WebResponse>> carryOutWebRequest(Request request) async {
    requests.add(request);
    return const Ran(WebResponse(status: 201, created: 'activity-1'));
  }
}

String reachOf(Reach reach) => switch (reach) {
  Reads(:final path) => 'read $path',
  Writes(:final file) => 'write ${file.path}',
  Starts(:final program, :final args) => [
    program.value,
    ...args.args,
  ].join(' '),
  MakesWebRequest(:final origin, :final signIn) =>
    'request to $origin as $signIn',
  CallsTheModel(:final model, :final signIn) => 'ask $model as $signIn',
};

/// Rules: what a trajectory may do, by name, and the sites it may make requests to
/// as `<origin> as <sign-in>`. Places are step numbers. Keeps a line per
/// entry, and can be told to fail writing one kind of entry.
///
/// Its logbook holds the text of each entry a test [remember]s, and of each
/// result it keeps for a proposal, which belongs to the proposal's
/// trajectory; [readOn] keeps each entry the airlock reads.
/// Which of the airlock's two writes a [LogAirlock] fails.
enum FailWriting { decision, result }

final class LogAirlock implements DecidesAndRecordsActions<Set<String>, int> {
  LogAirlock({this.failWriting});

  final FailWriting? failWriting;
  final log = <String>[];

  /// The body of each result kept for a proposal, by the proposal it
  /// answers, as the airlock would write it on the decision's chain.
  final results = <EntryId, Object?>{};
  final _logbook = <EntryId, ({String kind, String body})>{};
  final _chainOf = <EntryId, TrajectoryId>{};
  final _lastOn = <TrajectoryId, EntryId>{};

  /// Records [body] as a [kind] entry, as the logbook would, on [on]'s
  /// chain (by default the trajectory [start] starts), and gives its id.
  /// Like the logbook's, the id covers the entry before it on the chain, so
  /// it is never a hash of [body] alone and the same body twice has two.
  EntryId remember(String body, {required String kind, TrajectoryId? on}) {
    final chain = on ?? idOf('started root');
    final previous = _lastOn[chain]?.hex ?? 'none';
    final id = EntryId.of(utf8.encode('$kind\n$previous\n$body'));
    _logbook[id] = (kind: kind, body: body);
    _chainOf[id] = chain;
    _lastOn[chain] = id;
    return id;
  }

  /// The trajectory each [decide] was for, in order.
  final decidedFor = <TrajectoryId>[];

  /// Each entry the airlock read through [recordedOn], in order.
  final readOn = <EntryId>[];

  @override
  Future<Outcome<({String kind, String body})>> recordedOn(
    TrajectoryId trajectory,
    EntryId entry,
  ) async => switch ((readOn..add(entry), _logbook[entry], _chainOf[entry])) {
    (_, final recorded?, final chain) when chain == trajectory => Ran(recorded),
    (_, _?, _) => Refused('entry $entry is on another chain'),
    (_, null, _) => Refused('entry $entry is not recorded'),
  };

  @override
  Future<Decision> decide(
    TrajectoryId trajectory,
    Reach reach,
    Set<String> rules,
  ) async {
    decidedFor.add(trajectory);
    return rules.contains(switch (reach) {
          Reads() => 'read',
          Writes() => 'write',
          Starts(:final program) => program.value,
          MakesWebRequest(:final origin, :final signIn) => '$origin as $signIn',
          CallsTheModel(:final signIn) => 'model as $signIn',
        })
        ? const Allow(by: DecidedBy.rules)
        : const Deny('not in the rules', by: DecidedBy.rules);
  }

  @override
  Future<void> recordDecision(AirlockDecisionOnAction<int> decision) async {
    if (failWriting == FailWriting.decision) throw StateError('disk full');
    log.add(
      '${decision.place}: ${switch (decision) {
        AirlockDecisionOnAction(:final reach, decision: Allow()) => 'allow ${reachOf(reach)}',
        AirlockDecisionOnAction(:final reach, decision: Deny(:final why)) => 'deny ${reachOf(reach)}: $why',
      }}',
    );
  }

  @override
  Future<void> recordResult(
    AirlockDecisionOnAction<int> decision,
    Outcome<Object?> result, {
    required Object? resultAsJson,
  }) async {
    if (failWriting == FailWriting.result) throw StateError('disk full');
    if (decision.proposed case final proposed?) {
      final body = outcomeOfProposedActionToJson(proposed, resultAsJson);
      results[proposed] = body;
      remember(
        jsonEncode(body),
        kind: outcomeOfProposedActionKind,
        on: decision.trajectoryId,
      );
    }
    log.add(
      '${decision.place}: ${switch (result) {
        Ran() => 'ran ${reachOf(decision.reach)}',
        Refused(:final why) => 'refused ${reachOf(decision.reach)}: $why',
      }}',
    );
  }
}

final dart = Executable.parse('dart')!;

/// Writes [path], then formats it: two actions, and what the second printed.
Result<String> writeAndFormat(String path) => Program.write.runOrRefusal(
  FileText(RelativePath(path), 'void main() {}'),
  then: (wrote) => dart.runOrRefusal(
    Args(['format', path]),
    then: (exec) => Done(exec.stdout),
  ),
);

/// [result] carried through at [crux] to an answer, or why there is none.
Future<String> answerOf(Result<String> result, Crux crux) async {
  while (result is Action<String>) {
    result = await result.next(crux);
  }
  return switch (result) {
    Done(:final value) => value,
    Failed(:final why) => 'failed: $why',
    Action() => throw StateError('carried through to an answer'),
  };
}

/// The id of a trajectory started by the entry [startedBy], as the
/// docking station names it: by that entry's hash.
TrajectoryId idOf(String startedBy) => TrajectoryId.of(utf8.encode(startedBy));

/// A trajectory as the docking station starts one, with the airlock's side
/// of it set up in this process.
Trajectory<Set<String>, int> start(
  LogAirlock airlock,
  List<CarriesOutActions> drivers, {
  Set<String> rules = const {'read', 'write', 'dart'},
}) => Trajectory(
  id: idOf('started root'),
  drivers: drivers,
  airlock: airlock,
  rules: rules,
  suit: suit1,
);

/// The suit loop_launcher hands a path in these tests.
final suit1 = Suit.parse('suit-1')!;

final hart = SignIn.parse('hart-bot')!;
final teams = Origin.parse('https://smba.trafficmanager.net')!;

const teamsMessage = Projection.teamsMessageFromModelReply;

/// A proposal of [program] with [input], as a loop writes one on [on]'s
/// chain (by default the trajectory [start] starts).
EntryId recordedProposal(
  LogAirlock airlock,
  String program,
  Object? input, {
  TrajectoryId? on,
}) => airlock.remember(
  jsonEncode({
    'place': [1, 0],
    'program': program,
    'input': input,
  }),
  kind: ActionProposedByAgentLoop.kind,
  on: on,
);

/// A proposal to ask the model, on [on]'s chain.
EntryId askedTheModel(LogAirlock airlock, {TrajectoryId? on}) =>
    recordedProposal(airlock, 'model', {
      'signIn': 'hart-model',
      'model': 'claude-opus-5-5',
      'request': EntryId.of(utf8.encode('a model request')).hex,
    }, on: on);

/// The result [resultAsJson] of [proposed], kept as the airlock keeps one,
/// belonging to [on].
EntryId recordedOutcome(
  LogAirlock airlock,
  EntryId proposed,
  Object? resultAsJson, {
  TrajectoryId? on,
}) => airlock.remember(
  jsonEncode(outcomeOfProposedActionToJson(proposed, resultAsJson)),
  kind: outcomeOfProposedActionKind,
  on: on,
);

/// A model's reply [text], answering a proposal to ask the model, both
/// belonging to [on] (by default the trajectory [start] starts).
EntryId recordedReply(LogAirlock airlock, String text, {TrajectoryId? on}) =>
    recordedOutcome(
      airlock,
      askedTheModel(airlock, on: on),
      encodeOutcome<ModelReply>(
        Ran(FinishedReply(text: text)),
        encodeModelReply,
      ),
      on: on,
    );

/// A Teams message whose text is [text], as [teamsMessage] draws it.
String teamsMessageOf(String text) =>
    jsonEncode({'type': 'message', 'text': text});

Result<String> webRequest(
  Origin site,
  SignIn signIn, {
  EntryId? drawnFrom,
  String? body,
  Projection projection = teamsMessage,
}) => Program.web.runOrRefusal(
  WebRequest(
    site,
    path: WebPath.parse('/v3/conversations/c/activities')!,
    signIn: signIn,
    body: body ?? teamsMessageOf('done'),
    projection: projection,
    drawnFrom: drawnFrom ?? EntryId.of(utf8.encode('nothing recorded')),
  ),
  then: (answer) => Done('${answer.status} ${answer.created}'),
);

void main() {
  test('every entry is at the place its crux was given', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles(), RecordedPrograms()]);
    expect(
      await answerOf(writeAndFormat('a.dart'), path.at(1)),
      'Formatted 1 file',
    );
    expect(
      await answerOf(writeAndFormat('b.dart'), path.at(2)),
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
      final answer = await answerOf(
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

  test('a denied action reaches no driver, is recorded, and fails', () async {
    final files = MemoryFiles();
    final airlock = LogAirlock();
    final answer = await answerOf(
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
    final answer = await answerOf(
      writeAndFormat('.git/config'),
      start(LogAirlock(), [MemoryFiles(), programs]).at(1),
    );
    expect(answer, "failed: .git/config is git's own");
    expect(programs.started, isEmpty);
  });

  test('no driver is reached when the decision cannot be recorded', () async {
    final files = MemoryFiles();
    await expectLater(
      answerOf(
        writeAndFormat('lib/a.dart'),
        start(LogAirlock(failWriting: FailWriting.decision), [files]).at(1),
      ),
      throwsStateError,
    );
    expect(files.files, isEmpty);
  });

  test('an outcome that cannot be recorded does not flow on', () async {
    final files = MemoryFiles();
    final programs = RecordedPrograms();
    await expectLater(
      answerOf(
        writeAndFormat('lib/a.dart'),
        start(LogAirlock(failWriting: FailWriting.result), [
          files,
          programs,
        ]).at(1),
      ),
      throwsStateError,
    );
    // The write reached the world; the record's AirlockDecisionOnAction entry says so. The
    // continuation never saw it, so dart was never started.
    expect(files.files, {'lib/a.dart': 'void main() {}'});
    expect(programs.started, isEmpty);
  });

  test('stopping a trajectory refuses what it has not yet run', () async {
    final files = MemoryFiles();
    final airlock = LogAirlock();
    final path = start(airlock, [files])..stop();
    expect(
      await answerOf(writeAndFormat('lib/a.dart'), path.at(2)),
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
    root.decisions.listen(
      (d) => decided.add('${d.decision.runtimeType} by ${d.decision.by.name}'),
    );
    await answerOf(writeAndFormat('a.dart'), root.at(1));
    root.stop();
    await answerOf(writeAndFormat('a.dart'), root.at(2));
    expect(decided, ['Allow by rules', 'Allow by rules', 'Deny by person']);
  });

  test('each decision and result reaches the trajectory, naming it', () async {
    final path = start(LogAirlock(), [MemoryFiles()], rules: {'write'});
    final seen = <String>[];
    path.decisions.listen(
      (d) => seen.add('${d.trajectoryId == path.id} decision at ${d.place}'),
    );
    path.results.listen(
      (r) => seen.add(
        '${r.decision.trajectoryId == path.id} '
        '${r.result.runtimeType} at ${r.decision.place}',
      ),
    );
    await answerOf(
      Program.write.runOrRefusal(
        FileText(RelativePath('a'), ''),
        then: (_) => const Done('ok'),
      ),
      path.at(2),
    );
    expect(seen, ['true decision at 2', 'true Ran<Wrote> at 2']);
  });

  test('what drivers report while running reaches the live view', () async {
    final path = start(LogAirlock(), [RecordedPrograms()], rules: {'dart'});
    final seen = <String>[];
    path.underway.listen(
      (u) => seen.add(
        'at ${u.place}: ${switch (u.progress) {
          Printed(:final channel, :final text) => '${channel.name}: $text',
          ReplyArriving(:final text) => 'reply: $text',
        }}',
      ),
    );
    Result<String> format() =>
        dart.runOrRefusal(const Args(['format']), then: (e) => Done(e.stdout));
    await answerOf(format(), path.at(2));
    await answerOf(format(), path.at(3));
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
      await answerOf(result, start(LogAirlock(), [files]).at(1)),
      'replaced true: new',
    );
  });

  test('a web request is decided by its origin and sign-in together', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final reply = recordedReply(airlock, 'done');
    final path = start(airlock, [web], rules: {'$teams as $hart'});
    expect(
      await answerOf(webRequest(teams, hart, drawnFrom: reply), path.at(1)),
      '201 activity-1',
    );
    expect(
      await answerOf(
        webRequest(teams, SignIn.parse('other-bot')!, drawnFrom: reply),
        path.at(2),
      ),
      'failed: not in the rules',
    );
    expect(web.requests.map((r) => r.signIn), [hart]);
    expect(airlock.log, [
      '1: allow request to $teams as hart-bot',
      '1: ran request to $teams as hart-bot',
      '2: deny request to $teams as other-bot: not in the rules',
      '2: refused request to $teams as other-bot: not in the rules',
    ]);
  });

  test(
    'a web request shows its sign-in, and null only when it has none',
    () async {
      final path = start(LogAirlock(), [RecordedWeb()]);
      final seen = <(Origin, SignIn?)>[];
      path.decisions.listen((d) {
        if (d.reach case MakesWebRequest(:final origin, :final signIn)) {
          seen.add((origin, signIn));
        }
      });
      for (final (i, signIn) in [hart, null].indexed) {
        await Program.web
            .run(
              WebRequest(
                teams,
                signIn: signIn,
                body: '',
                projection: teamsMessage,
                drawnFrom: EntryId.of(utf8.encode('nothing recorded')),
              ),
              then: (_) => const Done(''),
            )
            .next(path.at(i));
      }
      expect(seen, [(teams, hart), (teams, null)]);
    },
  );

  test('a web request sends exactly the body its projection draws from a '
      'recorded model reply, and the decision holds that body', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final asked = askedTheModel(airlock);
    final reply = recordedOutcome(
      airlock,
      asked,
      encodeOutcome<ModelReply>(
        const Ran(FinishedReply(text: 'Clause 4 — rent is due monthly.')),
        encodeModelReply,
      ),
    );
    final path = start(airlock, [web], rules: {'$teams as $hart'});
    final decided = <AirlockDecisionOnAction<int>>[];
    path.decisions.listen(decided.add);
    final body = teamsMessageOf('Clause 4 — rent is due monthly.');
    expect(
      await answerOf(
        webRequest(teams, hart, drawnFrom: reply, body: body),
        path.at(1),
      ),
      '201 activity-1',
    );
    expect(
      web.requests.single.body,
      '{"type":"message","text":"Clause 4 — rent is due monthly."}',
    );
    expect(airlock.readOn, [reply, asked]);
    final MakesWebRequest(:request) = decided.single.reach as MakesWebRequest;
    expect(request.body, body);
    expect(request.drawnFrom, reply);
  });

  test('a body that is not what its projection draws from the record is '
      'refused, for its own reason, and nothing is sent', () async {
    final other = idOf('another trajectory');
    final cases = <(String, String, EntryId Function(LogAirlock), String)>[
      (
        'other words',
        teamsMessageOf('something else'),
        (a) => recordedReply(a, 'done'),
        'the body is not teams-message-from-model-reply of',
      ),
      (
        'the same words, spaced',
        '{"type": "message", "text": "done"}',
        (a) => recordedReply(a, 'done'),
        'the body is not teams-message-from-model-reply of',
      ),
      (
        'a reply that was refused',
        teamsMessageOf('done'),
        (a) => a.remember(
          jsonEncode(proposalRejectedToJson(askedTheModel(a), 'no')),
          kind: outcomeOfProposedActionKind,
        ),
        'the body is not teams-message-from-model-reply of',
      ),
      (
        'a result that did not run, though it holds text',
        teamsMessageOf('done'),
        (a) => a.remember(
          jsonEncode({
            'proposed': askedTheModel(a).hex,
            'result': {'kind': 'refused', 'output': 'done'},
          }),
          kind: outcomeOfProposedActionKind,
        ),
        'the body is not teams-message-from-model-reply of',
      ),
      (
        'not a result at all',
        teamsMessageOf('done'),
        (a) => a.remember('done', kind: outcomeOfProposedActionKind),
        'names no proposal',
      ),
      (
        'a reply to a proposal on another chain',
        teamsMessageOf('done'),
        (a) => recordedOutcome(
          a,
          askedTheModel(a, on: other),
          encodeOutcome<ModelReply>(
            const Ran(FinishedReply(text: 'done')),
            encodeModelReply,
          ),
        ),
        'is on another chain',
      ),
      (
        'a reply naming an entry that is not a proposal',
        teamsMessageOf('done'),
        (a) => recordedOutcome(
          a,
          a.remember('{}', kind: ModelRequestPiece.kind),
          encodeOutcome<ModelReply>(
            const Ran(FinishedReply(text: 'done')),
            encodeModelReply,
          ),
        ),
        'is a model-request-piece, not a action-proposed-by-agent-loop',
      ),
      (
        'a reply naming a proposal that is not one',
        teamsMessageOf('done'),
        (a) => recordedOutcome(
          a,
          a.remember('not json', kind: ActionProposedByAgentLoop.kind),
          encodeOutcome<ModelReply>(
            const Ran(FinishedReply(text: 'done')),
            encodeModelReply,
          ),
        ),
        'which asked no model',
      ),
      (
        // A loop may write any body under its own kinds on its own chain.
        'a reply-shaped body the loop wrote under another kind',
        teamsMessageOf('anything the loop likes'),
        (a) => a.remember(
          jsonEncode(
            outcomeOfProposedActionToJson(
              EntryId.of(utf8.encode('p')),
              encodeOutcome<ModelReply>(
                const Ran(FinishedReply(text: 'anything the loop likes')),
                encodeModelReply,
              ),
            ),
          ),
          kind: ModelRequestPiece.kind,
        ),
        'is a model-request-piece, not a outcome-of-proposed-action',
      ),
      (
        "another trajectory's reply",
        teamsMessageOf('done'),
        (a) => recordedReply(a, 'done', on: other),
        'is on another chain',
      ),
      (
        'nothing recorded',
        teamsMessageOf('done'),
        (a) => EntryId.of(utf8.encode('never written')),
        'is not recorded',
      ),
    ];
    for (final (why, body, drawnFrom, said) in cases) {
      final web = RecordedWeb();
      final airlock = LogAirlock();
      final answer = await answerOf(
        webRequest(teams, hart, drawnFrom: drawnFrom(airlock), body: body),
        start(airlock, [web], rules: {'$teams as $hart'}).at(1),
      );
      expect(
        answer,
        allOf(startsWith('failed: '), contains(said)),
        reason: why,
      );
      expect(web.requests, isEmpty, reason: why);
      expect(
        airlock.log.last,
        startsWith('1: refused request to $teams as hart-bot: '),
        reason: why,
      );
    }
  });

  test("a file read's text is never sent as a model's reply", () async {
    // A read's result is {"kind":"text","text":…}, which reads as a reply.
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final read = recordedProposal(airlock, 'read', 'secret.txt');
    final answer = await answerOf(
      webRequest(
        teams,
        hart,
        drawnFrom: recordedOutcome(
          airlock,
          read,
          encodeOutcome<ReadResult>(
            const Ran(ReadText('the secret file')),
            encodeReadResult,
          ),
        ),
        body: teamsMessageOf('the secret file'),
      ),
      start(airlock, [web], rules: {'$teams as $hart'}).at(1),
    );
    expect(answer, allOf(startsWith('failed: '), contains('asked no model')));
    expect(web.requests, isEmpty);
  });

  test('a trajectory open card is sent only as its fixed bytes, drawn from '
      'its own trajectory, and reads nothing', () async {
    final own = EntryId.parse(idOf('started root').hex)!;
    final cases = [
      ('the card, from its trajectory', own, trajectoryOpenCardBody, true),
      (
        'from another trajectory',
        EntryId.parse(idOf('another root').hex)!,
        trajectoryOpenCardBody,
        false,
      ),
      ('another body', own, teamsMessageOf('done'), false),
    ];
    for (final (why, drawnFrom, body, sent) in cases) {
      final web = RecordedWeb();
      final airlock = LogAirlock();
      final answer = await answerOf(
        webRequest(
          teams,
          hart,
          drawnFrom: drawnFrom,
          body: body,
          projection: Projection.trajectoryOpenCard,
        ),
        start(airlock, [web], rules: {'$teams as $hart'}).at(1),
      );
      expect(answer, sent ? '201 activity-1' : startsWith('failed: '));
      expect(
        [for (final r in web.requests) r.body],
        [if (sent) trajectoryOpenCardBody],
        reason: why,
      );
      expect(airlock.readOn, isEmpty, reason: why);
    }
    expect(
      Projection.trajectoryOpenCard.drawnFrom(
        jsonEncode(
          outcomeOfProposedActionToJson(
            own,
            encodeOutcome<ModelReply>(
              Ran(FinishedReply(text: 'hi')),
              encodeModelReply,
            ),
          ),
        ),
      ),
      isNull,
    );
    expect(trajectoryOpenCardBody, contains('"verb":"close"'));
    expect(trajectoryOpenCardBody, contains('● Open · trajectory started'));
    expect(
      Projection.parse('trajectory-open-card'),
      Projection.trajectoryOpenCard,
    );
  });

  test('the airlock decides knowing which trajectory acts', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles()], rules: {'write', 'dart'});
    await answerOf(writeAndFormat('a.dart'), path.at(1));
    expect(airlock.decidedFor, [path.id, path.id]);
  });

  test('a denied web request never has its entry read', () async {
    final airlock = LogAirlock();
    final answer = await answerOf(
      webRequest(teams, hart, drawnFrom: recordedReply(airlock, 'done')),
      start(airlock, [RecordedWeb()], rules: const {}).at(1),
    );
    expect(answer, 'failed: not in the rules');
    expect(airlock.readOn, isEmpty);
  });

  test(
    'nothing is read or sent when the decision cannot be recorded',
    () async {
      final web = RecordedWeb();
      final airlock = LogAirlock(failWriting: FailWriting.decision);
      await expectLater(
        answerOf(
          webRequest(teams, hart, drawnFrom: recordedReply(airlock, 'done')),
          start(airlock, [web], rules: {'$teams as $hart'}).at(1),
        ),
        throwsStateError,
      );
      expect(airlock.log, isEmpty);
      expect(airlock.readOn, isEmpty);
      expect(web.requests, isEmpty);
    },
  );

  test('a web request cannot hold a credential, or a path to another site', () {
    expect(
      () => WebRequest(
        teams,
        body: '',
        projection: teamsMessage,
        drawnFrom: EntryId.of(utf8.encode('nothing recorded')),
        headers: {'Authorization': 'Bearer x'},
      ),
      throwsArgumentError,
    );
    expect(
      ['//evil.example', '/a/../b', '/@evil.example', 'v3'].map(WebPath.parse),
      everyElement(isNull),
    );
  });

  test('projections are named once, at the boundary', () {
    expect(
      Projection.parse('teams-message-from-model-reply'),
      Projection.teamsMessageFromModelReply,
    );
    expect(
      ['', 'teams-reply', 'teamsMessageFromModelReply'].map(Projection.parse),
      everyElement(isNull),
    );
  });

  test('a machine with no web driver makes no web request', () async {
    expect(
      await answerOf(
        webRequest(teams, hart),
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
