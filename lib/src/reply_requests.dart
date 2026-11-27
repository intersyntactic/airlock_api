part of 'action.dart';

/// Writes the web requests that post a reply in a Slack conversation, and
/// reads back what each one posted. Pure: it holds no secret and sends
/// nothing, so the web requests driver knows nothing of Slack.
///
/// The airlock decides on the whole [ReplyContent], its footer included,
/// and on the endpoint. Every request [draw] writes must go to an address
/// that endpoint admits, which the airlock checks before any is sent, and
/// carries no sign-in: the airlock sets the one it granted. How the text is
/// split into messages Slack will take is this writer's, so one reply may
/// be several requests, sent in order.
///
/// [posted] returns the timestamp Slack named, never a [PostedMessage]: that
/// is made from the endpoint the airlock granted, so the logbook's
/// conversation is the grant's, never the writer's.
abstract interface class WritesSlackReplyRequests {
  /// The requests that post [content] in [to]'s channel and thread, in the
  /// order they are to be sent. [trajectory] is the one replying, as the
  /// trusted side knows it, for anything in the reply that answers back to
  /// it, such as a button to close it; never taken from the proposal.
  List<ProposedRequest> draw(
    RepliesInSlackConversation to,
    TrajectoryId trajectory,
    ReplyContent content,
  );

  /// What one of [draw]'s requests posted, read from its [response]: [Ran]
  /// with the message's timestamp; [NothingRan] only when the response
  /// itself says nothing posted, such as Slack's `"ok": false`, with its
  /// error as `why`; [StoppedPartway] with `done` null when it can't be
  /// told, such as a 5xx or a body that won't parse, since the message may
  /// have posted.
  Outcome<SlackMessageTimestamp> posted(WebResponse response);
}

/// Writes the web requests that post a reply under a conversation's web
/// address, as Teams' Bot Connector takes it, and reads back what each one
/// posted.
///
/// As [WritesSlackReplyRequests]: pure, every request one the endpoint
/// admits with no sign-in, the split the writer's, and [posted] the
/// server's own id, never a [PostedMessage].
abstract interface class WritesWebAddressReplyRequests {
  /// The requests that post [content] under [to], in the order they are to
  /// be sent, with [trajectory] as for [WritesSlackReplyRequests.draw].
  List<ProposedRequest> draw(
    RepliesUnderWebAddress to,
    TrajectoryId trajectory,
    ReplyContent content,
  );

  /// What one of [draw]'s requests posted, read from its [response]: [Ran]
  /// with the id the server gave the message; [NothingRan] only when the
  /// response itself says nothing posted, such as a 4xx refusing it;
  /// [StoppedPartway] with `done` null when it can't be told, since the
  /// message may have posted.
  Outcome<ServerAssignedMessageId> posted(WebResponse response);
}
