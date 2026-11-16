part of 'run.dart';

/// What loop_launcher tells the airlock service: the journey path
/// [journeyPath] has started, under [rules], so the airlock service can set
/// up its own side of it, or hand over a new token for it when that side is
/// already set up.
///
/// The docking port starts journey paths: it decides which journey path an
/// outside conversation belongs to, and records that decision; a journey
/// starts with its first thread. loop_launcher follows the journal for the
/// docking port's entries that start a path, sends this, and launches the
/// path's loop with the token this is answered with ([Ready]). The airlock
/// starts nothing. Its side of a path, a [JourneyPath], holds the drivers,
/// so it lives in the airlock service. The airlock service takes this only
/// from loop_launcher's OS user on the socket, as the kernel reports the
/// peer.
///
/// It names the two users loop_launcher handed the path (Nick, 16 Nov): the
/// [loopUser] its loop runs as, the only user the airlock service takes the
/// path's proposals from, and the [journeyUser] its programs run as, which
/// the airlock service gives the path's program driver.
///
/// Sent again after either service restarts: for a path the airlock service
/// no longer holds, it sets up its side anew under the same id, so it is the
/// same path, with a new token; for one it holds, [JourneyPath.reissue]
/// gives a new token, and takes the loop user, since a loop launched again
/// may run as another; the old token is rejected from then on. [stopped]
/// says the person stopped it, since a stop lives in the airlock service's
/// memory and a restart would otherwise undo it; nothing here un-stops a
/// path.
final class PathStarted implements PathStartedReceived {
  /// The message, for loop_launcher to send as [toJson]. [rules] is
  /// already the JSON the airlock service reads the path's rules from: the
  /// two services agree their type between them.
  const PathStarted(
    this.journeyPath, {
    required this.rules,
    required this.loopUser,
    required this.journeyUser,
    this.stopped = false,
  });

  /// [json] read as a path started, or [Rejected] with why it is not one.
  static PathStartedReceived read(Object? json) {
    if (json case {
      'pathStarted': final String path,
      'loopUser': final String loop,
      'journeyUser': final String journey,
      'stopped': final bool stopped,
    }) {
      return switch ((
        JourneyPathId.parse(path),
        LoopUser.parse(loop),
        JourneyUser.parse(journey),
      )) {
        (final id?, final loopUser?, final journeyUser?) => PathStarted(
          id,
          rules: json['rules'],
          loopUser: loopUser,
          journeyUser: journeyUser,
          stopped: stopped,
        ),
        (null, _, _) => Rejected('not a journey path: $path'),
        (_, null, _) => Rejected('not a loop user: $loop'),
        (_, _, null) => Rejected('not a journey user: $journey'),
      };
    }
    return const Rejected('not a path started');
  }

  final JourneyPathId journeyPath;

  /// The user the path's loop runs as: the only user the airlock service
  /// takes the path's proposals from.
  final LoopUser loopUser;

  /// The user the path's programs run as. A path whose side is already set
  /// up keeps the journey user it had: it owns the journey's working tree.
  final JourneyUser journeyUser;

  /// The path's rules, as JSON; the airlock service reads them as its
  /// journey paths' `R`. A path whose side is already set up keeps the rules
  /// it had: rules never change on a live path.
  final Object? rules;

  /// Whether the person stopped the path.
  final bool stopped;

  Object? toJson() => {
    'pathStarted': journeyPath.hex,
    'rules': rules,
    'loopUser': loopUser.name,
    'journeyUser': journeyUser.name,
    'stopped': stopped,
  };
}

/// What a [PathStarted] message came to, once read: the message, or
/// [Rejected].
sealed class PathStartedReceived {}

/// What the airlock service answers a [PathStarted] with: [Ready], or
/// [Rejected].
sealed class PathStartedAnswer {
  /// [json], the airlock service's answer, read by loop_launcher. Throws
  /// a [FormatException] when it is neither answer.
  static PathStartedAnswer read(Object? json) => switch (json) {
    {'kind': 'ready', 'token': final String token} => switch (PathToken.parse(
      token,
    )) {
      final t? => Ready._(t),
      null => throw const FormatException('ready: not a token'),
    },
    {'kind': 'refused', 'why': final String why} => Rejected(why),
    _ => throw const FormatException('not an answer to a path started'),
  };

  /// The answer as JSON, for the socket to take back.
  Object? get json;
}

/// The airlock service's side of the path is ready, and [token] is what the
/// path's loop shows: the only token accepted on it now.
final class Ready implements PathStartedAnswer {
  const Ready._(this.token);

  /// The answer for [path], once its side is set up or its token reissued.
  factory Ready.of(JourneyPath<Object?, Object?> path) => Ready._(path.token);

  final PathToken token;

  @override
  Object? get json => {'kind': 'ready', 'token': token.hex};
}
