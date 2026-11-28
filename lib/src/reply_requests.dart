part of 'action.dart';

/// Writes the web requests that post a reply to an endpoint of kind [E],
/// and reads back what each one posted. Pure: it holds no secret and sends
/// nothing, so the web requests driver knows nothing of the chat service.
///
/// The airlock decides on the whole [ReplyContent], its footer included,
/// and on the endpoint. Every request [draw] writes must be one that
/// endpoint admits, which the airlock checks before any is sent: its
/// address, and for [RepliesWithPinnedBodyFields] its body too. It carries
/// no sign-in: the airlock sets the one it granted. How the text is split
/// into messages the service will take is this writer's, so one reply may
/// be several requests, sent in order.
///
/// [posted] returns the id the service gave the message, never a
/// [PostedMessage]: that is made from the endpoint the airlock granted, so
/// the logbook's conversation is the grant's, never the writer's.
abstract interface class WritesReplyRequests<E extends ReplyEndpoint> {
  /// The requests that post [content] to [to], in the order they are to be
  /// sent. [trajectory] is the one replying, as the trusted side knows it,
  /// for anything in the reply that answers back to it, such as a button to
  /// close it; never taken from the proposal.
  List<ProposedRequest> draw(
    E to,
    TrajectoryId trajectory,
    ReplyContent content,
  );

  /// What one of [draw]'s requests posted, read from its [response]: [Ran]
  /// with the id the service gave the message; [NothingRan] only when the
  /// response itself says nothing posted, such as Slack's `"ok": false` or
  /// a 4xx, with its error as `why`; [StoppedPartway] with `done` null when
  /// it can't be told, such as a 5xx or a body that won't parse, since the
  /// message may have posted.
  Outcome<ServerAssignedMessageId> posted(WebResponse response);
}

/// A [WritesReplyRequests] for endpoints that take every reply at one
/// address and name the conversation in the body, such as Slack's and
/// WhatsApp's.
///
/// Several services can share this endpoint kind, so the airlock picks the
/// writer by the endpoint's address: each writer names the [addresses] it
/// writes to, and no two writers given to one airlock may name the same one.
abstract interface class WritesPinnedBodyReplyRequests
    implements WritesReplyRequests<RepliesWithPinnedBodyFields> {
  /// The addresses this writer's replies are sent to, such as
  /// `https://slack.com` with `/api/chat.postMessage`.
  Set<({Origin origin, WebPath path})> get addresses;
}
