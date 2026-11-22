import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'contract_test.dart' show hart, idOf, teams, teamsMessageOf;

/// [json] as the logbook would hold it and give it back: JSON text.
JsonObject throughText(Object? json) => JsonObject.decode(jsonEncode(json));

/// One reach of each kind.
final reaches = <Reach>[
  Reads(RelativePath('a.dart')),
  Writes(FileText(RelativePath('a.dart'), 'void main() {}')),
  Starts(ProgramName.parse('dart')!, Args(['format', 'a.dart'])),
  MakesWebRequests([
    Request(
      teams,
      method: Method.post,
      path: WebPath.parse('/v3/conversations/c/activities')!,
      signIn: hart,
      headers: const {'content-type': 'application/json'},
      body: teamsMessageOf('done'),
    ),
  ]),
  CallsTheModel(
    ModelCall(
      signIn: ModelSignInName.parse('nick-claude-team')!,
      model: ModelName.parse('claude-opus-5-5')!,
      request: EntryId.of(utf8.encode('a model request')),
    ),
  ),
  Reads(RelativePath('report.docx'), as: ReadsAs.bytes),
  FetchesFromWeb(
    WebFetch(
      Origin.parse('https://graph.microsoft.com')!,
      path: WebPath.parse('/v1.0/drives/d/items/i/content')!,
      signIn: hart,
      keep: BodyToKeep.bytes,
    ),
  ),
];

final PlaceInTrajectory place = ProposedForAnIntent.at(3, 0, 1);
final proposed = EntryId.of(utf8.encode('a proposal'));
final lease = EntryId.of(utf8.encode('a lease'));

AirlockDecisionOnAction<PlaceInTrajectory> decided(
  Reach reach,
  Decision decision,
) => AirlockDecisionOnAction(
  idOf('started root'),
  place,
  reach,
  decision,
  proposed: proposed,
);

Object? written(AirlockDecisionOnAction<PlaceInTrajectory> d) =>
    d.toJson((p) => p.toJson());

AirlockDecisionOnAction<PlaceInTrajectory> readBack(Object? json) =>
    AirlockDecisionOnAction.fromJson(
      throughText(json),
      PlaceInTrajectory.parse,
    );

void main() {
  test('a decision of every reach reads back as it was written, to the same '
      'bytes', () {
    for (final reach in reaches) {
      for (final decision in [
        const Allow(by: DecidedBy.rules),
        Deny('leased elsewhere', by: DecidedBy.rules, reliedOn: [lease]),
        const Deny('stopped', by: DecidedBy.person),
      ]) {
        final d = decided(reach, decision);
        final back = readBack(written(d));
        final why = '${reach.runtimeType} ${decision.runtimeType}';
        expect(back.trajectoryId, d.trajectoryId, reason: why);
        expect(back.place, place, reason: why);
        expect(back.reach.runtimeType, reach.runtimeType, reason: why);
        expect(back.decision.runtimeType, decision.runtimeType, reason: why);
        expect(back.decision.by, decision.by, reason: why);
        expect(back.decision.reliedOn, decision.reliedOn, reason: why);
        expect(back.proposed, proposed, reason: why);
        expect(jsonEncode(written(back)), jsonEncode(written(d)), reason: why);
      }
    }
  });

  test("a decision's reach is written as the program and input that make "
      'it, as a proposal writes them', () {
    Object? reachOf(Reach r) =>
        throughText(written(decided(r, const Allow(by: DecidedBy.rules))))
            .asUncheckedMap()['reach'];
    expect(reachOf(reaches[0]), {'program': 'read', 'input': 'a.dart'});
    expect(reachOf(reaches[5]), {
      'program': 'read-bytes',
      'input': 'report.docx',
    });
    expect(
      readBack(written(decided(reaches[5], const Allow(by: DecidedBy.rules))))
          .reach,
      isA<Reads>().having((r) => r.as, 'as', ReadsAs.bytes),
    );
    expect(
      readBack(written(decided(reaches[6], const Allow(by: DecidedBy.rules))))
          .reach,
      isA<FetchesFromWeb>()
          .having((r) => r.path.value, 'path', '/v1.0/drives/d/items/i/content')
          .having((r) => r.signIn, 'signIn', hart)
          .having((r) => r.fetch.keep, 'keep', BodyToKeep.bytes),
    );
    expect(
      reachOf(reaches[2]),
      allOf(
        containsPair('program', 'start'),
        containsPair('executable', 'dart'),
      ),
    );
    final back = readBack(
      written(decided(reaches[3], const Allow(by: DecidedBy.rules))),
    );
    expect(
      back.reach,
      isA<MakesWebRequests>()
          .having((r) => r.requests.single.body, 'body', teamsMessageOf('done'))
          .having((r) => r.requests.single.signIn, 'signIn', hart)
          .having((r) => r.requests.single.headers, 'headers', {
            'content-type': 'application/json',
          }),
    );
    expect(
      readBack(written(decided(reaches[4], const Allow(by: DecidedBy.rules))))
          .reach,
      isA<CallsTheModel>().having(
        (r) => r.model,
        'model',
        ModelName.parse('claude-opus-5-5'),
      ),
    );
  });

  test('a malformed decision is refused, naming the part', () {
    final json = throughText(
      written(decided(reaches[0], const Allow(by: DecidedBy.rules))),
    ).asUncheckedMap();
    String? whyNot(String key, Object? value) {
      try {
        readBack({...json, key: value});
        return null;
      } on FormatException catch (e) {
        return e.message;
      }
    }

    expect(whyNot('place', [3, 0, 1]), isNull);
    expect(whyNot('place', [3, 'reply', 1]), isNull);
    expect(whyNot('place', [3, 'model-call']), isNull);
    for (final (key, value, said) in [
      ('trajectory', 'x', 'decided.trajectory'),
      ('place', 3, 'decided.place: not a place'),
      ('place', [3, 0, -1], 'decided.place: not a place'),
      // As 0.14 wrote a place.
      ('place', [3, 1], 'decided.place: not a place'),
      ('proposed', 'x', 'decided.proposed: not an entry id'),
      // As 0.13 wrote a decision made in the airlock service's own process.
      ('proposed', null, 'decided.proposed: not an entry id'),
      ('reach', {'program': 'delete', 'input': 'a'}, 'decided.reach.program'),
      ('reach', {'program': 'read', 'input': 42}, 'decided.reach.input'),
      ('reach', 'read a.dart', 'decided.reach'),
      ('decision', {'allow': true, 'by': 'robot'}, 'decided.decision.by'),
    ]) {
      expect(whyNot(key, value), startsWith(said), reason: '$key: $value');
    }
  });
}
