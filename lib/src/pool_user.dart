part of 'run.dart';

// The OS users loop_launcher hands out, one from each pool, made ahead of
// time on the box by infra, never by loop_launcher (Nick, 16 Nov: "a pool
// made ahead of time"). Here, not in loop_launcher, since the airlock
// service reads them in every [PathStarted] and checks a [Proposal]'s
// sender against one: both sides need the one type.

/// A user from the loop pool, `loop-<n>`: a journey path's agent loop runs
/// as it, holding the path's token and the model sign-ins its rules allow.
/// It owns no files (Nick, 16 Nov: "a loop user of its own, one per running
/// loop, from a second pool"). The airlock service takes a path's proposals
/// only from the path's loop user, as the kernel reports the socket's peer.
final class LoopUser extends _PoolUser {
  LoopUser._(super.n);

  /// [s] as a loop user; null unless it is `loop-<n>`, n from 1.
  static LoopUser? parse(String s) => switch (_numbered('loop', s)) {
    final n? => LoopUser._(n),
    null => null,
  };

  @override
  String get name => 'loop-$n';
}

/// A user from the journey pool, `journey-<n>`: it owns a journey's working
/// tree, and the journey's programs run as it, through the airlock's program
/// driver. Nothing of loop_launcher's runs as it.
final class JourneyUser extends _PoolUser {
  JourneyUser._(super.n);

  /// [s] as a journey user; null unless it is `journey-<n>`, n from 1.
  static JourneyUser? parse(String s) => switch (_numbered('journey', s)) {
    final n? => JourneyUser._(n),
    null => null,
  };

  @override
  String get name => 'journey-$n';
}

sealed class _PoolUser {
  _PoolUser(this.n);

  final int n;

  /// The OS user's name.
  String get name;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType && other is _PoolUser && other.n == n;

  @override
  int get hashCode => Object.hash(runtimeType, n);

  @override
  String toString() => name;
}

final _digits = RegExp(r'^[1-9][0-9]*$');

int? _numbered(String prefix, String s) {
  if (!s.startsWith('$prefix-')) return null;
  final rest = s.substring(prefix.length + 1);
  return _digits.hasMatch(rest) ? int.parse(rest) : null;
}
