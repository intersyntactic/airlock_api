import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show
        LogAirlock,
        MemoryFiles,
        RecordedWeb,
        answerOf,
        hart,
        start,
        teams,
        teamsMessage,
        teamsMessageOf,
        webRequest,
        writeAndFormat;

/// [json] as the logbook would hold it and give it back: JSON text.
JsonObject throughText(Object? json) => JsonObject.decode(jsonEncode(json));

/// The [AirlockDecisionOnAction] entries recorded while [run] is carried through on a trajectory
/// with [rules].
Future<List<AirlockDecisionOnAction<int>>> decidedWhile(
  Future<void> Function(Trajectory<Set<String>, int> path) run, {
  Set<String> rules = const {},
}) async {
  final airlock = LogAirlock();
  final path = start(airlock, [RecordedWeb(), MemoryFiles()], rules: rules);
  final decided = <AirlockDecisionOnAction<int>>[];
  path.decisions.listen(decided.add);
  await run(path);
  return decided;
}

void main() {
  test("a web request's decision reads back as it was written, its exact "
      'body among it', () async {
    expect(AirlockDecisionOnWebRequest.kind, 'airlock-decision-on-web-request');
    final reply = EntryId.of(utf8.encode('a reply'));
    final body = teamsMessageOf('Clause 4 — monthly.');
    final decided = await decidedWhile(
      (path) => answerOf(
        webRequest(teams, hart, drawnFrom: reply, body: body),
        path.at(4),
      ),
      rules: {'$teams as $hart'},
    );
    final written = AirlockDecisionOnWebRequest.of(
      decided.single,
      (int place) => place,
    )!;
    final read = AirlockDecisionOnWebRequest.fromJson(
      throughText(written.toJson()),
    );
    expect(read.trajectory, written.trajectory);
    expect(read.place, 4);
    expect(read.request.origin, teams);
    expect(read.request.signIn, hart);
    expect(read.request.method, Method.post);
    expect(read.request.path, written.request.path);
    expect(read.request.body, body);
    expect(read.request.projection, Projection.teamsMessageFromModelReply);
    expect(read.request.drawnFrom, reply);
    expect(read.decision, isA<Allow>());
    expect(read.decision.by, DecidedBy.rules);
    expect(read.proposed, isNull);
  });

  test('a web request decided for a proposal names it, so no two such '
      'decisions are byte-identical', () async {
    final [d] = await decidedWhile(
      (path) => answerOf(webRequest(teams, hart), path.at(4)),
      rules: {'$teams as $hart'},
    );
    Object? asProposed(String proposal) => AirlockDecisionOnWebRequest.of(
      AirlockDecisionOnAction(
        d.trajectoryId,
        d.place,
        d.reach,
        d.decision,
        proposed: EntryId.of(utf8.encode(proposal)),
      ),
      (int place) => place,
    )!.toJson();
    final read = AirlockDecisionOnWebRequest.fromJson(
      throughText(asProposed('one')),
    );
    expect(read.proposed, EntryId.of(utf8.encode('one')));
    expect(jsonEncode(asProposed('one')), isNot(jsonEncode(asProposed('two'))));
    final json = asProposed('one');
    expect(json, isA<Map<String, Object?>>());
    if (json case final Map<String, Object?> written) {
      expect(
        () => AirlockDecisionOnWebRequest.fromJson(
          JsonObject.of({...written, 'proposed': 'nope'}),
        ),
        throwsFormatException,
      );
    }
  });

  test('the entries a decision relied on read back, and a decision that '
      'relied on none is written as before', () async {
    final [d] = await decidedWhile(
      (path) => answerOf(webRequest(teams, hart), path.at(4)),
      rules: {'$teams as $hart'},
    );
    final lease = EntryId.of(utf8.encode('bot leased'));
    final settings = EntryId.of(utf8.encode('settings'));
    Object? written(Decision decision) => AirlockDecisionOnWebRequest.of(
      AirlockDecisionOnAction(d.trajectoryId, d.place, d.reach, decision),
      (int place) => place,
    )!.toJson();
    for (final decision in [
      Allow(by: DecidedBy.rules, reliedOn: [lease, settings]),
      Deny('leased elsewhere', by: DecidedBy.rules, reliedOn: [lease]),
    ]) {
      final read = AirlockDecisionOnWebRequest.fromJson(
        throughText(written(decision)),
      );
      expect(read.decision.reliedOn, decision.reliedOn);
      expect(read.decision.runtimeType, decision.runtimeType);
    }
    expect(
      throughText(written(const Allow(by: DecidedBy.rules)))
          .asUncheckedMap()['decision'],
      {'allow': true, 'by': 'rules'},
    );
    final json = throughText(written(Allow(by: DecidedBy.rules)));
    for (final (bad, said) in [
      (['x'], 'decided.decision.reliedOn[0]: not an entry id'),
      ([1], 'decided.decision.reliedOn: not a list of strings'),
    ]) {
      expect(
        () => AirlockDecisionOnWebRequest.fromJson(
          JsonObject.of({
            ...json.asUncheckedMap(),
            'decision': {'allow': true, 'by': 'rules', 'reliedOn': bad},
          }),
        ),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', said),
        ),
      );
    }
  });

  test('a denied web request reads back with why', () async {
    final decided = await decidedWhile(
      (path) => answerOf(webRequest(teams, hart), path.at(1)),
    );
    final [denied] = [
      for (final d in decided)
        AirlockDecisionOnWebRequest.fromJson(
          throughText(
            AirlockDecisionOnWebRequest.of(d, (int place) => place)!.toJson(),
          ),
        ),
    ];
    expect(denied.decision, isA<Deny>());
    expect(switch (denied.decision) {
      Deny(:final why) => why,
      Allow() => 'allowed',
    }, 'not in the rules');
  });

  test(
    "an action that is not a web request has no web request entry",
    () async {
      final decided = await decidedWhile(
        (path) => answerOf(writeAndFormat('a.dart'), path.at(1)),
        rules: {'write', 'dart'},
      );
      expect(
        decided.map(
          (d) => AirlockDecisionOnWebRequest.of(d, (int place) => place),
        ),
        everyElement(isNull),
      );
    },
  );

  test('a malformed entry is refused, naming the part', () async {
    final decided = await decidedWhile(
      (path) => answerOf(webRequest(teams, hart), path.at(1)),
      rules: {'$teams as $hart'},
    );
    final json = throughText(
      AirlockDecisionOnWebRequest.of(decided.single, (int p) => p)!.toJson(),
    ).asUncheckedMap();
    Map<String, Object?> change(String key, Object? value) => {
      ...json,
      key: value,
    };
    final request = json['request']! as Map<String, Object?>;
    String? whyNot(Object? entry) {
      try {
        AirlockDecisionOnWebRequest.fromJson(
          JsonObject.decode(jsonEncode(entry)),
        );
        return null;
      } on FormatException catch (e) {
        return e.message;
      }
    }

    expect(whyNot(json), isNull);
    expect(
      whyNot(change('request', {...request, 'path': '//evil.example'})),
      startsWith('decided.request.path'),
    );
    expect(
      whyNot(change('decision', {'allow': true, 'by': 'robot'})),
      startsWith('decided.decision.by'),
    );
    expect(
      whyNot(change('request', {...request, 'projection': 'teams-reply'})),
      startsWith('decided.request.projection'),
    );
    expect(
      whyNot(change('request', {...request, 'drawnFrom': 'x'})),
      startsWith('decided.request.drawnFrom'),
    );
    expect(
      whyNot(change('request', {...request, 'body': null})),
      startsWith('decided.request.body'),
    );
    expect(whyNot(change('trajectory', 'x')), startsWith('decided.trajectory'));
  });

  test('a Teams message is drawn only from a reply the model ran to', () {
    final proposed = EntryId.of(utf8.encode('asked'));
    String outcome(Object? result) =>
        jsonEncode(outcomeOfProposedActionToJson(proposed, result));
    String? drawn(ModelReply reply) => teamsMessage.drawnFrom(
      outcome(encodeOutcome<ModelReply>(Ran(reply), encodeModelReply)),
    );
    const usage = ModelUsage(
      input: 150000,
      cacheRead: 2000,
      output: 300,
      contextWindow: 1000000,
    );
    expect(drawn(const FinishedReply(text: 'hi')), teamsMessageOf('hi'));
    expect(
      drawn(const FinishedReply(text: 'hi', usage: usage)),
      teamsMessageOf('hi'),
      reason: 'a reply with usage is written as an object, and still drawn',
    );
    for (final reply in [
      const CutOffReply(text: 'Clause 4 is'),
      const CutOffReply(text: 'Clause 4 is', usage: usage),
    ]) {
      expect(
        drawn(reply),
        teamsMessageOf('Clause 4 is\n\n_(reply cut off)_'),
        reason: 'a cut-off reply is never posted as the whole answer',
      );
    }
    for (final recorded in [
      outcome(encodeOutcome<ModelReply>(const Refused('no'), encodeModelReply)),
      outcome({'kind': 'ran', 'output': 7}),
      outcome({'kind': 'reported', 'output': 'hi'}),
      'not json',
    ]) {
      expect(teamsMessage.drawnFrom(recorded), isNull, reason: recorded);
    }
  });
}
