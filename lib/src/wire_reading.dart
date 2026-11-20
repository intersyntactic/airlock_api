part of 'action.dart';

Object? _answerToJson(Answer answer) => switch (answer) {
  ReplyToEvent(:final respondsTo, :final reply) => {
    'answer': 'reply',
    'respondsTo': respondsTo.hex,
    'reply': reply.hex,
  },
  TrajectoryOpened() => {'answer': 'trajectory-opened'},
};

/// [input] as an [Answer], exactly its keys. Throws a [FormatException]
/// naming the part.
Answer _answerFromJson(Object? input, [String field = 'answer']) {
  final json = _object(field, input);
  EntryId entry(String key) =>
      EntryId.parse(json.string(key)) ??
      (throw FormatException('$field.$key: not an entry id'));
  return _at(field, () {
    // wire-ok: the answer's tag, read once into the sealed Answer
    switch (json.string('answer')) {
      case 'reply':
        _exactly(field, json, const {'answer', 'respondsTo', 'reply'});
        return ReplyToEvent(
          respondsTo: entry('respondsTo'),
          reply: entry('reply'),
        );
      case 'trajectory-opened':
        _exactly(field, json, const {'answer'});
        return const TrajectoryOpened();
      case final other:
        throw FormatException('$field.answer: not an answer: $other');
    }
  });
}

Object? _webResponsesToJson(List<WebResponse> responses) => [
  for (final r in responses) encodeWebResponse(r),
];

List<WebResponse> _webResponsesFromJson(Object? json, [String field = '']) =>
    switch (json) {
      final List<Object?> list => [
        for (final (i, r) in list.indexed) decodeWebResponse(r, '$field[$i]'),
      ],
      _ => throw FormatException('$field: not a list'),
    };

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
  final reliedOn = [
    for (final (i, hex) in (json.stringsOrNull('reliedOn') ?? []).indexed)
      EntryId.parse(hex) ??
          (throw FormatException('$field.reliedOn[$i]: not an entry id')),
  ];
  return json.boolean('allow')
      ? Allow(by: by, reliedOn: reliedOn)
      : Deny(json.string('why'), by: by, reliedOn: reliedOn);
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
