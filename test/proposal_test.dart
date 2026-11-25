import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_model_vocabulary/is_model_vocabulary.dart';
import 'package:is_conversation_reply_vocabulary/is_conversation_reply_vocabulary.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Each method answers with its own name, so a test sees which one a
/// program reached.
final class _NamesEachMethod implements CarriesOutEachProgram {
  @override
  Future<Outcome<ReadResult>> readFile(RelativePath path) async =>
      const NothingRan('readFile');

  @override
  Future<Outcome<BytesReadResult>> readFileBytes(RelativePath path) async =>
      const NothingRan('readFileBytes');

  @override
  Future<Outcome<Wrote>> writeFile(FileText file) async =>
      const NothingRan('writeFile');

  @override
  Future<Outcome<ExecResult>> runExecutable(
    ProgramName program,
    Args args,
  ) async => NothingRan('runExecutable ${program.value}');

  @override
  Future<Outcome<List<WebResponse>>> makeWebRequests(
    List<ProposedRequest> requests,
  ) async => const NothingRan('makeWebRequests');

  @override
  Future<Outcome<WebResponse>> fetchFromWeb(WebFetch fetch) async =>
      const NothingRan('fetchFromWeb');

  @override
  Future<Outcome<ModelReply>> askTheModel(ModelCall call) async =>
      const NothingRan('askTheModel');

  @override
  Future<Outcome<List<PostedMessage>>> replyToOwnConversation(
    ReplyContent content,
  ) async => const NothingRan('replyToOwnConversation');
}

/// One input for every program, and the method that carries it out.
final _each =
    <
      ({
        String method,
        Future<Outcome<Object?>>? Function(CarriesOutEachProgram by) carry,
        String Function(PlaceInTrajectory at) proposal,
        Reach Function() reach,
      })
    >[
      _one(Program.read, RelativePath('a.dart'), 'readFile'),
      _one(Program.readBytes, RelativePath('a.docx'), 'readFileBytes'),
      _one(Program.write, FileText(RelativePath('a'), 'x'), 'writeFile'),
      _one(
        Executable.parse('git')!,
        const Args(['status']),
        'runExecutable git',
      ),
      _one(Program.makeWebRequests, [teamsPost('hi')], 'makeWebRequests'),
      _one(
        Program.fetch,
        WebFetch(teams, keep: BodyToKeep.text, signIn: hart),
        'fetchFromWeb',
      ),
      _one(
        Program.askTheModel,
        ModelCall(
          signIn: ModelSignInName.parse('nick-claude-team')!,
          model: ModelName.parse('claude-opus-5-5')!,
          request: EntryId.of(utf8.encode('the request')),
        ),
        'askTheModel',
      ),
      _one(
        Program.replyToOwnConversation,
        ReplyContent(text: ReplyText.parse('done')!),
        'replyToOwnConversation',
      ),
    ];

/// [program] on [input], kept typed together: the pair a tool would build.
({
  String method,
  Future<Outcome<Object?>>? Function(CarriesOutEachProgram by) carry,
  String Function(PlaceInTrajectory at) proposal,
  Reach Function() reach,
})
_one<I, O>(Program<I, O> program, I input, String method) => (
  method: method,
  carry: (by) => program.carriedOutBy(by, input),
  proposal: (at) => program.proposal(input, at: at),
  reach: () => program.reachOf(input),
);

void main() {
  test('each program is carried out by its own method', () async {
    final by = _NamesEachMethod();
    expect(
      [
        for (final p in _each)
          switch (await p.carry(by)) {
            NothingRan(:final why) => why,
            final other => '$other',
          },
      ],
      [for (final p in _each) p.method],
    );
  });

  test(
    'a proposal reads back as the same program on the same input, typed',
    () {
      final at = ProposedForAnIntent.at(1, 0, 2);
      for (final p in _each) {
        final written = p.proposal(at);
        final proposal = switch (ActionProposedByAgentLoop.read(written)) {
          final ActionProposedByAgentLoop proposal => proposal,
          Rejected(:final why) => fail('$written rejected: $why'),
        };
        expect(proposal.place, at);
        expect(
          proposal.open(
            <I, O>(program, input) => program.proposal(input, at: at),
          ),
          written,
        );
        expect(proposal.reach.runtimeType, p.reach().runtimeType);
      }
    },
  );

  test('an outcome reads back with the program that was proposed', () {
    final outcomes = <Outcome<Wrote>>[
      const Ran(Wrote(replaced: true)),
      const NothingRan('denied'),
      const StoppedPartway(why: 'disk full', done: null),
    ];
    for (final outcome in outcomes) {
      final json = jsonDecode(jsonEncode(Program.write.outcomeToJson(outcome)));
      expect(
        jsonEncode(
          Program.write.outcomeToJson(Program.write.outcomeFromJson(json)),
        ),
        jsonEncode(Program.write.outcomeToJson(outcome)),
      );
    }
    expect(
      () => Program.write.outcomeFromJson({'kind': 'maybe'}),
      throwsFormatException,
    );
  });

  test('what is not a proposal is rejected', () {
    final proposal = {
      'place': [1, 0, 0],
      'input': 'a.dart',
    };
    expect(
      [
        for (final request in <Object?>[
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
        ])
          _rejected(request is String ? request : jsonEncode(request)),
      ],
      [
        'not a proposal',
        'not a proposal',
        'not a program: delete',
        'not a program: start',
        'not a place',
        'not a place',
      ],
    );
  });

  test('a fetch carrying a body or headers is rejected, not stripped', () {
    final fetch = {
      'origin': '$teams',
      'path': '/x',
      'signIn': 'hart-bot',
      'keep': 'text',
    };
    expect(
      [
        for (final extra in [
          {'body': 'case words'},
          {'headers': <String, String>{}},
          {'keep': 'everything'},
          {'path': '//evil.example/x'},
          {'path': '/a/../b'},
        ])
          _rejected(
            jsonEncode({
              'place': [1, 0, 0],
              'program': 'fetch',
              'input': {...fetch, ...extra},
            }),
          ),
      ],
      [
        startsWith('input: unexpected (body)'),
        startsWith('input: unexpected (headers)'),
        startsWith('input.keep'),
        startsWith('input.path'),
        startsWith('input.path'),
      ],
    );
  });

  test('a GET, a header other than content-type, or no requests at all is '
      'rejected, naming the part', () {
    String propose(Object? input) => jsonEncode({
      'place': [1, 0, 0],
      'program': 'make-web-requests',
      'input': input,
    });
    final post = switch (encodeProposedRequest(teamsPost('hi'))) {
      final Map<String, Object?> json => json,
      _ => throw StateError('a request is written as an object'),
    };
    expect(
      [
        for (final input in <Object?>[
          [
            encodeProposedRequest(
              ProposedRequest(teams, path: conversation, signIn: hart),
            ),
          ],
          [
            encodeProposedRequest(
              teamsPost('hi', headers: {'x-note': 'the secret'}),
            ),
          ],
          [
            {
              ...post,
              'headers': {'authorization': 'Bearer x'},
            },
          ],
          <Object?>[],
          post,
          // A tool can't say what prefix it was granted, even a narrow one.
          [
            {...post, 'grantedPathPrefix': '/'},
          ],
        ])
          _rejected(propose(input)),
      ],
      [
        startsWith('input[0].method'),
        startsWith('input[0].headers'),
        startsWith('input[0].headers.authorization: carries a credential'),
        startsWith('input: no requests'),
        startsWith('input: not a list'),
        startsWith('input[0].grantedPathPrefix'),
      ],
    );
    expect(
      ActionProposedByAgentLoop.read(
        propose([
          encodeProposedRequest(
            teamsPost('hi', headers: {'Content-Type': 'application/json'}),
          ),
        ]),
      ),
      isA<ActionProposedByAgentLoop>(),
      reason: 'content-type may be sent in any case',
    );
  });

  test('a proposal to make web requests read back says exactly what it would '
      'send', () {
    final proposal = ActionProposedByAgentLoop.read(
      Program.makeWebRequests.proposal([
        teamsPost('open'),
      ], at: ProposedForTheReply.at(0, 1)),
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

  test('a model call is proposed as `model`, and read back strictly', () {
    final request = EntryId.of(utf8.encode('the request'));
    final input = {
      'signIn': 'nick-claude-team',
      'model': 'claude-opus-5-5',
      'request': request.hex,
    };
    String wire(Object? input) => jsonEncode({
      'program': 'model',
      'place': [1, 'model-call'],
      'input': input,
    });
    expect(switch (ActionProposedByAgentLoop.read(wire(input))) {
      ActionProposedByAgentLoop(program: AskTheModel()) => 'a model call',
      _ => 'not one',
    }, 'a model call');
    for (final bad in <Object?>[
      {...input, 'request': 'nope'},
      {...input, 'signIn': 'Nick Team'},
      {...input, 'body': 'words of its own'},
      {'signIn': 'nick-claude-team', 'model': 'claude-opus-5-5'},
    ]) {
      expect(
        ActionProposedByAgentLoop.read(wire(bad)),
        isA<Rejected>(),
        reason: '$bad',
      );
    }
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

  test('names are checked once, at the boundary', () {
    expect(
      ['', ' ', 'git status', 'git\tlog'].map(Executable.parse),
      everyElement(isNull),
    );
    expect(Executable.parse('git'), Executable.parse('git'));
    expect(Executable.parse('git'), isNot(Executable.parse('dart')));
  });
}

/// Why [body] is not a proposal; fails the test when it is one.
String _rejected(String body) => switch (ActionProposedByAgentLoop.read(body)) {
  Rejected(:final why) => why,
  ActionProposedByAgentLoop() => fail('read as a proposal: $body'),
};
