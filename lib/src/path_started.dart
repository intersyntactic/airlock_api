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
/// from loop_launcher's OS user on the socket: one fixed service, unlike a
/// loop, whose agent's paths all share its user, so the user is enough
/// here.
///
/// Sent again after either service restarts: for a path the airlock service
/// no longer holds, it sets up its side anew under the same id, so it is the
/// same path, with a new token; for one it holds, [JourneyPath.reissue]
/// gives a new token and the old one is rejected from then on. [stopped]
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
    this.stopped = false,
  });

  /// [json] read as a path started, or [Rejected] with why it is not one.
  static PathStartedReceived read(Object? json) {
    if (json case {
      'pathStarted': final String path,
      'stopped': final bool stopped,
    }) {
      return switch (JourneyPathId.parse(path)) {
        final id? => PathStarted(id, rules: json['rules'], stopped: stopped),
        null => Rejected('not a journey path: $path'),
      };
    }
    return const Rejected('not a path started');
  }

  final JourneyPathId journeyPath;

  /// The path's rules, as JSON; the airlock service reads them as its
  /// journey paths' `R`. A path whose side is already set up keeps the rules
  /// it had: rules never change on a live path.
  final Object? rules;

  /// Whether the person stopped the path.
  final bool stopped;

  Object? toJson() => {
    'pathStarted': journeyPath.hex,
    'rules': rules,
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
