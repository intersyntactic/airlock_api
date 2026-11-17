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
  static DecidedWebRequest fromJson(
    JsonObject json, [
    String field = 'decided',
  ]) => DecidedWebRequest._(
    JourneyPathId.parse(json.string('journeyPath')) ??
        (throw FormatException('$field.journeyPath: not a journey path')),
    json.raw('place'),
    _webRequestFromJson(json.object('request'), '$field.request'),
    switch (json.objectOrNull('renderer')) {
      null => null,
      final renderer => _rendererFromJson(renderer, '$field.renderer'),
    },
    _decisionFromJson(json.object('decision'), '$field.decision'),
  );

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
  static Rendered fromJson(JsonObject json, [String field = 'rendered']) =>
      Rendered(
        decided:
            EntryId.parse(json.string('decided')) ??
            (throw FormatException('$field.decided: not an entry id')),
        renderer:
            RendererId.parse(json.string('renderer')) ??
            (throw FormatException('$field.renderer: not a renderer id')),
        body: decodeOutcome(
          json.raw('body'),
          (body, field) => switch (body) {
            final String text => text,
            _ => throw FormatException('$field: not a string'),
          },
          '$field.body',
        ),
      );

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

Renderer _rendererFromJson(JsonObject json, String field) => Renderer(
  RendererId.parse(json.string('id')) ??
      (throw FormatException('$field.id: not a renderer id')),
  executable:
      ObjectId.parse(json.string('executable')) ??
      (throw FormatException('$field.executable: not an object id')),
);

Decision _decisionFromJson(JsonObject json, String field) {
  final by =
      DecidedBy.values.asNameMap()[json.string('by')] ??
      (throw FormatException('$field.by: not rules or person'));
  return json.boolean('allow')
      ? Allow(by: by)
      : Deny(json.string('why'), by: by);
}

/// [json], refused with a [FormatException] naming [field] and each key it
/// does not know, unless every key is one of [keys]. For a reader whose
/// object must never be skimmed: a key it skipped could be one that
/// restricts.
JsonObject _exactly(String field, JsonObject json, Set<String> keys) {
  final unknown = json.keys.where((key) => !keys.contains(key));
  if (unknown.isNotEmpty) {
    throw FormatException('$field: unexpected ${unknown.join(', ')}');
  }
  return json;
}
