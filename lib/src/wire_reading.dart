part of 'action.dart';

Object? _requestsToJson(List<Request> requests) => [
  for (final r in requests) encodeRequest(r),
];

/// The only header a request sent from a proposal may carry; a sign-in's
/// credential is added by the driver, never written here.
const _headersSent = {'content-type'};

/// [input] as the requests to send, each read by is_effects's own codec,
/// then refused when it is a GET, which is a [FetchFromWeb], carries a
/// header other than `content-type`, or names a granted path prefix, which
/// only a grant gives; and refused when there are none. Throws a
/// [FormatException] naming the part.
List<Request> _requestsFromJson(Object? input, [String field = 'requests']) {
  if (input is! List<Object?>) throw FormatException('$field: not a list');
  if (input.isEmpty) throw FormatException('$field: no requests');
  return [
    for (final (i, json) in input.indexed)
      switch (decodeRequest(json, '$field[$i]')) {
        Request(method: Method.get) => throw FormatException(
          '$field[$i].method: a GET is a fetch',
        ),
        Request(:final headers)
            when !headers.keys.every(
              (h) => _headersSent.contains(h.toLowerCase()),
            ) =>
          throw FormatException(
            '$field[$i].headers: only content-type may be sent',
          ),
        Request(grantedPathPrefix: _?) => throw FormatException(
          '$field[$i].grantedPathPrefix: a grant gives it, never a proposal',
        ),
        final request => request,
      },
  ];
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
