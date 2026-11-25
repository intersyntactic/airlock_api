part of 'action.dart';

Object? _requestsToJson(List<ProposedRequest> requests) => [
  for (final r in requests) encodeProposedRequest(r),
];

/// The only header a request sent from a proposal may carry; a sign-in's
/// credential is added by the driver, never written here.
const _headersSent = {'content-type'};

/// [input] as the requests to send, each read by is_effects's own codec,
/// which refuses a granted path prefix, since only a grant gives one; then
/// refused when it is a GET, which is a [FetchFromWeb], or carries a header
/// other than `content-type`; and refused when there are none. Throws a
/// [FormatException] naming the part.
List<ProposedRequest> _requestsFromJson(
  Object? input, [
  String field = 'requests',
]) {
  if (input is! List<Object?>) throw FormatException('$field: not a list');
  if (input.isEmpty) throw FormatException('$field: no requests');
  return [
    for (final (i, json) in input.indexed)
      switch (decodeProposedRequest(json, '$field[$i]')) {
        ProposedRequest(method: Method.get) => throw FormatException(
          '$field[$i].method: a GET is a fetch',
        ),
        ProposedRequest(:final headers)
            when !headers.keys.every(
              (h) => _headersSent.contains(h.toLowerCase()),
            ) =>
          throw FormatException(
            '$field[$i].headers: only content-type may be sent',
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
  final by = switch (json.stringOrNull('by')) {
    null => null,
    final name =>
      DecidedBy.values.asNameMap()[name] ??
          (throw FormatException('$field.by: not rules or person')),
  };
  final reliedOn = [
    for (final (i, hex) in (json.stringsOrNull('reliedOn') ?? []).indexed)
      EntryId.parse(hex) ??
          (throw FormatException('$field.reliedOn[$i]: not an entry id')),
  ];
  if (!json.boolean('allow')) {
    return Deny(
      json.string('why'),
      by: by ?? (throw FormatException('$field.by: missing on a denial')),
      reliedOn: reliedOn,
    );
  }
  final prefixes = [
    for (final (i, raw)
        in (json.stringsOrNull('grantedPathPrefixes') ?? []).indexed)
      PathPrefix.parse(raw) ??
          (throw FormatException(
            '$field.grantedPathPrefixes[$i]: not a path prefix',
          )),
  ];
  final endpoint = switch (json.raw('grantedReplyEndpoint')) {
    null => null,
    final raw => decodeReplyEndpoint(raw, '$field.grantedReplyEndpoint'),
  };
  if (endpoint == null) {
    return Allow(by: by, reliedOn: reliedOn, grantedPathPrefixes: prefixes);
  }
  if (prefixes.isNotEmpty) {
    throw FormatException(
      '$field: grants both path prefixes and a reply endpoint',
    );
  }
  return Allow.toReplyTo(endpoint, by: by, reliedOn: reliedOn);
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
