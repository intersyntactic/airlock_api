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
  /// keys in that order, with no whitespace and the text as UTF-8. A
  /// [CutOffReply]'s text is followed by a blank line and
  /// `_(reply cut off)_`, so it never reads as the whole answer.
  teamsMessageFromModelReply('teams-message-from-model-reply'),

  /// The card that shows a trajectory is open, with its one Close action:
  /// exactly [trajectoryOpenCardBody], drawn from the trajectory itself. Its
  /// request's `drawnFrom` is the trajectory's id, the hash of the
  /// admission that started it, so it draws from no entry's body and the
  /// airlock reads nothing to check it.
  trajectoryOpenCard('trajectory-open-card');

  const Projection(this.wire);

  /// Its name in a proposal.
  final String wire;

  /// [wire] read back; null when it names none.
  static Projection? parse(String wire) =>
      values.where((p) => p.wire == wire).firstOrNull;

  /// The body drawn from [recorded], the body (after its header) of the
  /// [outcomeOfProposedActionKind] logbook entry a request names; null
  /// when it draws none from it, as [trajectoryOpenCard] never does. The
  /// caller checks the entry's kind.
  String? drawnFrom(String recorded) => switch (this) {
    teamsMessageFromModelReply => switch (_modelReplyIn(recorded)) {
      FinishedReply(:final text) => _teamsMessage(text),
      CutOffReply(:final text) => _teamsMessage('$text\n\n$_cutOffMarker'),
      null => null,
    },
    trajectoryOpenCard => null,
  };
}

String _teamsMessage(String text) =>
    jsonEncode({'type': 'message', 'text': text});

/// The line a cut-off reply ends with in Teams.
const _cutOffMarker = '_(reply cut off)_';

/// The exact body of [Projection.trajectoryOpenCard]: a Teams message
/// holding an Adaptive Card 1.5, the version that has rendered in both
/// tenants, reading "● Open · trajectory started" with one action whose
/// `verb` teams_module reads as a request to close the trajectory. Teams
/// shows when it was posted, so the card names no time.
final trajectoryOpenCardBody = jsonEncode({
  'type': 'message',
  'attachments': [
    {
      'contentType': 'application/vnd.microsoft.card.adaptive',
      'content': {
        r'$schema': 'http://adaptivecards.io/schemas/adaptive-card.json',
        'type': 'AdaptiveCard',
        'version': '1.5',
        'body': [
          {
            'type': 'TextBlock',
            'text': '● Open · trajectory started',
            'wrap': true,
          },
        ],
        'actions': [
          {
            'type': 'Action.Execute',
            'title': 'Close trajectory',
            'verb': 'close',
          },
        ],
      },
    },
  ],
});

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
