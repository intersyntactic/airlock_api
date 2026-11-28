import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_file_request_vocabulary/is_file_request_vocabulary.dart';
import 'package:is_model_vocabulary/is_model_vocabulary.dart'
    show ModelName, ModelSignInName;
import 'package:is_program_request_vocabulary/is_program_request_vocabulary.dart';
import 'package:is_relative_path_vocabulary/is_relative_path_vocabulary.dart';
import 'package:is_web_request_vocabulary/is_web_request_vocabulary.dart';
import 'package:is_conversation_vocabulary/is_conversation_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';
import 'package:test/test.dart';

import 'fixtures.dart' show hart, idOf, teams, teamsMessageOf;

/// [json] as the logbook would hold it and give it back: JSON text.
JsonObject throughText(Object? json) => JsonObject.decode(jsonEncode(json));

/// One reach of each kind.
final reaches = <Reach>[
  Reads(RelativePath('a.dart')),
  Writes(FileText(RelativePath('a.dart'), 'void main() {}')),
  Starts(ProgramName.parse('dart')!, Args(['format', 'a.dart'])),
  MakesWebRequests([
    ProposedRequest(
      teams,
      method: Method.post,
      path: WebPath.parse('/v3/conversations/c/activities')!,
      signIn: hart,
      headers: const {'content-type': 'application/json'},
      body: teamsMessageOf('done'),
    ),
  ]),
  CallsTheModel(
    ModelCallNamingRequestEntry(
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
  RepliesToOwnConversation(
    ReplyContent(
      text: ReplyText.parse(' hello ')!,
      footer: ReplyText.parse('turn 3'),
    ),
  ),
];

final ownSlack = RepliesWithPinnedBodyFields.at(
  origin: Origin.parse('https://slack.com')!,
  path: WebPath.parse('/api/chat.postMessage')!,
  pinned: PinnedBodyFields.of({
    'channel': 'C123',
    'thread_ts': '1700000000.000100',
  })!,
)!;

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
        const Allow.withNoPaths(by: DecidedBy.rules),
        const Allow.withNoPaths(by: null),
        Allow(
          by: DecidedBy.rules,
          grantedPathPrefixes: [PathPrefix.parse('/v3/conversations/')!],
        ),
        Deny('leased elsewhere', by: DecidedBy.rules, reliedOn: [lease]),
        const Deny('stopped', by: DecidedBy.person),
        Allow.toReplyTo(ownSlack, asSignIn: hart, by: DecidedBy.rules),
      ]) {
        final d = decided(reach, decision);
        final back = readBack(written(d));
        final why = '${reach.runtimeType} ${decision.runtimeType}';
        expect(back.trajectoryId, d.trajectoryId, reason: why);
        expect(back.place, place, reason: why);
        expect(back.reach.runtimeType, reach.runtimeType, reason: why);
        expect(back.decision.runtimeType, decision.runtimeType, reason: why);
        expect(byOf(back.decision), byOf(decision), reason: why);
        expect(back.decision.reliedOn, decision.reliedOn, reason: why);
        if (decision case Allow(:final grantedPathPrefixes)) {
          expect(
            (back.decision as Allow)
                .grantedPathPrefixes, // cast-ok: same type checked above
            grantedPathPrefixes,
            reason: why,
          );
          expect(
            (back.decision as Allow) // cast-ok: same type checked above
                .grantedReply,
            decision.grantedReply,
            reason: why,
          );
        }
        expect(back.proposed, proposed, reason: why);
        expect(jsonEncode(written(back)), jsonEncode(written(d)), reason: why);
      }
    }
  });

  test("a decision's reach is written as the program and input that make "
      'it, as a proposal writes them', () {
    Object? reachOf(Reach r) => throughText(
      written(decided(r, const Allow.withNoPaths(by: DecidedBy.rules))),
    ).asUncheckedMap()['reach'];
    expect(reachOf(reaches[0]), {'program': 'read', 'input': 'a.dart'});
    expect(reachOf(reaches[5]), {
      'program': 'read-bytes',
      'input': 'report.docx',
    });
    expect(
      readBack(
        written(
          decided(reaches[5], const Allow.withNoPaths(by: DecidedBy.rules)),
        ),
      ).reach,
      isA<Reads>().having((r) => r.as, 'as', ReadsAs.bytes),
    );
    expect(
      readBack(
        written(
          decided(reaches[6], const Allow.withNoPaths(by: DecidedBy.rules)),
        ),
      ).reach,
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
      written(
        decided(reaches[3], const Allow.withNoPaths(by: DecidedBy.rules)),
      ),
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
      readBack(
        written(
          decided(reaches[4], const Allow.withNoPaths(by: DecidedBy.rules)),
        ),
      ).reach,
      isA<CallsTheModel>().having(
        (r) => r.model,
        'model',
        ModelName.parse('claude-opus-5-5'),
      ),
    );
  });

  test('an allow granting no path writes no prefixes, so it keeps the bytes '
      'it had before prefixes existed', () {
    expect(
      throughText(
        written(
          decided(reaches[0], const Allow.withNoPaths(by: DecidedBy.rules)),
        ),
      ).asUncheckedMap()['decision'],
      {'allow': true, 'by': 'rules'},
    );
  });

  test('an allow no rule governs writes no by, and reads back as null', () {
    final json = throughText(
      written(decided(reaches[0], const Allow.withNoPaths(by: null))),
    ).asUncheckedMap();
    expect(json['decision'], {'allow': true});
    expect(byOf(readBack(json).decision), isNull);
  });

  test('a malformed decision is refused, naming the part', () {
    final json = throughText(
      written(
        decided(reaches[0], const Allow.withNoPaths(by: DecidedBy.rules)),
      ),
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
      (
        'decision',
        {'allow': false, 'why': 'no'},
        'decided.decision.by: missing on a denial',
      ),
      (
        'decision',
        {
          'allow': true,
          'grantedPathPrefixes': ['/v3/'],
          'grantedReply': {
            'to': {
              'case': 'in-slack-conversation',
              'origin': 'https://slack.com',
              'channel': 'C123',
            },
            'asSignIn': 'hart-bot',
          },
        },
        'decided.decision: grants both path prefixes and a reply',
      ),
      (
        'decision',
        {
          'allow': true,
          'grantedReply': {
            'to': {
              'case': 'in-slack-conversation',
              'origin': 'https://slack.com',
              'channel': 'C123',
            },
          },
        },
        'decided.decision.grantedReply.asSignIn',
      ),
      (
        'decision',
        {
          'allow': true,
          'by': 'rules',
          'grantedPathPrefixes': ['/v3'],
        },
        'decided.decision.grantedPathPrefixes[0]: not a path prefix',
      ),
    ]) {
      expect(whyNot(key, value), startsWith(said), reason: '$key: $value');
    }
  });
}

/// Whom [decision] was made by; null for an allow no rule governs.
DecidedBy? byOf(Decision decision) => switch (decision) {
  Allow(by: final DecidedBy? by) || Deny(by: final DecidedBy? by) => by,
};
