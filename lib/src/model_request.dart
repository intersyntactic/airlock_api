part of 'action.dart';

// A model call is an action the loop proposes for itself
// (https://github.com/enspyrco/intersyntactic/pull/1168; Nick, 17 Nov:
// "shit so the model call should really go through the airlock hey?", then
// "we do it tonight"). What a step sends is in the record before it is
// sent: the loop records the exact body it rendered, as pieces (Nick, 12
// Nov: byte ranges of the exact bytes sent, joined and compared before
// sending, whole when it won't split), then a [ModelRequest] naming them.
// The airlock joins the pieces, checks the join against [ModelRequest.body],
// and hands the model driver exactly those bytes, so what it allows is what
// is sent.

/// One run of a model request's body, in the order [ModelRequest.pieces]
/// names it: recorded as an entry of its own, and named there by its
/// content, the journal object the entry points at. So a piece repeated
/// from an earlier request (the history so far) has the same id and its
/// bytes are kept once, wherever on the chain it was recorded; its entry's
/// own id, which hashes its previous too, differs each time.
///
/// Its text is a run of the exact body the loop rendered: of the API's JSON,
/// or of the prompt a program reads. A turn's entry is never a piece, since
/// its bytes are not the body's.
final class ModelRequestPiece {
  const ModelRequestPiece(this.text);

  /// The entry's kind in the journal.
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

/// What a step sends the model, recorded before it is sent: the
/// [ModelRequestPiece]s its body is made of, by content, in order, the
/// sha256 of that body, and the turns it was rendered from.
///
/// The pieces' places on the chain are not what is checked: this entry,
/// which only the loop user can write, commits to [body], and [join]
/// gives nothing that does not hash to it.
///
/// Written by the loop on its trajectory's chain, which only its loop user
/// writes, so it names no trajectory, as a [Proposal] names none.
final class ModelRequest {
  ModelRequest({
    required Iterable<ObjectId> pieces,
    required this.body,
    Iterable<EntryId> builtFrom = const [],
  }) : pieces = List.unmodifiable(pieces),
       builtFrom = List.unmodifiable(builtFrom) {
    if (this.pieces.isEmpty) {
      throw ArgumentError.value(pieces, 'pieces', 'a body has a piece');
    }
  }

  /// The entry's kind in the journal.
  static const kind = 'model-request';

  /// [json] read back, strictly: a key it does not know, or a part that is
  /// not what it names, throws a [FormatException] naming the part.
  static ModelRequest fromJson(Object? json, [String field = 'modelRequest']) {
    final map = _object(field, json);
    const keys = {'pieces', 'body', 'builtFrom'};
    if (map.keys.any((key) => !keys.contains(key))) {
      throw FormatException(
        '$field: unexpected ${map.keys.where((k) => !keys.contains(k))}',
      );
    }
    List<T> ids<T>(String name, T? Function(String) parse, String what) =>
        switch (map[name]) {
          final List<Object?> list => [
            for (final (i, id) in list.indexed)
              parse(_string('$field.$name[$i]', id)) ??
                  (throw FormatException('$field.$name[$i]: not $what')),
          ],
          _ => throw FormatException('$field.$name: not a list'),
        };
    final pieces = ids('pieces', ObjectId.parse, 'an object id');
    if (pieces.isEmpty) throw FormatException('$field.pieces: none');
    return ModelRequest(
      pieces: pieces,
      body:
          ObjectId.parse(_string('$field.body', map['body'])) ??
          (throw FormatException('$field.body: not a sha256')),
      builtFrom: ids('builtFrom', EntryId.parse, 'an entry id'),
    );
  }

  /// The [ModelRequestPiece]s the body is made of, in order, each by the
  /// journal object its entry points at; one, when the body is not split.
  final List<ObjectId> pieces;

  /// The sha256 of the body's UTF-8 bytes: what [join] checks the pieces
  /// against.
  final ObjectId body;

  /// The turns the body was rendered from, in order: where it came from,
  /// for a reader of the record. Not checked here: [body] is what is
  /// sent.
  final List<EntryId> builtFrom;

  /// The body, from [texts], the text of each of [pieces] in order, joined;
  /// or [Refused] with why it is not the body this request names. The
  /// airlock gives the model driver nothing else.
  Outcome<String> join(List<String> texts) {
    if (texts.length != pieces.length) {
      return Refused(
        '${texts.length} pieces given, the request names ${pieces.length}',
      );
    }
    final joined = texts.join();
    return ObjectId.of(utf8.encode(joined)) == body
        ? Ran(joined)
        : const Refused('the pieces do not join to the body the request names');
  }

  Object? toJson() => {
    'pieces': [for (final id in pieces) id.hex],
    'body': body.hex,
    'builtFrom': [for (final id in builtFrom) id.hex],
  };
}
