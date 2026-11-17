part of 'action.dart';

// A model call is an action the loop proposes for itself
// (https://github.com/enspyrco/intersyntactic/pull/1168; Nick, 17 Nov:
// "shit so the model call should really go through the airlock hey?", then
// "we do it tonight"). What a step sends is in the record before it is
// sent: the loop records each text it rendered, the system prompt and the
// request, as pieces (Nick, 12 Nov: byte ranges of the exact bytes sent,
// joined and compared before sending, whole when it won't split), then a
// [ModelRequest] naming them. The airlock joins each text's pieces, checks
// the join against its sha256, and hands the model driver exactly those
// bytes, so what it allows is what is sent.

/// One run of a text a model request sends, in the order
/// [RecordedText.pieces] names it: recorded as an entry of its own, and
/// named by that entry, so the request shows each piece was recorded
/// through the record service, by a sender it allows, before it was sent. A
/// piece repeated from an earlier request (the history so far) is a new
/// entry with a new id, since an entry's id hashes its previous too, but its
/// bytes are kept once: the logbook stores an entry's content as an object,
/// by sha256, however many entries name it.
///
/// Its text is a run of the exact text the loop rendered: of the system
/// prompt, or of the request (the API's JSON, or the message a program
/// reads). A turn's entry is never a piece, since its bytes are not the
/// text's.
final class ModelRequestPiece {
  const ModelRequestPiece(this.text);

  /// The entry's kind in the logbook.
  static const kind = 'model-request-piece';

  /// [json] read back, strictly: anything but exactly a `text` throws a
  /// [FormatException] naming the part.
  static ModelRequestPiece fromJson(
    Object? json, [
    String field = 'modelRequestPiece',
  ]) {
    final map = _object(field, json);
    if (map.keys.any((key) => key != 'text')) {
      throw FormatException(
        '$field: unexpected ${map.keys.where((k) => k != 'text')}',
      );
    }
    return ModelRequestPiece(_string('$field.text', map['text']));
  }

  final String text;

  Object? toJson() => {'text': text};
}

/// One text a model request sends, as the record holds it: the
/// [ModelRequestPiece] entries it is made of, in order, and the sha256 of
/// its UTF-8 bytes, which is what is sent.
final class RecordedText {
  RecordedText({required Iterable<EntryId> pieces, required this.sha256})
    : pieces = List.unmodifiable(pieces) {
    if (this.pieces.isEmpty) {
      throw ArgumentError.value(pieces, 'pieces', 'a text has a piece');
    }
  }

  /// [json] read back, strictly, as [ModelRequest.fromJson] reads its
  /// parts.
  static RecordedText fromJson(Object? json, String field) {
    final map = _object(field, json);
    const keys = {'pieces', 'sha256'};
    if (map.keys.any((key) => !keys.contains(key))) {
      throw FormatException(
        '$field: unexpected ${map.keys.where((k) => !keys.contains(k))}',
      );
    }
    final pieces = _entryIds('$field.pieces', map['pieces']);
    if (pieces.isEmpty) throw FormatException('$field.pieces: none');
    return RecordedText(
      pieces: pieces,
      sha256:
          ObjectId.parse(_string('$field.sha256', map['sha256'])) ??
          (throw FormatException('$field.sha256: not a sha256')),
    );
  }

  /// The [ModelRequestPiece] entries, in order; one, when the text is not
  /// split.
  final List<EntryId> pieces;

  /// The sha256 of the text's UTF-8 bytes: what [join] checks the pieces
  /// against.
  final ObjectId sha256;

  /// The text, from [texts], the text of each of [pieces] in order, joined;
  /// or [Refused] with why it is not the text this names. The airlock gives
  /// the model driver nothing else.
  Outcome<String> join(List<String> texts) {
    if (texts.length != pieces.length) {
      return Refused(
        '${texts.length} pieces given, the request names ${pieces.length}',
      );
    }
    final joined = texts.join();
    return ObjectId.of(utf8.encode(joined)) == sha256
        ? Ran(joined)
        : const Refused('the pieces do not join to the text the request names');
  }

  Object? toJson() => {
    'pieces': [for (final id in pieces) id.hex],
    'sha256': sha256.hex,
  };
}

/// What a step sends the model, recorded before it is sent: its
/// [systemPrompt] and its [request], each as a [RecordedText], and the
/// turns they were rendered from.
///
/// Written by the loop on its trajectory's chain, which only its loop user
/// writes, so it names no trajectory, as a [Proposal] names none.
final class ModelRequest {
  ModelRequest({
    required this.systemPrompt,
    required this.request,
    Iterable<EntryId> builtFrom = const [],
  }) : builtFrom = List.unmodifiable(builtFrom);

  /// The entry's kind in the logbook.
  static const kind = 'model-request';

  /// [json] read back, strictly: a key it does not know, or a part that is
  /// not what it names, throws a [FormatException] naming the part.
  static ModelRequest fromJson(Object? json, [String field = 'modelRequest']) {
    final map = _object(field, json);
    const keys = {'systemPrompt', 'request', 'builtFrom'};
    if (map.keys.any((key) => !keys.contains(key))) {
      throw FormatException(
        '$field: unexpected ${map.keys.where((k) => !keys.contains(k))}',
      );
    }
    return ModelRequest(
      systemPrompt: RecordedText.fromJson(
        map['systemPrompt'],
        '$field.systemPrompt',
      ),
      request: RecordedText.fromJson(map['request'], '$field.request'),
      builtFrom: _entryIds('$field.builtFrom', map['builtFrom']),
    );
  }

  /// The system prompt the model is given in place of its own.
  final RecordedText systemPrompt;

  /// What it is asked: the API's JSON, or the one message a program reads.
  final RecordedText request;

  /// The turns the texts were rendered from, in order: where they came
  /// from, for a reader of the record. Not checked here: the texts are what
  /// is sent.
  final List<EntryId> builtFrom;

  Object? toJson() => {
    'systemPrompt': systemPrompt.toJson(),
    'request': request.toJson(),
    'builtFrom': [for (final id in builtFrom) id.hex],
  };
}

List<EntryId> _entryIds(String field, Object? json) => switch (json) {
  final List<Object?> list => [
    for (final (i, id) in list.indexed)
      EntryId.parse(_string('$field[$i]', id)) ??
          (throw FormatException('$field[$i]: not an entry id')),
  ],
  _ => throw FormatException('$field: not a list'),
};
