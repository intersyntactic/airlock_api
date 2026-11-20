import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show
        FailWriting,
        LogAirlock,
        MemoryFiles,
        RecordedWeb,
        admission,
        answerOf,
        answerWith,
        askedTheModel,
        hart,
        idOf,
        openCardBody,
        recordedOutcome,
        recordedProposal,
        recordedReply,
        replyWith,
        start,
        teams,
        teamsMessageOf;

/// [json] as the logbook would hold it and give it back: JSON text.
JsonObject throughText(Object? json) => JsonObject.decode(jsonEncode(json));

void main() {
  test('a reply is built first, decided holding every exact request, then '
      'sent in order', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final reply = recordedReply(airlock, 'Clause 4 —|rent is due monthly.');
    final path = start(airlock, [web], rules: {'$teams as $hart'});
    final decided = <AirlockDecisionOnAction<int>>[];
    path.decisions.listen(decided.add);
    expect(
      await answerOf(replyWith(reply), path.at(1)),
      '201 activity-1, 201 activity-2',
    );
    expect(
      [for (final r in web.requests) r.body],
      [teamsMessageOf('Clause 4 —'), teamsMessageOf('rent is due monthly.')],
    );
    final AnswersEvent(:requests, :answer) =
        decided.single.reach as AnswersEvent; // cast-ok: the one reach here
    expect(
      [for (final r in requests) r.body],
      [for (final r in web.requests) r.body],
    );
    expect(
      answer,
      isA<ReplyToEvent>()
          .having((a) => a.respondsTo, 'respondsTo', admission)
          .having((a) => a.reply, 'reply', reply),
    );
    expect(airlock.log, [
      '1: allow answer with 2 [$teams as hart-bot, $teams as hart-bot]',
      '1: ran answer with 2 [$teams as hart-bot, $teams as hart-bot]',
    ]);
  });

  test(
    "every request's origin and sign-in must be granted, together",
    () async {
      final web = RecordedWeb();
      final airlock = LogAirlock()..answerAs = SignIn.parse('other-bot')!;
      final answer = await answerOf(
        replyWith(recordedReply(airlock, 'done')),
        start(airlock, [web], rules: {'$teams as $hart'}).at(1),
      );
      expect(answer, 'failed: not in the rules');
      expect(web.requests, isEmpty);
      expect(
        airlock.log.first,
        '1: deny answer with 1 [$teams as other-bot]: '
        'not in the rules',
      );
    },
  );

  test('a decision on an answer reads back from the logbook with every '
      'exact request', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [RecordedWeb()], rules: {'$teams as $hart'});
    final decided = <AirlockDecisionOnAction<int>>[];
    path.decisions.listen(decided.add);
    await answerOf(replyWith(recordedReply(airlock, 'a|b')), path.at(4));
    final written = decided.single.toJson((p) => p);
    final back = AirlockDecisionOnAction.fromJson(
      throughText(written),
      (json) => json is int ? json : null,
    );
    final AnswersEvent(:requests) =
        back.reach as AnswersEvent; // cast-ok: the one reach here
    expect(
      [for (final r in requests) r.body],
      [teamsMessageOf('a'), teamsMessageOf('b')],
    );
    expect(requests.first.signIn, hart);
    expect(requests.first.method, Method.post);
    expect(jsonEncode(back.toJson((p) => p)), jsonEncode(written));
  });

  test('a reply that is not a model reply of this trajectory is refused, for '
      'its own reason: nothing is built or sent, and the refusal is '
      'recorded with no requests', () async {
    final other = idOf('another trajectory');
    final cases = <(String, EntryId Function(LogAirlock), String)>[
      (
        'a reply that was refused',
        (a) => a.remember(
          jsonEncode(proposalRejectedToJson(askedTheModel(a), 'no')),
          kind: outcomeOfProposedActionKind,
        ),
        'holds no model reply',
      ),
      (
        'a result that did not run, though it holds text',
        (a) => a.remember(
          jsonEncode({
            'proposed': askedTheModel(a).hex,
            'result': {'kind': 'refused', 'output': 'done'},
          }),
          kind: outcomeOfProposedActionKind,
        ),
        'holds no model reply',
      ),
      (
        'not a result at all',
        (a) => a.remember('done', kind: outcomeOfProposedActionKind),
        'names no proposal',
      ),
      (
        'a reply to a proposal on another chain',
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
        // A read's result is {"kind":"text","text":…}, which reads as a reply.
        "a file read's text",
        (a) => recordedOutcome(
          a,
          recordedProposal(a, 'read', 'secret.txt'),
          encodeOutcome<ReadResult>(
            const Ran(ReadText('the secret file')),
            encodeReadResult,
          ),
        ),
        'asked no model',
      ),
      (
        "another trajectory's reply",
        (a) => recordedReply(a, 'done', on: other),
        'is on another chain',
      ),
      (
        'nothing recorded',
        (a) => EntryId.of(utf8.encode('never written')),
        'is not recorded',
      ),
    ];
    for (final (why, reply, said) in cases) {
      final web = RecordedWeb();
      final airlock = LogAirlock();
      final path = start(airlock, [web], rules: {'$teams as $hart'});
      final decided = <AirlockDecisionOnAction<int>>[];
      path.decisions.listen(decided.add);
      final answer = await answerOf(replyWith(reply(airlock)), path.at(1));
      expect(
        answer,
        allOf(startsWith('failed: '), contains(said)),
        reason: why,
      );
      expect(web.requests, isEmpty, reason: why);
      expect(airlock.builtFrom, isEmpty, reason: why);
      expect(airlock.decidedFor, isEmpty, reason: why);
      expect(
        decided.single,
        isA<AirlockDecisionOnAction<int>>()
            .having((d) => d.decision, 'decision', isA<Deny>())
            .having(
              (d) => (d.reach as AnswersEvent)
                  .requests, // cast-ok: the one reach here
              'requests',
              isEmpty,
            ),
        reason: why,
      );
    }
  });

  test('an event the module cannot answer is refused, and nothing is '
      'sent', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final answer = await answerOf(
      replyWith(
        recordedReply(airlock, 'done'),
        respondsTo: EntryId.of(utf8.encode('a join, not a message')),
      ),
      start(airlock, [web], rules: {'$teams as $hart'}).at(1),
    );
    expect(answer, allOf(startsWith('failed: '), contains('admits no event')));
    expect(web.requests, isEmpty);
    expect(airlock.decidedFor, isEmpty);
  });

  test('sending stops at the first part that fails, saying how far it got, '
      'and never retries', () async {
    final web = RecordedWeb(refuseAt: 2);
    final airlock = LogAirlock();
    final answer = await answerOf(
      replyWith(recordedReply(airlock, 'one|two|three')),
      start(airlock, [web], rules: {'$teams as $hart'}).at(1),
    );
    expect(answer, 'failed: sent 1 of 3: 403 throttled');
    expect(
      [for (final r in web.requests) r.body],
      [teamsMessageOf('one'), teamsMessageOf('two')],
    );
  });

  test('a part the web driver refuses to send stops the rest, in the '
      "driver's words", () async {
    final web = RecordedWeb(cannotSendAt: 2);
    final airlock = LogAirlock();
    final answer = await answerOf(
      replyWith(recordedReply(airlock, 'one|two|three')),
      start(airlock, [web], rules: {'$teams as $hart'}).at(1),
    );
    expect(answer, 'failed: sent 1 of 3: hart-bot is not held here');
    expect(web.requests, hasLength(2));
  });

  test('a trajectory open notice is built, decided and sent like a reply, '
      'reading nothing', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    expect(
      await answerOf(
        answerWith(const TrajectoryOpened()),
        start(airlock, [web], rules: {'$teams as $hart'}).at(0),
      ),
      '201 activity-1',
    );
    expect([for (final r in web.requests) r.body], [openCardBody]);
    expect(airlock.readOn, isEmpty);
  });

  test('nothing is sent when the decision cannot be recorded', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock(failWriting: FailWriting.decision);
    await expectLater(
      answerOf(
        replyWith(recordedReply(airlock, 'done')),
        start(airlock, [web], rules: {'$teams as $hart'}).at(1),
      ),
      throwsStateError,
    );
    expect(airlock.log, isEmpty);
    expect(web.requests, isEmpty);
  });

  test('a stopped trajectory builds nothing and sends nothing', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final path = start(airlock, [web], rules: {'$teams as $hart'})..stop();
    expect(
      await answerOf(replyWith(recordedReply(airlock, 'done')), path.at(1)),
      'failed: stopped',
    );
    expect(airlock.readOn, isEmpty);
    expect(airlock.builtFrom, isEmpty);
    expect(web.requests, isEmpty);
  });

  test('a machine with no web driver sends no answer', () async {
    final airlock = LogAirlock();
    expect(
      await answerOf(
        replyWith(recordedReply(airlock, 'done')),
        start(airlock, [MemoryFiles()], rules: {'$teams as $hart'}).at(1),
      ),
      'failed: this machine cannot run answer',
    );
  });
}
