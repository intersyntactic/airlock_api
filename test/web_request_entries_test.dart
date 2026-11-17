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
        teamsReply,
        webRequest,
        writeAndFormat;

/// [json] as the journal would hold it and give it back: JSON text.
Object? throughText(Object? json) => jsonDecode(jsonEncode(json));

/// [json] as the journal would hold it, read back as our own wire is.
JsonObject wire(Object? json) => JsonObject.decode(jsonEncode(json));

/// The [Decided] entries recorded while [run] is carried through on a journey path
/// with [rules].
Future<List<Decided<int>>> decidedWhile(
  Future<void> Function(JourneyPath<Set<String>, int> path) run, {
  Set<String> rules = const {},
}) async {
  final airlock = LogAirlock();
  final path = start(airlock, [RecordedWeb(), MemoryFiles()], rules: rules);
  final decided = <Decided<int>>[];
  path.entries.listen((e) {
    if (e case final Decided<int> d) decided.add(d);
  });
  await run(path);
  return decided;
}

void main() {
  test("a web request's Decided entry reads back as it was written", () async {
    expect(DecidedWebRequest.kind, 'web-request-decided');
    final turn = EntryId.of(utf8.encode('done'));
    final decided = await decidedWhile(
      (path) => answerOf(webRequest(teams, hart, entries: [turn]), path.at(4)),
      rules: {'$teams as $hart'},
    );
    final written = DecidedWebRequest.of(decided.single, (int place) => place)!;
    final read = DecidedWebRequest.fromJson(wire(written.toJson()));
    expect(read.journeyPath, written.journeyPath);
    expect(read.place, 4);
    expect(read.request.origin, teams);
    expect(read.request.signIn, hart);
    expect(read.request.method, Method.post);
    expect(read.request.path, written.request.path);
    expect(read.request.renderer, teamsReply.name);
    expect(read.request.entries, [turn]);
    expect(read.renderer?.id, teamsReply.renderer.id);
    expect(read.renderer?.executable, teamsReply.renderer.executable);
    expect(read.decision, isA<Allow>());
    expect(read.decision.by, DecidedBy.rules);
  });

  test('a denied web request, and one whose renderer named nothing, read back with '
      'why', () async {
    final decided = await decidedWhile((path) async {
      await answerOf(webRequest(teams, hart), path.at(1));
      await answerOf(webRequest(teams, hart, renderer: 'nowhere'), path.at(2));
    });
    final [denied, unnamed] = [
      for (final d in decided)
        DecidedWebRequest.fromJson(
          wire(DecidedWebRequest.of(d, (int place) => place)!.toJson()),
        ),
    ];
    expect(denied.decision, isA<Deny>());
    expect((denied.decision as Deny).why, 'not in the rules');
    expect(denied.renderer, isNotNull);
    expect(unnamed.renderer, isNull);
    expect((unnamed.decision as Deny).why, 'no renderer named nowhere');
  });

  test(
    "an action that is not a web request has no web request entry",
    () async {
      final decided = await decidedWhile(
        (path) => answerOf(writeAndFormat('a.dart'), path.at(1)),
        rules: {'write', 'dart'},
      );
      expect(
        decided.map((d) => DecidedWebRequest.of(d, (int place) => place)),
        everyElement(isNull),
      );
    },
  );

  test('a Rendered entry reads back, with a body or a refusal', () {
    final decided = EntryId.of(utf8.encode('the decided entry'));
    for (final body in <Outcome<String>>[
      const Ran('the tests pass'),
      const Refused('entry abc is not recorded'),
    ]) {
      final read = Rendered.fromJson(
        wire(
          Rendered(
            decided: decided,
            renderer: teamsReply.renderer.id,
            body: body,
          ).toJson(),
        ),
      );
      expect(read.decided, decided);
      expect(read.renderer, teamsReply.renderer.id);
      expect(
        switch (read.body) {
          Ran(:final output) => 'ran $output',
          Refused(:final why) => 'refused $why',
        },
        switch (body) {
          Ran(:final output) => 'ran $output',
          Refused(:final why) => 'refused $why',
        },
      );
    }
  });

  test('a malformed entry is refused, naming the part', () async {
    final decided = await decidedWhile(
      (path) => answerOf(webRequest(teams, hart), path.at(1)),
      rules: {'$teams as $hart'},
    );
    final json =
        throughText(
              DecidedWebRequest.of(decided.single, (int p) => p)!.toJson(),
            )!
            as Map<String, Object?>;
    Map<String, Object?> change(String key, Object? value) => {
      ...json,
      key: value,
    };
    final request = json['request']! as Map<String, Object?>;
    String? whyNot(Object? entry) {
      try {
        DecidedWebRequest.fromJson(wire(entry));
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
      whyNot(change('renderer', {'id': 'x', 'executable': 'y'})),
      startsWith('decided.renderer.id'),
    );
    expect(
      whyNot(change('journeyPath', 'x')),
      startsWith('decided.journeyPath'),
    );
    expect(
      () => Rendered.fromJson(
        wire({
          'decided': 'x',
          'renderer': teamsReply.renderer.id.hex,
          'body': {'kind': 'ran', 'output': ''},
        }),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          startsWith('rendered.decided'),
        ),
      ),
    );
  });
}
