import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show
        LogAirlock,
        MemoryFiles,
        RecordedPrograms,
        RecordedWeb,
        answerOf,
        hart,
        recordedReply,
        start,
        teams,
        teamsMessageOf,
        webRequest,
        writeAndFormat;

/// A trajectory's chain and the airlock's, in memory: each proposal the
/// loop writes goes through `jsonEncode` and back, as the logbook would keep
/// it, and is named by the id the logbook gives it, as the loop's write
/// returns it, never a hash of the body alone; the airlock service considers
/// it on [path], and the loop is handed the result that names it, through
/// `jsonEncode` and back, as loop_launcher would hand it.
/// Places are ints. Keeps why each rejected entry was rejected.
final class RecordedLink implements ProposesActionsThroughTheRecord {
  RecordedLink(this.path, this.airlock);

  final Trajectory<Set<String>, int> path;
  final LogAirlock airlock;
  final rejected = <String>[];

  /// The program of each proposal read back, in order.
  final programs = <Program<Object?, Object?>>[];

  /// What loop_launcher would hand the loop, when a test wants another
  /// answer.
  Object? Function(Object? outcome) answerWith = (outcome) => outcome;

  @override
  Future<Object?> propose(Object? proposal) async {
    final body = jsonEncode(proposal);
    final proposed = airlock.remember(
      body,
      kind: ActionProposedByAgentLoop.kind,
    );
    switch (ActionProposedByAgentLoop.read(jsonDecode(body))) {
      case Rejected(:final why):
        rejected.add(why);
        airlock.results[proposed] = proposalRejectedToJson(proposed, why);
      case final ActionProposedByAgentLoop proposal:
        programs.add(proposal.program);
        switch (proposal.place) {
          case final int place:
            await path.consider(proposal, place, proposed: proposed);
          default:
            rejected.add('not a place');
            airlock.results[proposed] = proposalRejectedToJson(
              proposed,
              'not a place',
            );
        }
    }
    final answer = readOutcomeOfProposedAction(
      jsonDecode(jsonEncode(airlock.results[proposed])),
    )!;
    expect(answer.proposed, proposed);
    return answerWith(answer.result);
  }
}

/// The agent loop's crux at [place] on [link]'s path.
Crux loopCrux(RecordedLink link, {int place = 1}) =>
    Crux.through(link, place: place);

void main() {
  test(
    'an action proposed through the record is decided, recorded and '
    'carried out as in the airlock, and its continuation runs in the loop',
    () async {
      final airlock = LogAirlock();
      final files = MemoryFiles();
      final link = RecordedLink(
        start(airlock, [files, RecordedPrograms()]),
        airlock,
      );
      expect(
        await answerOf(writeAndFormat('a.dart'), loopCrux(link, place: 3)),
        'Formatted 1 file',
      );
      expect(files.files, {'a.dart': 'void main() {}'});
      expect(airlock.log, [
        '3: allow write a.dart',
        '3: ran write a.dart',
        '3: allow dart format a.dart',
        '3: ran dart format a.dart',
      ]);
      expect(link.rejected, isEmpty);
      expect(link.programs, [
        Program.write,
        isA<Executable>().having((e) => e.name, 'name', 'dart'),
      ]);
    },
  );

  test("what an action returned reaches the loop from the record, in full, and "
      'its entries name the proposal', () async {
    final airlock = LogAirlock();
    final files = MemoryFiles()..files['a.dart'] = 'the text';
    final path = start(airlock, [files]);
    final link = RecordedLink(path, airlock);
    final decisions = <AirlockDecisionOnAction<int>>[];
    final results = <AirlockDecisionOnAction<int>>[];
    path.decisions.listen(decisions.add);
    path.results.listen((r) => results.add(r.decision));
    expect(
      await answerOf(
        Program.read.runOrRefusal(
          RelativePath('a.dart'),
          then: (read) => Done(switch (read) {
            ReadText(:final text) => text,
            _ => 'not read',
          }),
        ),
        loopCrux(link),
      ),
      'the text',
    );
    expect(decisions, hasLength(1));
    final proposed = decisions.single.proposed;
    expect(proposed, isNotNull);
    expect(results, [same(decisions.single)]);
    expect(airlock.results.keys, [proposed]);
    expect(jsonEncode(airlock.results[proposed]), contains('the text'));
  });

  test(
    'a web request proposed through the record sends a recorded reply',
    () async {
      final web = RecordedWeb();
      final airlock = LogAirlock();
      final reply = recordedReply(airlock, 'done');
      final path = start(airlock, [web], rules: {'$teams as $hart'});
      expect(
        await answerOf(
          webRequest(teams, hart, drawnFrom: reply),
          loopCrux(RecordedLink(path, airlock)),
        ),
        '201 activity-1',
      );
      expect(web.requests.single.body, teamsMessageOf('done'));
    },
  );

  test('a refusal comes back through the record in its own words', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles()], rules: {'read'});
    expect(
      await answerOf(
        writeAndFormat('a.dart'),
        loopCrux(RecordedLink(path, airlock)),
      ),
      'failed: not in the rules',
    );
  });

  test(
    'an action proposed in-process has no entry in the record to answer',
    () async {
      final airlock = LogAirlock();
      final path = start(airlock, [MemoryFiles()]);
      final results = <AirlockDecisionOnAction<int>>[];
      path.results.listen((r) => results.add(r.decision));
      await answerOf(writeAndFormat('a.dart'), path.at(1));
      expect(results, hasLength(2));
      expect(results.map((d) => d.proposed), everyElement(isNull));
      expect(airlock.results, isEmpty);
    },
  );

  test('input that its type would not accept is rejected at the boundary, '
      'naming the field, and answered refused', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [RecordedWeb()], rules: {'$teams as $hart'});
    final link = RecordedLink(path, airlock);
    final proposal = {'place': 1, 'program': 'web'};
    Map<String, Object?> requestWith(Map<String, Object?> change) => {
      'origin': '$teams',
      'method': 'post',
      'path': '/v3/conversations/c/activities',
      'signIn': 'hart-bot',
      'headers': <String, String>{},
      'body': '{"type":"message","text":"done"}',
      'projection': 'teams-message-from-model-reply',
      'drawnFrom': '0' * 64,
      ...change,
    };
    final answers = [
      for (final change in [
        {'path': '//evil.example/x'},
        {
          'headers': {'Authorization': 'Bearer x'},
        },
        {'projection': 'teams-reply'},
        {'drawnFrom': 'not an id'},
        {'body': null},
      ])
        await link.propose({...proposal, 'input': requestWith(change)}),
    ];
    expect(link.rejected, hasLength(5));
    expect(link.rejected[0], startsWith('input.path'));
    expect(link.rejected[1], startsWith('input.headers'));
    expect(link.rejected[2], startsWith('input.projection'));
    expect(link.rejected[3], startsWith('input.drawnFrom'));
    expect(link.rejected[4], startsWith('input.body'));
    expect(
      answers.map(
        (a) => decodeOutcome<Never>(a, (_, _) => throw StateError('ran')),
      ),
      everyElement(isA<Refused>()),
    );
    expect(airlock.log, isEmpty);
  });

  test('what is not a proposal is rejected', () async {
    final airlock = LogAirlock();
    final link = RecordedLink(start(airlock, [MemoryFiles()]), airlock);
    final proposal = {'place': 1, 'input': 'a.dart'};
    for (final request in [
      null,
      'read a.dart',
      {...proposal, 'program': 'delete'},
      {...proposal, 'program': 'start'},
      {...proposal, 'program': 'read', 'place': 'first'},
    ]) {
      await link.propose(request);
    }
    expect(link.rejected, [
      'not a proposal',
      'not a proposal',
      'not a program: delete',
      'not a program: start',
      'not a place',
    ]);
    expect(airlock.log, isEmpty);
  });

  test('an answer that is no outcome ends the call', () async {
    final airlock = LogAirlock();
    final link = RecordedLink(start(airlock, [MemoryFiles()]), airlock)
      ..answerWith = (_) => {'kind': 'maybe'};
    await expectLater(
      answerOf(writeAndFormat('a.dart'), loopCrux(link)),
      throwsFormatException,
    );
  });

  test('the logbook kinds name what they hold', () {
    expect(ActionProposedByAgentLoop.kind, 'action-proposed-by-agent-loop');
    expect(AirlockDecisionOnAction.kind, 'airlock-decision-on-action');
    expect(outcomeOfProposedActionKind, 'outcome-of-proposed-action');
  });

  test('a result reads back only with the proposal it answers, exactly', () {
    final id = EntryId.of(utf8.encode('proposed'));
    final refused = proposalRejectedToJson(id, 'why');
    expect(
      jsonEncode(refused),
      '{"proposed":"${id.hex}","result":{"kind":"refused","why":"why"}}',
    );
    final back = readOutcomeOfProposedAction(jsonDecode(jsonEncode(refused)))!;
    expect(back.proposed, id);
    expect(back.result, {'kind': 'refused', 'why': 'why'});
    for (final json in [
      null,
      'a line a person reads',
      {'result': null},
      {'proposed': 'nope', 'result': null},
      {'proposed': id.hex},
      {'proposed': id.hex, 'result': null, 'outcome': null},
    ]) {
      expect(readOutcomeOfProposedAction(json), isNull, reason: '$json');
    }
  });
}
