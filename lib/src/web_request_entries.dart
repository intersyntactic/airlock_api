part of 'action.dart';

// One web request's chain in the journal: a [DecidedWebRequest] entry, the
// [Rendered] entry its renderer writes after it, and the airlock's
// `Returned` after that, each naming the one before as its previous. The
// journal's tip check lets each link be written once. A renderer that does
// not answer in time is closed by the airlock's `Returned` (refused), whose
// previous is the `DecidedWebRequest`, after which a late `Rendered` is
// turned away, since its previous is no longer the tip.
//
// A renderer reads the one and writes the other, and the airlock reads what
// it wrote. What came back from any proposed action, a web request's among
// them, is recorded in full in a [ReturnedProposal].

/// A web request's [Decided] entry as the journal holds it: what its
/// renderer subscribes to the record for, and reads to know what to draw.
final class DecidedWebRequest {
  const DecidedWebRequest._(
    this.journeyPath,
    this.place,
    this.request,
    this.renderer,
    this.decision,
  );

  /// The entry's kind in the journal.
  static const kind = 'web-request-decided';

  /// [decided] as a web request's entry, its place written by
  /// [placeToJson]; null when it is not a web request's.
  static DecidedWebRequest? of<P>(
    Decided<P> decided,
    Object? Function(P place) placeToJson,
  ) => switch (decided.reach) {
    MakesWebRequest(:final request, :final renderer) => DecidedWebRequest._(
      decided.journeyPathId,
      placeToJson(decided.place),
      request,
      renderer,
      decided.decision,
    ),
    Reads() || Writes() || Starts() => null,
  };

  /// [json] read back as a web request's entry, each part checked as its
  /// type's `parse` checks it. Throws a [FormatException] naming the part.
  static DecidedWebRequest fromJson(Object? json, [String field = 'decided']) {
    final map = _object(field, json);
    return DecidedWebRequest._(
      JourneyPathId.parse(_string('$field.journeyPath', map['journeyPath'])) ??
          (throw FormatException('$field.journeyPath: not a journey path')),
      map['place'],
      _webRequestFromJson(map['request'], '$field.request'),
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
  final WebRequest request;

  /// The renderer the request named, exactly; null when its name named
  /// none, and the request was denied.
  final Renderer? renderer;
  final Decision decision;

  Object? toJson() => {
    'journeyPath': journeyPath.hex,
    'place': place,
    'request': _webRequestToJson(request),
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

/// What a renderer wrote after a [DecidedWebRequest] entry: the body it
/// drew from the entries the request names, or why it drew none, and the
/// source it was built from.
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

  /// The [DecidedWebRequest] entry this answers, its previous.
  final EntryId decided;

  /// The source the renderer was built from, as it reports it: the airlock
  /// has the request carried out with the body only when this is the id
  /// the [DecidedWebRequest] names.
  final RendererId renderer;

  /// The body, or [Refused] with why there is none: an entry the request
  /// names that the journal does not hold, or that fails its checks.
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
