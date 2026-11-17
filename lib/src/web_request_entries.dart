part of 'action.dart';

// One web request's chain in the logbook. The airlock's
// [AirlockDecisionOnWebRequest] logbook entry starts it (previous `-`): it
// cannot follow the proposal, whose chain only the path's loop user may
// extend. The [Rendered] logbook entry its renderer writes follows it, and
// the airlock's [resultOfActionOrWhyRefusedKind] logbook entry follows that,
// each naming the one before as its previous, so the logbook service's tip
// check lets each be written once. A renderer that does not answer in time
// is closed by the airlock's result (refused), whose previous is the
// decision, after which a late [Rendered] is turned away, since its previous
// is no longer the tip.
//
// The tip check does not stop two decisions on one proposal, since each
// starts a chain of its own; the airlock decides each proposal once. Each
// decision names its proposal, so no two start byte-identical chains, which
// the logbook service refuses.
//
// A renderer reads the decision and writes the [Rendered], and the airlock
// reads what it wrote.

/// A web request's [AirlockDecisionOnAction] as the logbook holds it: what
/// its renderer subscribes to the logbook for, and reads to know what to
/// draw.
final class AirlockDecisionOnWebRequest {
  const AirlockDecisionOnWebRequest._(
    this.trajectory,
    this.place,
    this.request,
    this.renderer,
    this.decision,
    this.proposed,
  );

  /// The entry's kind in the logbook.
  static const kind = 'airlock-decision-on-web-request';

  /// [decided] as a web request's entry, its place written by
  /// [placeToJson]; null when it is not a web request's.
  static AirlockDecisionOnWebRequest? of<P>(
    AirlockDecisionOnAction<P> decided,
    Object? Function(P place) placeToJson,
  ) => switch (decided.reach) {
    MakesWebRequest(:final request, :final renderer) =>
      AirlockDecisionOnWebRequest._(
        decided.trajectoryId,
        placeToJson(decided.place),
        request,
        renderer,
        decided.decision,
        decided.proposed,
      ),
    Reads() || Writes() || Starts() || CallsTheModel() => null,
  };

  /// [json] read back as a web request's entry, each part checked as its
  /// type's `parse` checks it. Throws a [FormatException] naming the part.
  static AirlockDecisionOnWebRequest fromJson(
    Object? json, [
    String field = 'decided',
  ]) {
    final map = _object(field, json);
    return AirlockDecisionOnWebRequest._(
      TrajectoryId.parse(_string('$field.trajectory', map['trajectory'])) ??
          (throw FormatException('$field.trajectory: not a trajectory')),
      map['place'],
      _webRequestFromJson(map['request'], '$field.request'),
      switch (map['renderer']) {
        null => null,
        final renderer => _rendererFromJson(renderer, '$field.renderer'),
      },
      _decisionFromJson(map['decision'], '$field.decision'),
      switch (map['proposed']) {
        null => null,
        final hex =>
          EntryId.parse(_string('$field.proposed', hex)) ??
              (throw FormatException('$field.proposed: not an entry id')),
      },
    );
  }

  final TrajectoryId trajectory;

  /// The place in a turn, as its trajectory writes places.
  final Object? place;
  final WebRequest request;

  /// The renderer the request named, exactly; null when its name named
  /// none, and the request was denied.
  final Renderer? renderer;
  final Decision decision;

  /// The [ActionProposedByAgentLoop] logbook entry that asked for the
  /// request; null for one proposed in the airlock service's own process.
  final EntryId? proposed;

  Object? toJson() => {
    'trajectory': trajectory.hex,
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
    'proposed': proposed?.hex,
  };
}

/// What a renderer wrote after an [AirlockDecisionOnWebRequest]: the body
/// it drew from the entries the request names, or why it drew none, and the
/// source it was built from.
final class Rendered {
  const Rendered({
    required this.decided,
    required this.renderer,
    required this.body,
  });

  /// The entry's kind in the logbook.
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

  /// The [AirlockDecisionOnWebRequest] entry this answers, its previous.
  final EntryId decided;

  /// The source the renderer was built from, as it reports it: the airlock
  /// has the request carried out with the body only when this is the id
  /// the [AirlockDecisionOnWebRequest] names.
  final RendererId renderer;

  /// The body, or [Refused] with why there is none: an entry the request
  /// names that the logbook does not hold, or that fails its checks.
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
