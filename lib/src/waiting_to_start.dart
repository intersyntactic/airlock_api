part of 'action.dart';

/// [trajectory] has started, and its work has not begun: it is waiting for
/// room (Nick, 17 Nov: "waiting-to-start"; a traveller does not know what a
/// loop is). The machine has no room for its loop, or no loop user or suit
/// is free. Its kind's entry is written only by loop_launcher, as the
/// journal's sender table allows, on a chain of its own, so the path is
/// named here, not by a chain: a path waiting before any user was handed to
/// it has no chain yet.
///
/// Recorded once, when a path that has no `assigned` entry yet has to wait;
/// its `assigned` ends the wait, and a path with users never waits to
/// start. Why it waits goes to the operator only, so it is not here (Nick,
/// 16 Nov: https://github.com/enspyrco/intersyntactic/pull/1158). What its
/// travellers are told, and who tells them, is decided elsewhere.
final class WaitingToStart {
  const WaitingToStart(this.trajectory);

  /// The entry's kind in the journal.
  static const kind = 'waiting-to-start';

  /// [json] read back, strictly: anything but exactly a `trajectory` throws
  /// a [FormatException] naming the part.
  static WaitingToStart fromJson(
    Object? json, [
    String field = 'waitingToStart',
  ]) {
    final map = _object(field, json);
    if (map.keys.any((key) => key != 'trajectory')) {
      throw FormatException(
        '$field: unexpected ${map.keys.where((k) => k != 'trajectory')}',
      );
    }
    return WaitingToStart(
      TrajectoryId.parse(_string('$field.trajectory', map['trajectory'])) ??
          (throw FormatException('$field.trajectory: not a trajectory')),
    );
  }

  final TrajectoryId trajectory;

  Object? toJson() => {'trajectory': trajectory.hex};
}
