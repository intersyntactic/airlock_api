part of 'run.dart';

/// What the service that starts a journey path asks of the airlock service:
/// start the journey path [journeyPath] under [rules], or, when it is
/// already live, hand over a new token for it.
///
/// The journey path lives in the airlock service, which holds the drivers,
/// so it is started there, by [JourneyPath.start]; whoever starts it is
/// another service, which builds the path's loop and gives it the token
/// this is answered with ([Started]). The airlock service takes a start only
/// from that service's OS user on the socket: one fixed service, unlike a
/// loop, whose agent's paths all share its user, so the user is enough
/// here.
///
/// Sent again after either service restarts: for a path the airlock service
/// no longer holds, it is started anew under the same id, so it is the same
/// path, with a new token; for one it holds, [JourneyPath.reissue] gives a
/// new token and the old one carries out nothing more. [stopped] says the
/// person stopped it, since a stop lives in the airlock service's memory and
/// a restart would otherwise undo it; a start never un-stops a path.
final class StartPath implements StartReceived {
  /// A start, for the sender to send as [toJson]. [rules] is already the
  /// JSON the airlock service reads the path's rules from: the two services
  /// agree their type between them.
  const StartPath(
    this.journeyPath, {
    required this.rules,
    this.stopped = false,
  });

  /// [json] read as a start, or [Rejected] with why it is not one.
  static StartReceived read(Object? json) {
    if (json case {'start': final String path, 'stopped': final bool stopped}) {
      return switch (JourneyPathId.parse(path)) {
        final id? => StartPath(id, rules: json['rules'], stopped: stopped),
        null => Rejected('not a journey path: $path'),
      };
    }
    return const Rejected('not a start');
  }

  final JourneyPathId journeyPath;

  /// The path's rules, as JSON; the airlock service reads them as its
  /// journey paths' `R`. A path already live keeps the rules it started
  /// under: rules never change on a live path.
  final Object? rules;

  /// Whether the person stopped the path.
  final bool stopped;

  Object? toJson() => {
    'start': journeyPath.hex,
    'rules': rules,
    'stopped': stopped,
  };
}

/// What a request to start a journey path came to, once read: a
/// [StartPath], or [Rejected].
sealed class StartReceived {}

/// What the airlock service answers a [StartPath] with: [Started], or
/// [Rejected].
sealed class StartAnswer {
  /// [json], the airlock service's answer, read by whoever sent the start.
  /// Throws a [FormatException] when it is neither answer.
  static StartAnswer read(Object? json) => switch (json) {
    {'kind': 'started', 'token': final String token} => switch (PathToken.parse(
      token,
    )) {
      final t? => Started._(t),
      null => throw const FormatException('started: not a token'),
    },
    {'kind': 'refused', 'why': final String why} => Rejected(why),
    _ => throw const FormatException('not an answer to a start'),
  };

  /// The answer as JSON, for the socket to take back.
  Object? get json;
}

/// The journey path is live, and [token] is what its loop shows: the only
/// token that carries out anything on it now.
final class Started implements StartAnswer {
  const Started._(this.token);

  /// The answer for [path], once it is started or its token reissued.
  factory Started.of(JourneyPath<Object?, Object?> path) =>
      Started._(path.token);

  final PathToken token;

  @override
  Object? get json => {'kind': 'started', 'token': token.hex};
}
