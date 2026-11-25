import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_reply_requests_api/is_reply_requests_api.dart';
import 'package:is_reply_vocabulary/is_reply_vocabulary.dart';
import 'package:is_sign_in_vocabulary/is_sign_in_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show LogAirlock, answerOf, idOf, start, teams, throughLogbook;

final slack = Origin.parse('https://slack.com')!;
final postMessage = WebPath.parse('/api/chat.postMessage')!;

final ownSlack = RepliesInSlackConversation(
  origin: slack,
  channel: SlackChannelId.parse('C123')!,
  thread: SlackMessageTimestamp.parse('1700000000.000100'),
);
final ownTeams = RepliesUnderWebAddress(
  AddressPrefix.of(teams, PathPrefix.parse('/v3/conversations/c/')!),
);

/// A Slack writer that draws one request per piece of the text (split on
/// `|`), posting each to [address] (by default chat.postMessage), and
/// reads a response's status: 200 posted as `<n>.000100`, 400 refused,
/// anything else unknown.
final class SlackWriter implements WritesSlackReplyRequests {
  SlackWriter({this.address, this.signIn});

  /// Where it draws its requests to, in place of chat.postMessage, as a
  /// faulty writer would.
  final WebPath? address;

  /// A sign-in it names on its requests, as a faulty writer would.
  final SignIn? signIn;

  final drawnFor = <TrajectoryId>[];
  var _posted = 0;

  @override
  List<ProposedRequest> draw(
    RepliesInSlackConversation to,
    TrajectoryId trajectory,
    ReplyContent content,
  ) {
    drawnFor.add(trajectory);
    return [
      for (final piece in content.text.value.split('|'))
        ProposedRequest(
          to.origin,
          method: Method.post,
          path: address ?? postMessage,
          signIn: signIn,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'channel': to.channel.value, 'text': piece}),
        ),
    ];
  }

  @override
  Outcome<SlackMessageTimestamp> posted(WebResponse response) =>
      switch (response.status) {
        200 => Ran(SlackMessageTimestamp.parse('${++_posted}.000100')!),
        400 => const NothingRan('not_in_channel'),
        _ => StoppedPartway(why: 'status ${response.status}', done: null),
      };
}

/// A Bot Connector writer: one request under the endpoint, read as the
/// server's id `activity-1`.
final class TeamsWriter implements WritesWebAddressReplyRequests {
  @override
  List<ProposedRequest> draw(
    RepliesUnderWebAddress to,
    TrajectoryId trajectory,
    ReplyContent content,
  ) => [
    ProposedRequest(
      to.prefix.origin,
      method: Method.post,
      path: WebPath.parse('${to.prefix.pathPrefix.value}activities')!,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'text': content.text.value}),
      keep: BodyToKeep.text,
    ),
  ];

  @override
  Outcome<ServerAssignedMessageId> posted(WebResponse response) =>
      Ran(ServerAssignedMessageId.parse('activity-1')!);
}

/// A web driver that keeps every granted request and answers each with the
/// next of [answers], or 200 when they run out.
final class ScriptedWeb implements CarriesOutWebRequests {
  ScriptedWeb([this.answers = const []]);

  final List<Outcome<WebResponse>> answers;
  final sent = <GrantedRequest>[];

  @override
  Future<Outcome<WebResponse>> carryOutWebRequest(
    GrantedRequest request,
  ) async {
    sent.add(request);
    final n = sent.length - 1;
    return n < answers.length
        ? answers[n]
        : const Ran(WebResponse(status: 200));
  }
}

Result<String> reply(String text, {String? footer}) =>
    Program.replyToOwnConversation.runOrFail(
      ReplyContent(
        text: ReplyText.parse(text)!,
        footer: footer == null ? null : ReplyText.parse(footer),
      ),
      then: (posted) => Done(
        posted
            .map(
              (m) => switch (m) {
                PostedInSlackConversation(:final channel, :final timestamp) =>
                  '$channel/$timestamp',
                PostedUnderWebAddress(:final prefix, :final id) =>
                  '$prefix#$id',
              },
            )
            .join(', '),
      ),
    );

/// The single result [airlock] wrote, as the logbook keeps it.
Object? resultOf(LogAirlock airlock) =>
    (jsonDecode(jsonEncode(airlock.results.values.single))
        as Map)['result']; // cast-ok: test reads back JSON it just encoded

const ok = Ran(WebResponse(status: 200));
const refused = Ran(WebResponse(status: 400));
const unknown = Ran(WebResponse(status: 503));

/// [text] replied on a trajectory whose own endpoint is [endpoint], with
/// [web] and the writers given, through the logbook.
Future<String> replied(
  String text, {
  required LogAirlock airlock,
  required ScriptedWeb web,
  SlackWriter? slackWriter,
  TeamsWriter? teamsWriter,
  Set<String> rules = const {'reply'},
}) => answerOf(
  reply(text),
  throughLogbook(
    start(
      airlock,
      [web],
      rules: rules,
      slackReplies: slackWriter,
      webAddressReplies: teamsWriter,
    ),
    airlock,
    turn: 1,
  ),
);

void main() {
  test('a Slack reply is drawn by the module, sent as the granted sign-in '
      'through the web driver, and recorded in the granted channel', () async {
    final web = ScriptedWeb();
    final writer = SlackWriter();
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    expect(
      await replied('one|two', airlock: airlock, web: web, slackWriter: writer),
      'C123/1.000100, C123/2.000100',
    );
    expect(writer.drawnFor, [idOf('started root')]);
    expect(web.sent, hasLength(2));
    for (final granted in web.sent) {
      expect(granted.proposed.signIn, LogAirlock.replyBot);
      expect(granted.proposed.origin, slack);
      expect(granted.proposed.path, postMessage);
      expect(granted.grantedPathPrefix, PathPrefix.parse('/api/'));
    }
    expect(resultOf(airlock), {
      'kind': 'ran',
      'output': [
        {
          'case': 'in-slack-conversation',
          'channel': 'C123',
          'timestamp': '1.000100',
        },
        {
          'case': 'in-slack-conversation',
          'channel': 'C123',
          'timestamp': '2.000100',
        },
      ],
    });
  });

  test('a reply under a web address goes under the granted prefix', () async {
    final web = ScriptedWeb();
    final airlock = LogAirlock(ownReplyEndpoint: ownTeams);
    final answer = await replied(
      'hi',
      airlock: airlock,
      web: web,
      teamsWriter: TeamsWriter(),
    );
    expect(answer, endsWith('#activity-1'));
    expect(web.sent.single.proposed.signIn, LogAirlock.replyBot);
    expect(web.sent.single.grantedPathPrefix, ownTeams.prefix.pathPrefix);
    // The writer reads the posted id from the body, so what it asked to
    // keep reaches the web driver as drawn.
    expect(web.sent.single.proposed.keep, BodyToKeep.text);
  });

  test(
    'a drawn request to any address but the endpoint\'s sends nothing',
    () async {
      final web = ScriptedWeb();
      final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
      expect(
        await replied(
          'one|two',
          airlock: airlock,
          web: web,
          slackWriter: SlackWriter(address: WebPath.parse('/api/chat.delete')),
        ),
        startsWith(
          'failed: request 1 of 2: https://slack.com/api/chat.delete '
          "is not the reply endpoint's address",
        ),
      );
      expect(web.sent, isEmpty);
    },
  );

  test('a drawn request naming its own sign-in sends nothing', () async {
    final web = ScriptedWeb();
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    expect(
      await replied(
        'hello',
        airlock: airlock,
        web: web,
        slackWriter: SlackWriter(signIn: SignIn.parse('other-bot')),
      ),
      'failed: request 1 of 1: names its own sign-in',
    );
    expect(web.sent, isEmpty);
  });

  test(
    'when the server says the first message did not post, nothing ran',
    () async {
      final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
      await replied(
        'one|two',
        airlock: airlock,
        web: ScriptedWeb([refused]),
        slackWriter: SlackWriter(),
      );
      expect(resultOf(airlock), {
        'kind': 'nothingRan',
        'why': 'message 1 of 2: not_in_channel',
      });
    },
  );

  test(
    'a later message refused stops partway, keeping those that posted',
    () async {
      final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
      await replied(
        'one|two|three',
        airlock: airlock,
        web: ScriptedWeb([ok, refused]),
        slackWriter: SlackWriter(),
      );
      expect(resultOf(airlock), {
        'kind': 'stoppedPartway',
        'why': 'message 2 of 3 did not post: not_in_channel',
        'done': [
          {
            'case': 'in-slack-conversation',
            'channel': 'C123',
            'timestamp': '1.000100',
          },
        ],
      });
    },
  );

  test(
    'a first message whose posting is unknown is never nothing ran',
    () async {
      final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
      await replied(
        'one|two',
        airlock: airlock,
        web: ScriptedWeb([unknown]),
        slackWriter: SlackWriter(),
      );
      expect(resultOf(airlock), {
        'kind': 'stoppedPartway',
        'why': 'message 1 of 2 may have posted, unknown: status 503',
        'done': <Object?>[],
      });
    },
  );

  test("the web driver's own outcome stops the reply the same way", () async {
    final cannotSend = ScriptedWeb([const NothingRan('no route')]);
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    await replied(
      'one|two',
      airlock: airlock,
      web: cannotSend,
      slackWriter: SlackWriter(),
    );
    expect(resultOf(airlock), {
      'kind': 'nothingRan',
      'why': 'message 1 of 2: no route',
    });

    final noAnswer = LogAirlock(ownReplyEndpoint: ownSlack);
    await replied(
      'one|two',
      airlock: noAnswer,
      web: ScriptedWeb([ok, const StoppedPartway(why: 'reset', done: null)]),
      slackWriter: SlackWriter(),
    );
    expect(resultOf(noAnswer), {
      'kind': 'stoppedPartway',
      'why': 'message 2 of 2 may have posted, unknown: reset',
      'done': [
        {
          'case': 'in-slack-conversation',
          'channel': 'C123',
          'timestamp': '1.000100',
        },
      ],
    });
  });

  test('a reply allowed with none granted sends nothing', () async {
    final web = ScriptedWeb();
    final airlock = LogAirlock();
    expect(
      await replied(
        'hello',
        airlock: airlock,
        web: web,
        slackWriter: SlackWriter(),
      ),
      'failed: allowed with no reply granted',
    );
    expect(web.sent, isEmpty);
  });

  test('a reply the rules do not grant sends nothing', () async {
    final web = ScriptedWeb();
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    expect(
      await replied(
        'hello',
        airlock: airlock,
        web: web,
        slackWriter: SlackWriter(),
        rules: const {},
      ),
      'failed: not in the rules',
    );
    expect(web.sent, isEmpty);
  });

  test('a Slack endpoint with no Slack writer runs nothing', () async {
    final web = ScriptedWeb();
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    expect(
      await replied(
        'hello',
        airlock: airlock,
        web: web,
        teamsWriter: TeamsWriter(),
      ),
      'failed: this machine cannot run reply-to-own-conversation',
    );
    expect(web.sent, isEmpty);
  });

  test('the footer is decided with the text, in the reach', () async {
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    final path = start(
      airlock,
      [ScriptedWeb()],
      rules: const {'reply'},
      slackReplies: SlackWriter(),
    );
    final decided = <Reach>[];
    path.decisions.listen((d) => decided.add(d.reach));
    await answerOf(
      reply('hello', footer: 'turn 3'),
      throughLogbook(path, airlock, turn: 1),
    );
    expect(decided.single, isA<RepliesToOwnConversation>());
    final RepliesToOwnConversation(:content) =
        decided.single as RepliesToOwnConversation; // cast-ok: checked above
    expect(content.text.value, 'hello');
    expect(content.footer?.value, 'turn 3');
  });
}
