part of 'action.dart';

// One web request's chain in the logbook. The airlock's
// [AirlockDecisionOnWebRequest] logbook entry starts it (previous `-`): it
// cannot follow the proposal, whose chain only the path's loop user may
// extend. The airlock's [resultOfActionOrWhyRefusedKind] logbook entry
// follows it, naming it as its previous.
//
// The tip check does not stop two decisions on one proposal, since each
// starts a chain of its own; the airlock decides each proposal once. Each
// decision names its proposal, so no two start byte-identical chains, which
// the logbook service refuses.

/// A web request's [AirlockDecisionOnAction] as the logbook holds it: the
/// request, its exact body among it, and what was decided.
final class AirlockDecisionOnWebRequest {
  const AirlockDecisionOnWebRequest._(
    this.trajectory,
    this.place,
    this.request,
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
    MakesWebRequest(:final request) => AirlockDecisionOnWebRequest._(
      decided.trajectoryId,
      placeToJson(decided.place),
      request,
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

  final Decision decision;

  /// The [ActionProposedByAgentLoop] logbook entry that asked for the
  /// request; null for one proposed in the airlock service's own process.
  final EntryId? proposed;

  Object? toJson() => {
    'trajectory': trajectory.hex,
    'place': place,
    'request': _webRequestToJson(request),
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

/// How a [WebRequest]'s body is drawn from the recorded entry it names:
/// one pure function each, which the loop builds the body with and the
/// airlock checks it by, byte for byte.
enum Projection {
  /// A Teams message whose text is a model's reply: drawn from a
  /// [resultOfActionOrWhyRefusedKind] body whose result ran to text, as
  /// `{"type":"message","text":<text>}`, Dart's `jsonEncode` of those two
  /// keys in that order, with no whitespace and the text as UTF-8.
  teamsMessageFromModelReply('teams-message-from-model-reply');

  const Projection(this.wire);

  /// Its name in a proposal.
  final String wire;

  /// [wire] read back; null when it names none.
  static Projection? parse(String wire) =>
      values.where((p) => p.wire == wire).firstOrNull;

  /// The body drawn from [recorded], the text of the entry a request
  /// names; null when it draws none from it.
  String? drawnFrom(String recorded) => switch (this) {
    teamsMessageFromModelReply => switch (readResultOfActionOrWhyRefused(
      _jsonOrNull(recorded),
    )) {
      (proposed: _, result: {'kind': 'ran', 'output': final String text}) =>
        jsonEncode({'type': 'message', 'text': text}),
      _ => null,
    },
  };
}

Object? _jsonOrNull(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
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
