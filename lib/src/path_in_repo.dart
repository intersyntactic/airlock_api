import 'package:path/path.dart' as p;

/// A path inside the repo: relative to its root, `/`-separated, normalised,
/// and never leaving the root. The root itself is the empty path.
///
/// A class, not an extension type, so no `String` can be cast to one: the
/// only way to get one is [parse].
///
/// What stays inside is the text. A symlink inside the tree can still point
/// outside it, and only a driver, which sees the disk, can refuse that.
final class PathInRepo {
  const PathInRepo._(this.value);

  static const root = PathInRepo._('');

  final String value;

  /// [raw] read from the repo root, or null when it leaves the root.
  static PathInRepo? parse(String raw) {
    final normal = p.posix.normalize(raw.startsWith('/') ? '.$raw' : raw);
    if (normal == '.') return root;
    if (normal == '..' || normal.startsWith('../')) return null;
    return PathInRepo._(normal);
  }

  /// The folder this path is in; the root's folder is the root.
  PathInRepo get folder {
    final dir = p.posix.dirname(value);
    return dir == '.' ? root : PathInRepo._(dir);
  }

  String get extension => p.posix.extension(value);

  @override
  bool operator ==(Object other) => other is PathInRepo && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
