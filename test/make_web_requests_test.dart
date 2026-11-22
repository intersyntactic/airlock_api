import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show
        FailWriting,
        LogAirlock,
        MemoryFiles,
        LogbookLink,
        RecordedWeb,
        answerOf,
        conversation,
        hart,
        makeWebRequests,
        requestsToConversation,
        start,
        teams,
        teamsMessageOf,
        teamsPost,
        throughLogbook;

/// [json] as the logbook would hold it and give it back: JSON text.
JsonObject throughText(Object? json) => JsonObject.decode(jsonEncode(json));

void main() {
  test('the exact requests a tool built are decided together, then sent in '
      'order', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final path = start(airlock, [web], rules: {requestsToConversation});
    final decided = <AirlockDecisionOnAction<int>>[];
    path.decisions.listen(decided.add);
    final requests = [teamsPost('Clause 4 —'), teamsPost('rent is due.')];
    expect(
      await answerOf(
        makeWebRequests(requests),
        throughLogbook(path, airlock, turn: 1),
      ),
      '201 activity-1, 201 activity-2',
    );
    expect(
      [for (final r in web.requests) r.body],
      [teamsMessageOf('Clause 4 —'), teamsMessageOf('rent is due.')],
    );
    final MakesWebRequests(requests: held) =
        decided.single.reach as MakesWebRequests; // cast-ok: the one reach here
    expect([for (final r in held) r.body], [for (final r in requests) r.body]);
    expect(airlock.log, [
      '1: allow make-web-requests 2 [$teams$conversation as hart-bot, '
          '$teams$conversation as hart-bot]',
      '1: ran make-web-requests 2 [$teams$conversation as hart-bot, '
          '$teams$conversation as hart-bot]',
    ]);
  });

  test('a request outside the path the rules grant is refused, and nothing '
      'is sent', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final other = WebPath.parse('/v3/conversations/other/activities')!;
    expect(
      await answerOf(
        makeWebRequests([teamsPost('hi', path: other)]),
        throughLogbook(
          start(airlock, [web], rules: {requestsToConversation}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: not in the rules',
    );
    expect(web.requests, isEmpty);
  });

  test("a request's sign-in must be granted with its path", () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    expect(
      await answerOf(
        makeWebRequests([teamsPost('hi', signIn: SignIn.parse('other-bot')!)]),
        throughLogbook(
          start(airlock, [web], rules: {requestsToConversation}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: not in the rules',
    );
    expect(web.requests, isEmpty);
  });

  test('every request must be granted, or none is sent', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final other = WebPath.parse('/v3/conversations/other/activities')!;
    expect(
      await answerOf(
        makeWebRequests([teamsPost('first'), teamsPost('second', path: other)]),
        throughLogbook(
          start(airlock, [web], rules: {requestsToConversation}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: not in the rules',
    );
    expect(web.requests, isEmpty);
  });

  test('a decision to make web requests reads back from the logbook with every exact '
      'request', () async {
    final airlock = LogAirlock();
    final path = start(
      airlock,
      [RecordedWeb()],
      rules: {requestsToConversation},
    );
    final decided = <AirlockDecisionOnAction<int>>[];
    path.decisions.listen(decided.add);
    await answerOf(
      makeWebRequests([teamsPost('a'), teamsPost('b')]),
      throughLogbook(path, airlock, turn: 4),
    );
    final written = decided.single.toJson((p) => p);
    final back = AirlockDecisionOnAction.fromJson(
      throughText(written),
      (json) => json is int ? json : null,
    );
    final MakesWebRequests(:requests) =
        back.reach as MakesWebRequests; // cast-ok: the one reach here
    expect(
      [for (final r in requests) r.body],
      [teamsMessageOf('a'), teamsMessageOf('b')],
    );
    expect(requests.first.signIn, hart);
    expect(requests.first.method, Method.post);
    expect(jsonEncode(back.toJson((p) => p)), jsonEncode(written));
  });

  test('making requests stops at the first one that fails, saying how far it '
      'got, and never retries', () async {
    final web = RecordedWeb(refuseAt: 2);
    final airlock = LogAirlock();
    expect(
      await answerOf(
        makeWebRequests([
          teamsPost('one'),
          teamsPost('two'),
          teamsPost('three'),
        ]),
        throughLogbook(
          start(airlock, [web], rules: {requestsToConversation}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: sent 1 of 3: 403 throttled',
    );
    expect(
      [for (final r in web.requests) r.body],
      [teamsMessageOf('one'), teamsMessageOf('two')],
    );
  });

  test('a request the web driver refuses to send stops the rest, in the '
      "driver's words", () async {
    final web = RecordedWeb(cannotSendAt: 2);
    final airlock = LogAirlock();
    expect(
      await answerOf(
        makeWebRequests([
          teamsPost('one'),
          teamsPost('two'),
          teamsPost('three'),
        ]),
        throughLogbook(
          start(airlock, [web], rules: {requestsToConversation}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: sent 1 of 3: hart-bot is not held here',
    );
    expect(web.requests, hasLength(2));
  });

  test('nothing is sent when the decision cannot be written', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock(failWriting: FailWriting.decision);
    await expectLater(
      answerOf(
        makeWebRequests([teamsPost('done')]),
        throughLogbook(
          start(airlock, [web], rules: {requestsToConversation}),
          airlock,
          turn: 1,
        ),
      ),
      throwsStateError,
    );
    expect(airlock.log, isEmpty);
    expect(web.requests, isEmpty);
  });

  test('a stopped trajectory sends nothing', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final path = start(airlock, [web], rules: {requestsToConversation})..stop();
    expect(
      await answerOf(
        makeWebRequests([teamsPost('done')]),
        throughLogbook(path, airlock, turn: 1),
      ),
      'failed: stopped',
    );
    expect(web.requests, isEmpty);
  });

  test('a machine with no web driver sends nothing', () async {
    final airlock = LogAirlock();
    expect(
      await answerOf(
        makeWebRequests([teamsPost('done')]),
        throughLogbook(
          start(airlock, [MemoryFiles()], rules: {requestsToConversation}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: this machine cannot run make-web-requests',
    );
  });

  test('a GET, a header other than content-type, or no requests at all is '
      'rejected at the boundary, naming the part', () async {
    final airlock = LogAirlock();
    final path = start(
      airlock,
      [RecordedWeb()],
      rules: {requestsToConversation},
    );
    final link = LogbookLink(path, airlock);
    Future<Object?> propose(Object? input) => link.proposeAsIs({
      'place': [1, 0, 0],
      'program': 'make-web-requests',
      'input': input,
    });
    final post = teamsPost('hi');
    final answers = [
      await propose([
        encodeRequest(Request(teams, path: conversation, signIn: hart)),
      ]),
      await propose([
        encodeRequest(teamsPost('hi', headers: {'x-note': 'the secret'})),
      ]),
      await propose([
        {
          ...encodeRequest(post)!
              as Map<
                String,
                Object?
              >, // cast-ok: encodeRequest writes an object
          'headers': {'authorization': 'Bearer x'},
        },
      ]),
      await propose(<Object?>[]),
      await propose(encodeRequest(post)),
      // A tool can't say what prefix it was granted, even a narrow one.
      await propose([
        encodeRequest(
          Request(
            teams,
            method: Method.post,
            path: conversation,
            signIn: hart,
            grantedPathPrefix: PathPrefix.parse('/')!,
          ),
        ),
      ]),
    ];
    expect(link.rejected, [
      startsWith('input[0].method'),
      startsWith('input[0].headers'),
      startsWith('input[0].headers.authorization: carries a credential'),
      startsWith('input: no requests'),
      startsWith('input: not a list'),
      startsWith('input[0].grantedPathPrefix'),
    ]);
    expect(
      answers.map(
        (a) => decodeOutcome<Never>(a, (_, _) => throw StateError('ran')),
      ),
      everyElement(isA<Refused>()),
    );
    expect(airlock.log, isEmpty);
  });

  test('content-type may be sent in any case', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final path = start(airlock, [web], rules: {requestsToConversation});
    final link = LogbookLink(path, airlock);
    await link.proposeAsIs({
      'place': [1, 0, 0],
      'program': 'make-web-requests',
      'input': [
        encodeRequest(
          teamsPost('hi', headers: {'Content-Type': 'application/json'}),
        ),
      ],
    });
    expect(link.rejected, isEmpty);
    expect(web.requests, hasLength(1));
  });
}
