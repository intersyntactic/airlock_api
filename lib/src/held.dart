part of 'run.dart';

/// loop_launcher held back [journeyPath]: the machine has no room for its
/// loop, or no loop user or suit is free. Its kind's entry is written only by
/// loop_launcher, as the journal's sender table allows, on a chain of its
/// own, so the path is named here, not by a chain: a path held before any
/// user was handed to it has no chain yet.
///
/// Recorded once, when a path that has no `assigned` entry yet is held; its
/// `assigned` ends the hold, and a path with users is never held. The
/// airlock sends the path's people one fixed notice for each. Why it was
/// held goes to the operator only, so it is not here (Nick, 16 Nov:
/// https://github.com/enspyrco/intersyntactic/pull/1158).
final class Held {
  const Held(this.journeyPath);

  /// The entry's kind in the journal.
  static const kind = 'held';

  /// [json] read back, strictly: anything but exactly a `journeyPath` throws
  /// a [FormatException] naming the part.
  static Held fromJson(Object? json, [String field = 'held']) {
    final map = _object(field, json);
    if (map.keys.any((key) => key != 'journeyPath')) {
      throw FormatException(
        '$field: unexpected ${map.keys.where((k) => k != 'journeyPath')}',
      );
    }
    return Held(
      JourneyPathId.parse(_string('$field.journeyPath', map['journeyPath'])) ??
          (throw FormatException('$field.journeyPath: not a journey path')),
    );
  }

  final JourneyPathId journeyPath;

  Object? toJson() => {'journeyPath': journeyPath.hex};
}
