import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show
        FetchingWeb,
        LogAirlock,
        MemoryFiles,
        LogbookLink,
        RecordedPrograms,
        RecordedWeb,
        answerOf,
        hart,
        loopCrux,
        makeWebRequests,
        requestsToConversation,
        start,
        teams,
        teamsMessageOf,
        teamsPost,
        writeAndFormat;

void main() {
  test(
    'an action proposed through the logbook is decided, written to it and '
    'carried out as in the airlock, and its continuation runs in the loop',
    () async {
      final airlock = LogAirlock();
      final files = MemoryFiles();
      final link = LogbookLink(
        start(airlock, [files, RecordedPrograms()]),
        airlock,
      );
      expect(
        await answerOf(writeAndFormat('a.dart'), loopCrux(link, turn: 3)),
        'Formatted 1 file',
      );
      expect(files.files, {'a.dart': 'void main() {}'});
      expect(airlock.log, [
        '0: allow write a.dart',
        '0: ran write a.dart',
        '1: allow dart format a.dart',
        '1: ran dart format a.dart',
      ]);
      expect(link.rejected, isEmpty);
      expect(link.places, [
        ProposedForAnIntent.at(3, 0, 0),
        ProposedForAnIntent.at(3, 0, 1),
      ]);
      expect(link.programs, [
        Program.write,
        isA<Executable>().having((e) => e.name, 'name', 'dart'),
      ]);
    },
  );

  test("what an action returned reaches the loop from the logbook, in full, "
      'and '
      'its entries name the proposal', () async {
    final airlock = LogAirlock();
    final files = MemoryFiles()..files['a.dart'] = 'the text';
    final path = start(airlock, [files]);
    final link = LogbookLink(path, airlock);
    final decisions = <AirlockDecisionOnAction<int>>[];
    final results = <AirlockDecisionOnAction<int>>[];
    path.decisions.listen(decisions.add);
    path.results.listen((r) => results.add(r.decision));
    expect(
      await answerOf(
        Program.read.runOrFail(
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

  test("a file's exact bytes reach the loop from the logbook, and the decision "
      'names the bytes read', () async {
    final airlock = LogAirlock();
    final files = MemoryFiles()..files['report.docx'] = 'PK zip';
    final path = start(airlock, [files]);
    final link = LogbookLink(path, airlock);
    final decisions = <AirlockDecisionOnAction<int>>[];
    path.decisions.listen(decisions.add);
    expect(
      await answerOf(
        Program.readBytes.runOrFail(
          RelativePath('report.docx'),
          then: (read) => Done(switch (read) {
            ReadBytes(:final bytes) => utf8.decode(bytes),
            ReadMissing() => 'missing',
          }),
        ),
        loopCrux(link),
      ),
      'PK zip',
    );
    expect(link.programs, [Program.readBytes]);
    expect(
      decisions.single.reach,
      isA<Reads>().having((r) => r.as, 'as', ReadsAs.bytes),
    );
  });

  test('a fetch goes as a GET with no body or headers, keeps what it asks, '
      'and its bytes reach the loop from the logbook', () async {
    final web = FetchingWeb();
    final airlock = LogAirlock();
    final graph = Origin.parse('https://graph.microsoft.com')!;
    final path = start(airlock, [web], rules: {'fetch $graph as $hart'});
    final answer = await answerOf(
      Program.fetch.runOrFail(
        WebFetch(
          graph,
          path: WebPath.parse('/v1.0/drives/d/items/i/content')!,
          signIn: hart,
          keep: BodyToKeep.bytes,
        ),
        then: (response) => Done(switch (response.body) {
          BytesBody(:final bytes) => utf8.decode(bytes),
          _ => 'no bytes',
        }),
      ),
      loopCrux(LogbookLink(path, airlock)),
    );
    expect(answer, 'PK zip');
    expect(web.requests.single.grantedPathPrefix.value, '/');
    final sent = web.requests.single.proposed;
    expect(sent.method, Method.get);
    expect(sent.path.value, '/v1.0/drives/d/items/i/content');
    expect(sent.signIn, hart);
    expect(sent.body, isNull);
    expect(sent.headers, isEmpty);
    expect(sent.keep, BodyToKeep.bytes);
  });

  test('a fetch allowed without its granted prefix is refused, and nothing '
      'is fetched', () async {
    final web = FetchingWeb();
    final airlock = LogAirlock(grantsPrefixes: []);
    final graph = Origin.parse('https://graph.microsoft.com')!;
    final path = start(airlock, [web], rules: {'fetch $graph as $hart'});
    expect(
      await answerOf(
        Program.fetch.runOrFail(
          WebFetch(graph, signIn: hart, keep: BodyToKeep.text),
          then: (_) => const Done('fetched'),
        ),
        loopCrux(LogbookLink(path, airlock)),
      ),
      'failed: allowed with 0 granted path prefixes for 1 requests',
    );
    expect(web.requests, isEmpty);
  });

  test(
    'a fetch is not granted by a grant to make requests to the same site',
    () async {
      final web = FetchingWeb();
      final airlock = LogAirlock();
      final path = start(airlock, [web], rules: {requestsToConversation});
      expect(
        await answerOf(
          Program.fetch.runOrFail(
            WebFetch(teams, signIn: hart, keep: BodyToKeep.text),
            then: (_) => const Done('fetched'),
          ),
          loopCrux(LogbookLink(path, airlock)),
        ),
        'failed: not in the rules',
      );
      expect(web.requests, isEmpty);
    },
  );

  test('requests proposed through the logbook are decided and sent exactly '
      'as the tool built them', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final path = start(airlock, [web], rules: {requestsToConversation});
    final link = LogbookLink(path, airlock);
    expect(
      await answerOf(makeWebRequests([teamsPost('done')]), loopCrux(link)),
      '201 activity-1',
    );
    expect(link.programs, [Program.makeWebRequests]);
    expect(web.requests.single.proposed.body, teamsMessageOf('done'));
    expect(web.requests.single.proposed.headers, {
      'content-type': 'application/json',
    });
  });

  test('a refusal comes back through the logbook in its own words', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles()], rules: {'read'});
    expect(
      await answerOf(
        writeAndFormat('a.dart'),
        loopCrux(LogbookLink(path, airlock)),
      ),
      'failed: not in the rules',
    );
  });

  test('a fetch carrying a body or headers is rejected at the boundary, not '
      'stripped', () async {
    final airlock = LogAirlock();
    final link = LogbookLink(start(airlock, [FetchingWeb()]), airlock);
    final fetch = {
      'origin': '$teams',
      'path': '/x',
      'signIn': 'hart-bot',
      'keep': 'text',
    };
    for (final extra in [
      {'body': 'case words'},
      {'headers': <String, String>{}},
      {'keep': 'everything'},
      {'path': '//evil.example/x'},
      {'path': '/a/../b'},
    ]) {
      await link.proposeAsIs({
        'place': [1, 0, 0],
        'program': 'fetch',
        'input': {...fetch, ...extra},
      });
    }
    expect(link.rejected, [
      startsWith('input: unexpected (body)'),
      startsWith('input: unexpected (headers)'),
      startsWith('input.keep'),
      startsWith('input.path'),
      startsWith('input.path'),
    ]);
    expect(airlock.log, isEmpty);
  });

  test('a proposal to make web requests read back says exactly what it would '
      'send', () {
    final proposal = ActionProposedByAgentLoop.read(
      jsonEncode({
        'place': [0, 'reply', 1],
        'program': 'make-web-requests',
        'input': [encodeProposedRequest(teamsPost('open'))],
      }),
    );
    expect(
      proposal,
      isA<ActionProposedByAgentLoop>().having(
        (p) => p.reach,
        'reach',
        isA<MakesWebRequests>().having(
          (r) => r.requests.single.body,
          'body',
          teamsMessageOf('open'),
        ),
      ),
    );
  });

  test('what is not a proposal is rejected', () async {
    final airlock = LogAirlock();
    final link = LogbookLink(start(airlock, [MemoryFiles()]), airlock);
    final proposal = {
      'place': [1, 0, 0],
      'input': 'a.dart',
    };
    for (final request in [
      null,
      'read a.dart',
      {...proposal, 'program': 'delete'},
      {...proposal, 'program': 'start'},
      {...proposal, 'program': 'read', 'place': 'first'},
      {
        ...proposal,
        'program': 'read',
        'place': [1, 0],
      },
    ]) {
      await link.proposeAsIs(request);
    }
    expect(link.rejected, [
      'not a proposal',
      'not a proposal',
      'not a program: delete',
      'not a program: start',
      'not a place',
      'not a place',
    ]);
    expect(airlock.log, isEmpty);
  });

  test('an answer that is no outcome ends the call', () async {
    final airlock = LogAirlock();
    final link = LogbookLink(start(airlock, [MemoryFiles()]), airlock)
      ..answerWith = (_, proposed) => jsonEncode({
        'proposed': proposed.hex,
        'result': {'kind': 'maybe'},
      });
    await expectLater(
      answerOf(writeAndFormat('a.dart'), loopCrux(link)),
      throwsFormatException,
    );
  });

  test('an outcome that names another proposal ends the call', () async {
    final airlock = LogAirlock();
    final other = EntryId.of(utf8.encode('another proposal'));
    final link = LogbookLink(start(airlock, [MemoryFiles()]), airlock)
      ..answerWith = (body, _) => body.replaceAll(
        readOutcomeOfProposedAction(body)!.proposed.hex,
        other.hex,
      );
    await expectLater(
      answerOf(writeAndFormat('a.dart'), loopCrux(link)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('names $other'),
        ),
      ),
    );
  });

  test('a place is the model call, an action of an intent, or an action of '
      'the reply, read back strictly', () {
    final places = [
      ProposedForTheModelCall.at(2),
      ProposedForAnIntent.at(2, 1, 5),
      ProposedForTheReply.at(2, 1),
    ];
    expect(
      [for (final p in places) p.toJson()],
      [
        [2, 'model-call'],
        [2, 1, 5],
        [2, 'reply', 1],
      ],
    );
    for (final place in places) {
      expect(
        PlaceInTrajectory.parse(jsonDecode(jsonEncode(place.toJson()))),
        place,
      );
    }
    for (final json in [
      null,
      1,
      'first',
      [1],
      [1, 2],
      [1, 2, 3, 4],
      [1.0, 2, 3],
      [-1, 0, 0],
      [0, -1, 0],
      [0, 0, -1],
      [-1, 'model-call'],
      [0, 'reply'],
      [0, 'reply', -1],
      [0, 'model-call', 0],
      [0, 'open-card'],
      [0, 'modelCall'],
      ['1', '2', '3'],
    ]) {
      expect(PlaceInTrajectory.parse(json), isNull, reason: '$json');
    }
    expect(() => ProposedForAnIntent.at(0, -1, 0), throwsArgumentError);
    expect(() => ProposedForTheModelCall.at(-1), throwsArgumentError);
    expect(() => ProposedForTheReply.at(0, -1), throwsArgumentError);
    expect(
      ProposedForAnIntent.at(1, 0, 0),
      isNot(ProposedForAnIntent.at(1, 1, 0)),
    );
    expect(ProposedForTheReply.at(1, 0), isNot(ProposedForTheReply.at(1, 1)));
    expect(ProposedForTheModelCall.at(1), isNot(ProposedForTheModelCall.at(2)));
  });

  test('within a turn the model call comes first, then each intent, then the '
      "reply's actions", () {
    final inOrder = <PlaceInTrajectory>[
      ProposedForTheModelCall.at(1),
      ProposedForAnIntent.at(1, 0, 0),
      ProposedForAnIntent.at(1, 0, 9),
      ProposedForAnIntent.at(1, 1, 0),
      ProposedForTheReply.at(1, 0),
      ProposedForTheReply.at(1, 1),
      ProposedForTheModelCall.at(2),
    ];
    expect(inOrder.reversed.toList()..sort(), inOrder);
  });

  test('two intents running at once each keep their own places', () async {
    final airlock = LogAirlock();
    final link = LogbookLink(
      start(airlock, [MemoryFiles(), RecordedPrograms()]),
      airlock,
    );
    Result<String> write(String name) => Program.write.runOrFail(
      FileText(RelativePath(name), ''),
      then: (_) => Done(name),
    );
    // Intent 1 starts first and takes two actions; intent 0 takes one.
    final second = answerOf(
      writeAndFormat('b.dart'),
      Crux.forIntent(link, turn: 1, intent: 1),
    );
    final first = answerOf(
      write('a.dart'),
      Crux.forIntent(link, turn: 1, intent: 0),
    );
    await Future.wait([first, second]);
    expect(link.places.toList()..sort(), [
      ProposedForAnIntent.at(1, 0, 0),
      ProposedForAnIntent.at(1, 1, 0),
      ProposedForAnIntent.at(1, 1, 1),
    ]);
  });

  test('a crux for the model call carries one action and refuses a second '
      'before writing it', () async {
    final airlock = LogAirlock();
    final link = LogbookLink(
      start(airlock, [MemoryFiles(), RecordedPrograms()]),
      airlock,
    );
    await expectLater(
      answerOf(writeAndFormat('a.dart'), Crux.forTheModelCall(link, turn: 1)),
      throwsStateError,
    );
    expect(link.places, [ProposedForTheModelCall.at(1)]);
  });

  test("a reply's actions are numbered: build the message, then send what was "
      'built', () async {
    final airlock = LogAirlock();
    final link = LogbookLink(
      start(airlock, [MemoryFiles(), RecordedPrograms()]),
      airlock,
    );
    await answerOf(writeAndFormat('a.dart'), Crux.forTheReply(link, turn: 4));
    expect(link.places, [
      ProposedForTheReply.at(4, 0),
      ProposedForTheReply.at(4, 1),
    ]);
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
      '{"proposed":"${id.hex}","result":{"kind":"nothingRan","why":"why"}}',
    );
    final back = readOutcomeOfProposedAction(jsonEncode(refused))!;
    expect(back.proposed, id);
    expect(back.result, {'kind': 'nothingRan', 'why': 'why'});
    for (final json in [
      null,
      'a line a person reads',
      {'result': null},
      {'proposed': 'nope', 'result': null},
      {'proposed': id.hex},
      {'proposed': id.hex, 'result': null, 'outcome': null},
    ]) {
      expect(
        readOutcomeOfProposedAction(jsonEncode(json)),
        isNull,
        reason: '$json',
      );
    }
  });
}
