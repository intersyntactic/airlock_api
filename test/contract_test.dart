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
/// destination made `activity-<n>`, n counting from 1; or, for the request
/// numbered [refuseAt], the destination answers 403, and for the one
/// numbered [cannotSendAt], the driver itself refuses.
final class RecordedWeb implements CarriesOutWebRequests {
  RecordedWeb({this.refuseAt, this.cannotSendAt});

  final int? refuseAt;
  final int? cannotSendAt;
  final requests = <Request>[];

  @override
  Future<Outcome<WebResponse>> carryOutWebRequest(Request request) async {
    requests.add(request);
    final n = requests.length;
    if (n == cannotSendAt) return Refused('${request.signIn} is not held here');
    return Ran(
      n == refuseAt
          ? const WebResponse(status: 403, refusedBecause: 'throttled')
          : WebResponse(status: 201, created: 'activity-$n'),
    );
  }
}

/// A web driver that keeps every request and answers 200 with the body
/// each asked to keep: "PK zip" as bytes or text.
final class FetchingWeb implements CarriesOutWebRequests {
  final requests = <Request>[];

  @override
  Future<Outcome<WebResponse>> carryOutWebRequest(Request request) async {
    requests.add(request);
    return Ran(
      WebResponse(
        status: 200,
        body: switch (request.keep) {
          BodyToKeep.none => const NoBody(),
          BodyToKeep.text => const TextBody('PK zip'),
          BodyToKeep.bytes => BytesBody(utf8.encode('PK zip')),
        },
      ),
    );
  }
}

String reachOf(Reach reach) => switch (reach) {
  Reads(:final path) => 'read $path',
  Writes(:final file) => 'write ${file.path}',
  Starts(:final program, :final args) => [
    program.value,
    ...args.args,
  ].join(' '),
  AnswersEvent(:final requests) =>
    'answer with ${requests.length} '
        '[${requests.map((r) => '${r.origin} as ${r.signIn}').join(', ')}]',
  FetchesFromWeb(:final origin, :final path, :final signIn) =>
    'fetch $origin${path.value} as $signIn',
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

  /// The id of the outcome entry each result was kept as, by the proposal
  /// it answers.
  final outcomeEntries = <EntryId, EntryId>{};
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
    final granted = switch (reach) {
      Reads() => [rules.contains('read')],
      Writes() => [rules.contains('write')],
      Starts(:final program) => [rules.contains(program.value)],
      AnswersEvent(:final requests) => [
        for (final r in requests) rules.contains('${r.origin} as ${r.signIn}'),
      ],
      FetchesFromWeb(:final origin, :final signIn) => [
        rules.contains('fetch $origin as $signIn'),
      ],
      CallsTheModel(:final signIn) => [rules.contains('model as $signIn')],
    };
    return granted.every((g) => g)
        ? const Allow(by: DecidedBy.rules)
        : const Deny('not in the rules', by: DecidedBy.rules);
  }

  /// The admissions a reply may answer: each of an event that starts a
  /// turn on the trajectory [start] starts.
  final admissions = <EntryId>{admission};

  /// Who the requests that answer an event go as.
  SignIn answerAs = hart;

  /// The reply each [replyRequests] was asked to build from, in order.
  final builtFrom = <ModelReply>[];

  /// The place each [replyRequests] or [trajectoryOpenedRequests] was asked
  /// to build at, in order.
  final builtAt = <int>[];

  /// The reason each [refusalNoticeRequests] was asked to tell, in order.
  final toldWhy = <String>[];

  /// One Teams message telling [why], to an admission a reply may answer.
  @override
  Future<Outcome<List<Request>>> refusalNoticeRequests(
    TrajectoryId trajectory,
    int place,
    EntryId respondsTo,
    String why,
  ) async {
    toldWhy.add(why);
    if (!admissions.contains(respondsTo)) {
      return Refused('entry $respondsTo admits no event that starts a turn');
    }
    return Ran([
      Request(
        teams,
        method: Method.post,
        path: conversation,
        signIn: answerAs,
        body: teamsMessageOf('refused: $why'),
      ),
    ]);
  }

  /// A stand-in for an event system's module: one Teams message per part
  /// of the reply's text, the parts split at `|`.
  @override
  Future<Outcome<List<Request>>> replyRequests(
    TrajectoryId trajectory,
    int place,
    EntryId respondsTo,
    ModelReply reply,
  ) async {
    builtFrom.add(reply);
    builtAt.add(place);
    if (!admissions.contains(respondsTo)) {
      return Refused('entry $respondsTo admits no event that starts a turn');
    }
    return Ran([
      for (final part in reply.text.split('|'))
        Request(
          teams,
          method: Method.post,
          path: conversation,
          signIn: answerAs,
          body: teamsMessageOf(part),
        ),
    ]);
  }

  @override
  Future<Outcome<List<Request>>> trajectoryOpenedRequests(
    TrajectoryId trajectory,
    int place,
  ) async {
    builtAt.add(place);
    return Ran([
      Request(
        teams,
        method: Method.post,
        path: conversation,
        signIn: answerAs,
        body: openCardBody,
      ),
    ]);
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
    final body = outcomeOfProposedActionToJson(decision.proposed, resultAsJson);
    results[decision.proposed] = body;
    outcomeEntries[decision.proposed] = remember(
      jsonEncode(body),
      kind: outcomeOfProposedActionKind,
      on: decision.trajectoryId,
    );
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

/// A trajectory's chain and the airlock's, in memory: each proposal the
/// loop writes goes through `jsonEncode` and back, as the logbook would keep
/// it, and is named by the id the logbook gives it, as the loop's write
/// returns it, never a hash of the body alone; the airlock service considers
/// it on [path], and the loop is handed the result that names it, through
/// `jsonEncode` and back, as loop_launcher would hand it.
/// The airlock service considers each at [placeOf] its place, by default its
/// step. Keeps why each rejected entry was rejected.
final class RecordedLink implements ProposesActionsThroughTheRecord {
  RecordedLink(this.path, this.airlock, {this.placeOf = _stepOf});

  final Trajectory<Set<String>, int> path;
  final LogAirlock airlock;
  final int Function(PlaceInTrajectory place) placeOf;
  final rejected = <String>[];

  /// The program and place of each proposal read back, in order.
  final programs = <Program<Object?, Object?>>[];
  final places = <PlaceInTrajectory>[];

  /// What loop_launcher would hand the loop for the outcome [body] and the
  /// proposal it answers, when a test wants another answer.
  String Function(String body, EntryId proposed) answerWith = (body, _) => body;

  @override
  Future<EntryId> writeProposal(String body) async {
    final proposed = airlock.remember(
      body,
      kind: ActionProposedByAgentLoop.kind,
    );
    switch (ActionProposedByAgentLoop.read(body)) {
      case Rejected(:final why):
        rejected.add(why);
        airlock.results[proposed] = proposalRejectedToJson(proposed, why);
      case final ActionProposedByAgentLoop proposal:
        programs.add(proposal.program);
        places.add(proposal.place);
        await path.consider(
          proposal,
          placeOf(proposal.place),
          proposed: proposed,
        );
    }
    return proposed;
  }

  @override
  Future<String> outcomeNaming(EntryId proposed) async =>
      answerWith(jsonEncode(airlock.results[proposed]), proposed);

  /// [proposal] written as it is, bypassing the crux, and the result of
  /// what the airlock recorded it came to.
  Future<Object?> proposeAsIs(Object? proposal) async =>
      readOutcomeOfProposedAction(
        await outcomeNaming(await writeProposal(jsonEncode(proposal))),
      )!.result;
}

int _stepOf(PlaceInTrajectory place) => place.step;

/// The agent loop's crux for [turn] on [link]'s path.
Crux loopCrux(RecordedLink link, {int turn = 1}) =>
    Crux.through(link, turn: turn);

/// The agent loop's crux for [turn] on [path], whose airlock is [airlock],
/// through the record; the airlock service considers every action of the
/// turn at [turn].
Crux throughRecord(
  Trajectory<Set<String>, int> path,
  LogAirlock airlock, {
  required int turn,
}) => Crux.through(
  RecordedLink(path, airlock, placeOf: (place) => place.turn),
  turn: turn,
);

/// The suit loop_launcher hands a path in these tests.
final suit1 = Suit.parse('suit-1')!;

final hart = SignIn.parse('hart-bot')!;
final teams = Origin.parse('https://smba.trafficmanager.net')!;
final conversation = WebPath.parse('/v3/conversations/c/activities')!;

/// The docking station's admission of an event that starts a turn on the
/// trajectory [start] starts, as a [LogAirlock] knows it.
final admission = EntryId.of(utf8.encode('an admission'));

/// A Teams message whose text is [text], as the stand-in module builds one.
String teamsMessageOf(String text) =>
    jsonEncode({'type': 'message', 'text': text});

/// The stand-in module's open card.
const openCardBody = '{"card":"open"}';

/// [answer] carried out, answered with each response's status and what the
/// destination made of it.
Result<String> answerWith(Answer answer) => Program.answerEvent.runOrRefusal(
  answer,
  then: (responses) =>
      Done(responses.map((r) => '${r.status} ${r.created}').join(', ')),
);

/// The reply recorded as [reply], answering [respondsTo] (by default
/// [admission]).
Result<String> replyWith(EntryId reply, {EntryId? respondsTo}) =>
    answerWith(ReplyToEvent(respondsTo: respondsTo ?? admission, reply: reply));

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

void main() {
  test('every entry is at the place the airlock service read for it', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles(), RecordedPrograms()]);
    expect(
      await answerOf(
        writeAndFormat('a.dart'),
        throughRecord(path, airlock, turn: 1),
      ),
      'Formatted 1 file',
    );
    expect(
      await answerOf(
        writeAndFormat('b.dart'),
        throughRecord(path, airlock, turn: 2),
      ),
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
        throughRecord(start(airlock, [files]), airlock, turn: 1),
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
      throughRecord(start(airlock, [files], rules: {'read'}), airlock, turn: 1),
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
    final airlock = LogAirlock();
    final answer = await answerOf(
      writeAndFormat('.git/config'),
      throughRecord(
        start(airlock, [MemoryFiles(), programs]),
        airlock,
        turn: 1,
      ),
    );
    expect(answer, "failed: .git/config is git's own");
    expect(programs.started, isEmpty);
  });

  test('no driver is reached when the decision cannot be recorded', () async {
    final files = MemoryFiles();
    final airlock = LogAirlock(failWriting: FailWriting.decision);
    await expectLater(
      answerOf(
        writeAndFormat('lib/a.dart'),
        throughRecord(start(airlock, [files]), airlock, turn: 1),
      ),
      throwsStateError,
    );
    expect(files.files, isEmpty);
  });

  test('an outcome that cannot be recorded does not flow on', () async {
    final files = MemoryFiles();
    final programs = RecordedPrograms();
    final airlock = LogAirlock(failWriting: FailWriting.result);
    await expectLater(
      answerOf(
        writeAndFormat('lib/a.dart'),
        throughRecord(start(airlock, [files, programs]), airlock, turn: 1),
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
      await answerOf(
        writeAndFormat('lib/a.dart'),
        throughRecord(path, airlock, turn: 2),
      ),
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
    final airlock = LogAirlock();
    final root = start(airlock, [MemoryFiles(), RecordedPrograms()]);
    root.decisions.listen(
      (d) => decided.add('${d.decision.runtimeType} by ${d.decision.by.name}'),
    );
    await answerOf(
      writeAndFormat('a.dart'),
      throughRecord(root, airlock, turn: 1),
    );
    root.stop();
    await answerOf(
      writeAndFormat('a.dart'),
      throughRecord(root, airlock, turn: 2),
    );
    expect(decided, ['Allow by rules', 'Allow by rules', 'Deny by person']);
  });

  test('each decision and result reaches the trajectory, naming it', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles()], rules: {'write'});
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
      throughRecord(path, airlock, turn: 2),
    );
    expect(seen, ['true decision at 2', 'true Ran<Wrote> at 2']);
  });

  test('what drivers report while running reaches the live view', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [RecordedPrograms()], rules: {'dart'});
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
    await answerOf(format(), throughRecord(path, airlock, turn: 2));
    await answerOf(format(), throughRecord(path, airlock, turn: 3));
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
    final airlock = LogAirlock();
    expect(
      await answerOf(
        result,
        throughRecord(start(airlock, [files]), airlock, turn: 1),
      ),
      'replaced true: new',
    );
  });

  test('the airlock decides knowing which trajectory acts', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles()], rules: {'write', 'dart'});
    await answerOf(
      writeAndFormat('a.dart'),
      throughRecord(path, airlock, turn: 1),
    );
    expect(airlock.decidedFor, [path.id, path.id]);
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
