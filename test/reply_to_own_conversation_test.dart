import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_reply_vocabulary/is_reply_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show LogAirlock, answerOf, start, teams, throughLogbook;

/// A Slack driver that keeps every reply it is handed and names the
/// messages it posted `<n>.000100`, or stops partway as told.
final class RecordedSlack implements PostsRepliesInSlackConversations {
  RecordedSlack({this.posts = 1, this.stopsAfter});

  /// How many messages each reply posts.
  final int posts;

  /// Stops with `done` the first this many, when set.
  final int? stopsAfter;
  final replies = <(RepliesInSlackConversation, ReplyText)>[];

  @override
  Future<Outcome<List<SlackMessageTimestamp>>> reply(
    RepliesInSlackConversation to,
    ReplyText text,
  ) async {
    replies.add((to, text));
    final timestamps = [
      for (var n = 1; n <= posts; n++)
        SlackMessageTimestamp.parse('$n.000100')!,
    ];
    return switch (stopsAfter) {
      null => Ran(timestamps),
      final k => StoppedPartway(
        why: 'rate limited',
        done: timestamps.take(k).toList(),
      ),
    };
  }
}

/// A Bot Connector driver that keeps every reply and names its message
/// `activity-1`.
final class RecordedTeamsReplies implements PostsRepliesUnderWebAddresses {
  final replies = <(RepliesUnderWebAddress, ReplyText)>[];

  @override
  Future<Outcome<List<ServerAssignedMessageId>>> reply(
    RepliesUnderWebAddress to,
    ReplyText text,
  ) async {
    replies.add((to, text));
    return Ran([ServerAssignedMessageId.parse('activity-1')!]);
  }
}

final slackOrigin = Origin.parse('https://slack.com')!;
final ownSlack = RepliesInSlackConversation(
  origin: slackOrigin,
  channel: SlackChannelId.parse('C123')!,
  thread: SlackMessageTimestamp.parse('1700000000.000100'),
);
final ownTeams = RepliesUnderWebAddress(
  AddressPrefix.of(teams, PathPrefix.parse('/v3/conversations/c/')!),
);

Result<String> reply(String text) => Program.replyToOwnConversation.runOrFail(
  ReplyText.parse(text)!,
  then: (posted) => Done(
    posted
        .map(
          (m) => switch (m) {
            PostedInSlackConversation(:final channel, :final timestamp) =>
              '$channel/$timestamp',
            PostedUnderWebAddress(:final prefix, :final id) => '$prefix#$id',
          },
        )
        .join(', '),
  ),
);

/// The single result [airlock] wrote, as the logbook keeps it.
Object? resultOf(LogAirlock airlock) =>
    (jsonDecode(jsonEncode(airlock.results.values.single))
        as Map)['result']; // cast-ok: test reads back JSON it just encoded

void main() {
  test('a Slack reply posts the text to the granted conversation alone, and '
      'records the messages there', () async {
    final slack = RecordedSlack(posts: 2);
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    expect(
      await answerOf(
        reply('hello'),
        throughLogbook(
          start(airlock, [slack], rules: {'reply'}),
          airlock,
          turn: 1,
        ),
      ),
      'C123/1.000100, C123/2.000100',
    );
    expect(slack.replies.single.$1, ownSlack);
    expect(slack.replies.single.$2.value, 'hello');
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

  test('a reply under a web address goes to the granted address', () async {
    final web = RecordedTeamsReplies();
    final airlock = LogAirlock(ownReplyEndpoint: ownTeams);
    final answer = await answerOf(
      reply('hi'),
      throughLogbook(start(airlock, [web], rules: {'reply'}), airlock, turn: 1),
    );
    expect(web.replies.single.$1, ownTeams);
    expect(answer, endsWith('#activity-1'));
  });

  test('a reply allowed with no endpoint granted reaches no driver', () async {
    final slack = RecordedSlack();
    final airlock = LogAirlock();
    expect(
      await answerOf(
        reply('hello'),
        throughLogbook(
          start(airlock, [slack], rules: {'reply'}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: allowed with no reply endpoint granted',
    );
    expect(slack.replies, isEmpty);
    expect(resultOf(airlock), {
      'kind': 'nothingRan',
      'why': 'allowed with no reply endpoint granted',
    });
  });

  test('a reply the rules do not grant reaches no driver', () async {
    final slack = RecordedSlack();
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    expect(
      await answerOf(
        reply('hello'),
        throughLogbook(start(airlock, [slack], rules: {}), airlock, turn: 1),
      ),
      'failed: not in the rules',
    );
    expect(slack.replies, isEmpty);
  });

  test('a Slack endpoint on a machine with only a web address reply driver '
      'runs nothing', () async {
    final web = RecordedTeamsReplies();
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    expect(
      await answerOf(
        reply('hello'),
        throughLogbook(
          start(airlock, [web], rules: {'reply'}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: this machine cannot run reply-to-own-conversation',
    );
    expect(web.replies, isEmpty);
  });

  test('a reply that stops partway records the messages that posted, in the '
      'granted conversation', () async {
    final slack = RecordedSlack(posts: 3, stopsAfter: 1);
    final airlock = LogAirlock(ownReplyEndpoint: ownSlack);
    expect(
      await answerOf(
        reply('a long reply'),
        throughLogbook(
          start(airlock, [slack], rules: {'reply'}),
          airlock,
          turn: 1,
        ),
      ),
      'failed: stopped partway: rate limited',
    );
    expect(resultOf(airlock), {
      'kind': 'stoppedPartway',
      'why': 'rate limited',
      'done': [
        {
          'case': 'in-slack-conversation',
          'channel': 'C123',
          'timestamp': '1.000100',
        },
      ],
    });
  });
}
