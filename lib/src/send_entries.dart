part of 'run.dart';

// One send's chain in the journal: a [DecidedSend] entry, the [Rendered]
// entry its renderer writes following it, and the airlock's `Returned`
// following that. The journal's tip check lets each link be written once. A
// renderer that does not answer in time is closed by the airlock's
// `Returned` (refused) following the `DecidedSend` directly, after which a
// late `Rendered` is turned away, since its entry is no longer the tip.
//
// Only a send's entries have a wire form here: a renderer reads one and
// writes the other, and the airlock reads what it wrote. Other runs' entries
// stay as the airlock writes them, naming what a run reached and why, never
// a file's text or a program's output.

/// A send's [Decided] entry as the journal holds it: what its renderer
/// follows the journal for, and reads to know what to draw.
final class DecidedSend {
  const DecidedSend._(
    this.journeyPath,
    this.place,
    this.send,
    this.renderer,
    this.decision,
  );

  /// The entry's kind in the journal.
  static const kind = 'send-decided';

  /// [decided] as a send's entry, its place written by [placeToJson]; null
  /// when it is not a send's.
  static DecidedSend? of<P>(
    Decided<P> decided,
    Object? Function(P place) placeToJson,
  ) => switch (decided.reach) {
    Sends(:final send, :final renderer) => DecidedSend._(
      decided.journeyPathId,
      placeToJson(decided.place),
      send,
      renderer,
      decided.decision,
    ),
    _ => null,
  };

  /// [json] read back as a send's entry, each part checked as its type's
  /// `parse` checks it. Throws a [FormatException] naming the part.
  static DecidedSend fromJson(Object? json, [String field = 'decided']) {
    final map = _object(field, json);
    return DecidedSend._(
      JourneyPathId.parse(_string('$field.journeyPath', map['journeyPath'])) ??
          (throw FormatException('$field.journeyPath: not a journey path')),
      map['place'],
      _sendFromJson(map['send'], '$field.send'),
      switch (map['renderer']) {
        null => null,
        final renderer => _rendererFromJson(renderer, '$field.renderer'),
      },
      _decisionFromJson(map['decision'], '$field.decision'),
    );
  }

  final JourneyPathId journeyPath;

  /// The place in a turn, as its journey path writes places.
  final Object? place;
  final Send send;

  /// The renderer the send named, exactly; null when its name named none,
  /// and the send was denied.
  final Renderer? renderer;
  final Decision decision;

  Object? toJson() => {
    'journeyPath': journeyPath.hex,
    'place': place,
    'send': _sendToJson(send),
    'renderer': switch (renderer) {
      final r? => {'id': r.id.hex, 'executable': r.executable.hex},
      null => null,
    },
    'decision': switch (decision) {
      Allow(:final by) => {'allow': true, 'by': by.name},
      Deny(:final why, :final by) => {
        'allow': false,
        'why': why,
        'by': by.name,
      },
    },
  };
}

/// What a renderer wrote following a [DecidedSend] entry: the body it drew
/// from the entries the send names, or why it drew none, and the source it
/// was built from.
final class Rendered {
  const Rendered({
    required this.decided,
    required this.renderer,
    required this.body,
  });

  /// The entry's kind in the journal.
  static const kind = 'rendered';

  /// [json] read back, each part checked. Throws a [FormatException] naming
  /// the part.
  static Rendered fromJson(Object? json, [String field = 'rendered']) {
    final map = _object(field, json);
    return Rendered(
      decided:
          EntryId.parse(_string('$field.decided', map['decided'])) ??
          (throw FormatException('$field.decided: not an entry id')),
      renderer:
          RendererId.parse(_string('$field.renderer', map['renderer'])) ??
          (throw FormatException('$field.renderer: not a renderer id')),
      body: decodeOutcome(
        map['body'],
        (json, field) => _string(field, json),
        '$field.body',
      ),
    );
  }

  /// The [DecidedSend] entry this follows.
  final EntryId decided;

  /// The source the renderer was built from, as it reports it: the airlock
  /// sends the body only when this is the id the [DecidedSend] names.
  final RendererId renderer;

  /// The body, or [Refused] with why there is none: an entry the send names
  /// that the journal does not hold, or that fails its checks.
  final Outcome<String> body;

  Object? toJson() => {
    'decided': decided.hex,
    'renderer': renderer.hex,
    'body': encodeOutcome(body, (String text) => text),
  };
}

Renderer _rendererFromJson(Object? json, String field) {
  final map = _object(field, json);
  return Renderer(
    RendererId.parse(_string('$field.id', map['id'])) ??
        (throw FormatException('$field.id: not a renderer id')),
    executable:
        ObjectId.parse(_string('$field.executable', map['executable'])) ??
        (throw FormatException('$field.executable: not an object id')),
  );
}

Decision _decisionFromJson(Object? json, String field) {
  final map = _object(field, json);
  final by =
      DecidedBy.values.asNameMap()[_string('$field.by', map['by'])] ??
      (throw FormatException('$field.by: not rules or person'));
  return switch (map['allow']) {
    true => Allow(by: by),
    false => Deny(_string('$field.why', map['why']), by: by),
    _ => throw FormatException('$field.allow: not true or false'),
  };
}

Map<String, Object?> _object(String field, Object? json) => switch (json) {
  final Map<String, Object?> map => map,
  _ => throw FormatException('$field: not an object'),
};

String _string(String field, Object? json) => switch (json) {
  final String s => s,
  _ => throw FormatException('$field: not a string'),
};
