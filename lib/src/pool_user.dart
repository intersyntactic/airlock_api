part of 'action.dart';

// The OS users loop_launcher hands out, one from each pool, made ahead of
// time on the box by infra, never by loop_launcher (Nick, 16 Nov: "a pool
// made ahead of time"). Here, not in loop_launcher, since loop_launcher
// records them in each path's `assigned` entry and the airlock service reads
// them from it: both sides need the one type.

/// A user from the loop pool, `loop-<n>`: a trajectory's agent loop runs
/// as it, holding the model sign-ins its rules allow. It owns no files
/// (Nick, 16 Nov: "a loop user of its own, one per running loop, from a
/// second pool"). The logbook service takes the entries on a path's chain,
/// its proposals among them, only from the path's loop user.
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

/// A user from the suit pool, `suit-<n>`: the identity one trajectory
/// wears, contained or open (Nick, 16 Nov: "suit";
/// https://github.com/enspyrco/intersyntactic/pull/1158). The path's
/// programs run as it, through the airlock's program driver. Nothing of
/// loop_launcher's runs as it.
final class Suit extends _PoolUser {
  Suit._(super.n);

  /// [s] as a suit; null unless it is `suit-<n>`, n from 1.
  static Suit? parse(String s) => switch (_numbered('suit', s)) {
    final n? => Suit._(n),
    null => null,
  };

  @override
  String get name => 'suit-$n';
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
