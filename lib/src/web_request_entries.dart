part of 'action.dart';

// One web request's chain in the logbook. The airlock's
// [AirlockDecisionOnWebRequest] logbook entry starts it (previous `-`): it
// cannot follow the proposal, whose chain only the path's loop user may
// extend. The airlock's [outcomeOfProposedActionKind] logbook entry
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
    JsonObject json, [
    String field = 'decided',
  ]) => _at(
    field,
    () => AirlockDecisionOnWebRequest._(
      TrajectoryId.parse(json.string('trajectory')) ??
          (throw FormatException('$field.trajectory: not a trajectory')),
      json.raw('place'),
      _webRequestFromJson(json.object('request'), '$field.request'),
      _decisionFromJson(json.object('decision'), '$field.decision'),
      switch (json.stringOrNull('proposed')) {
        null => null,
        final hex =>
          EntryId.parse(hex) ??
              (throw FormatException('$field.proposed: not an entry id')),
      },
    ),
  );

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
  /// [outcomeOfProposedActionKind] body whose result ran to a [ModelReply],
  /// read by is_effects's `decodeModelReply`, as
  /// `{"type":"message","text":<text>}`, Dart's `jsonEncode` of those two
  /// keys in that order, with no whitespace and the text as UTF-8.
  teamsMessageFromModelReply('teams-message-from-model-reply');

  const Projection(this.wire);

  /// Its name in a proposal.
  final String wire;

  /// [wire] read back; null when it names none.
  static Projection? parse(String wire) =>
      values.where((p) => p.wire == wire).firstOrNull;

  /// The body drawn from [recorded], the body (after its header) of the
  /// [outcomeOfProposedActionKind] logbook entry a request names; null
  /// when it draws none from it. The caller checks the entry's kind.
  String? drawnFrom(String recorded) => switch (this) {
    teamsMessageFromModelReply => switch (_modelReplyIn(recorded)) {
      final reply? => jsonEncode({'type': 'message', 'text': reply.text}),
      null => null,
    },
  };
}

/// The model's reply [recorded] ran to, read with is_effects's own codec so
/// a reply's shape is decided there alone; null when it holds none.
ModelReply? _modelReplyIn(String recorded) {
  final outcome = readOutcomeOfProposedAction(recorded);
  if (outcome == null) return null;
  try {
    return switch (decodeOutcome(outcome.result, decodeModelReply)) {
      Ran(:final output) => output,
      Refused() => null,
    };
  } on FormatException {
    return null;
  }
}

Decision _decisionFromJson(JsonObject json, String field) => _at(field, () {
  final by =
      DecidedBy.values.asNameMap()[json.string('by')] ??
      (throw FormatException('$field.by: not rules or person'));
  return json.boolean('allow')
      ? Allow(by: by)
      : Deny(json.string('why'), by: by);
});

/// What [read] reads from an object at [field], a field of the wrong shape
/// named by its dotted path from [field]: checked_json names it by its key
/// alone.
T _at<T>(String field, T Function() read) {
  try {
    return read();
  } on JsonFieldException catch (e) {
    throw FormatException('$field.${e.field}: not ${e.wanted}');
  }
}

/// [json] as an object at [field], for a value an is_effects codec hands
/// over undecoded.
JsonObject _object(String field, Object? json) =>
    JsonObject.parse(json) ?? (throw FormatException('$field: not an object'));

/// Throws unless every key of [json] is one of [keys].
void _exactly(String field, JsonObject json, Set<String> keys) {
  final unexpected = json.keys.where((k) => !keys.contains(k));
  if (unexpected.isNotEmpty) {
    throw FormatException('$field: unexpected $unexpected');
  }
}
