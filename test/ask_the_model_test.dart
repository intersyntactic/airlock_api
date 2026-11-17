import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'contract_test.dart' show LogAirlock, answerOf, idOf, start;

/// Asks nothing: keeps each call it was given, streams the reply in two
/// pieces, and answers with it whole.
final class RecordedModel implements AsksTheModel {
  final calls = <List<String>>[];

  @override
  Future<Outcome<ModelReply>> askTheModel(
    ModelSignInName signIn,
    ModelName model,
    String systemPrompt,
    String request, {
    required Report report,
  }) async {
    calls.add([signIn.name, model.value, systemPrompt, request]);
    report(const ReplyArriving('Clause 4 '));
    report(const ReplyArriving('says rent is due monthly.'));
    return const Ran(ModelReply('Clause 4 says rent is due monthly.'));
  }
}

final teamLogin = ModelSignInName.parse('nick-claude-team')!;
final opus = ModelName.parse('claude-opus-5-5')!;
const system = ['You are reviewing a case file.'];
const asked = ['Turn 1: what does clause 4 say?\n', 'Answer briefly.'];

/// [texts] recorded as piece entries in [airlock]'s logbook, on [on]'s
/// chain, and the [RecordedText] naming them.
RecordedText recordedText(
  LogAirlock airlock,
  List<String> texts, {
  TrajectoryId? on,
  String? sha256Of,
}) => RecordedText(
  pieces: [
    for (final text in texts)
      airlock.remember(jsonEncode(ModelRequestPiece(text).toJson()), on: on),
  ],
  sha256: ObjectId.of(utf8.encode(sha256Of ?? texts.join())),
);

/// A model request recorded in [airlock]'s logbook, and its entry.
EntryId recordedRequest(
  LogAirlock airlock, {
  RecordedText? systemPrompt,
  RecordedText? request,
  TrajectoryId? on,
}) => airlock.remember(
  jsonEncode(
    ModelRequest(
      systemPrompt: systemPrompt ?? recordedText(airlock, system),
      request: request ?? recordedText(airlock, asked),
    ).toJson(),
  ),
  on: on,
);

Result<String> ask(EntryId request) => Program.askTheModel.runOrRefusal(
  ModelCall(signIn: teamLogin, model: opus, request: request),
  then: (reply) => Done(reply.text),
);

void main() {
  const rules = {'model as nick-claude-team'};

  test('the model is asked exactly what was recorded, as the sign-in, and '
      'its reply is recorded once', () async {
    final airlock = LogAirlock();
    final model = RecordedModel();
    final path = start(airlock, [model], rules: rules);
    final streamed = <String>[];
    path.underway.listen(
      (u) => streamed.add(switch (u.progress) {
        ReplyArriving(:final text) => text,
        Printed(:final text) => text,
      }),
    );
    final answer = await answerOf(ask(recordedRequest(airlock)), path.at(1));
    expect(answer, 'Clause 4 says rent is due monthly.');
    expect(model.calls, [
      ['nick-claude-team', 'claude-opus-5-5', system.join(), asked.join()],
    ]);
    expect(streamed, ['Clause 4 ', 'says rent is due monthly.']);
    expect(airlock.log, [
      '1: allow ask claude-opus-5-5 as nick-claude-team',
      '1: ran ask claude-opus-5-5 as nick-claude-team',
    ]);
  });

  test('a sign-in the rules do not give the loop is denied, and the model '
      'is not asked', () async {
    final airlock = LogAirlock();
    final model = RecordedModel();
    final path = start(airlock, [model], rules: {'model as someone-else'});
    final answer = await answerOf(ask(recordedRequest(airlock)), path.at(1));
    expect(answer, 'failed: not in the rules');
    expect(model.calls, isEmpty);
  });

  test('a request that is not exactly as recorded is refused before the '
      'model is asked', () async {
    final other = idOf('another trajectory');
    // Each refused for its own reason, so the record says what was wrong,
    // not only that the hash failed: the hash would catch most of these on
    // its own, and hide which.
    final cases = <(String, EntryId Function(LogAirlock), String)>[
      (
        'a piece not joining to its hash',
        (a) => recordedRequest(
          a,
          request: recordedText(a, asked, sha256Of: 'something else'),
        ),
        'the pieces do not join',
      ),
      (
        'a system prompt not joining to its hash',
        (a) => recordedRequest(
          a,
          systemPrompt: recordedText(a, system, sha256Of: 'else'),
        ),
        'the pieces do not join',
      ),
      (
        'a piece on another chain',
        (a) => recordedRequest(a, request: recordedText(a, asked, on: other)),
        'is on another chain',
      ),
      (
        'a request on another chain',
        (a) => recordedRequest(a, on: other),
        'is on another chain',
      ),
      (
        'a piece not recorded',
        (a) => recordedRequest(
          a,
          request: RecordedText(
            pieces: [EntryId.of(utf8.encode('never recorded'))],
            sha256: ObjectId.of(utf8.encode(asked.join())),
          ),
        ),
        'is not recorded',
      ),
      (
        'a request not recorded',
        (a) => EntryId.of(utf8.encode('nothing')),
        'is not recorded',
      ),
      (
        'an entry that is not a model request',
        (a) => a.remember('"hello"'),
        'not a model request',
      ),
      (
        // Hashed as if the piece were skipped, so only its own check refuses.
        'a piece that is not a model request piece',
        (a) => recordedRequest(
          a,
          request: RecordedText(
            pieces: [a.remember('"hello"')],
            sha256: ObjectId.of(utf8.encode('')),
          ),
        ),
        'not a model request piece',
      ),
    ];
    for (final (why, request, said) in cases) {
      final airlock = LogAirlock();
      final model = RecordedModel();
      final path = start(airlock, [model], rules: rules);
      final answer = await answerOf(ask(request(airlock)), path.at(1));
      expect(
        answer,
        allOf(startsWith('failed: '), contains(said)),
        reason: why,
      );
      expect(model.calls, isEmpty, reason: why);
      expect(
        airlock.log.last,
        startsWith('1: refused ask claude-opus-5-5'),
        reason: why,
      );
    }
  });

  test('with no model driver, the call is refused', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [], rules: rules);
    final answer = await answerOf(ask(recordedRequest(airlock)), path.at(1));
    expect(answer, 'failed: this machine cannot run model');
  });

  test('a model call is proposed as `model`, and read back strictly', () {
    final request = EntryId.of(utf8.encode('the request'));
    final input = {
      'signIn': 'nick-claude-team',
      'model': 'claude-opus-5-5',
      'request': request.hex,
    };
    Object? wire(Object? input) => jsonDecode(
      jsonEncode({'program': 'model', 'place': 1, 'input': input}),
    );
    expect(Proposal.read(wire(input)), isA<Proposal>());
    for (final bad in <Object?>[
      {...input, 'request': 'nope'},
      {...input, 'signIn': 'Nick Team'},
      {...input, 'body': 'words of its own'},
      {'signIn': 'nick-claude-team', 'model': 'claude-opus-5-5'},
    ]) {
      expect(Proposal.read(wire(bad)), isA<Rejected>(), reason: '$bad');
    }
  });
}
