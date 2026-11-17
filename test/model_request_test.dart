import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

void main() {
  // A body cut where it won't split mid-message: a fixed prefix, the
  // history, the new turn, a fixed suffix.
  const texts = [
    '{"model":"m","messages":[',
    '{"role":"user","content":"hello"}',
    ',{"role":"user","content":"and again"}',
    ']}',
  ];
  final pieceIds = [
    for (final text in texts)
      EntryId.of(utf8.encode(jsonEncode(ModelRequestPiece(text).toJson()))),
  ];
  final request = ModelRequest(
    pieces: pieceIds,
    body: ObjectId.of(utf8.encode(texts.join())),
    builtFrom: [EntryId.of(utf8.encode('turn 1'))],
  );

  test('the pieces join to the body only as recorded, in order', () {
    expect(request.join(texts), isA<Ran<String>>());
    expect((request.join(texts) as Ran<String>).output, texts.join());
    for (final wrong in [
      [...texts.take(3), ']} '],
      texts.reversed.toList(),
      texts.take(3).toList(),
      [...texts, ''],
    ]) {
      expect(request.join(wrong), isA<Refused>(), reason: '$wrong');
    }
  });

  test('a model request and its pieces read back as written', () {
    final back = ModelRequest.fromJson(
      jsonDecode(jsonEncode(request.toJson())),
    );
    expect(back.pieces, request.pieces);
    expect(back.body, request.body);
    expect(back.builtFrom, request.builtFrom);
    expect(back.join(texts), isA<Ran<String>>());
    expect(
      ModelRequestPiece.fromJson(
        jsonDecode(jsonEncode(ModelRequestPiece(texts[1]).toJson())),
      ).text,
      texts[1],
    );
    expect(ModelRequest.kind, 'model-request');
    expect(ModelRequestPiece.kind, 'model-request-piece');
  });

  test('a model request and its pieces are read strictly', () {
    final good =
        jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>;
    for (final json in [
      null,
      <String, Object?>{},
      {...good, 'trajectory': pieceIds.first.hex},
      {...good, 'pieces': <Object?>[]},
      {
        ...good,
        'pieces': ['nope'],
      },
      {...good, 'body': 'nope'},
      {...good, 'builtFrom': null},
    ]) {
      expect(
        () => ModelRequest.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
    for (final json in [
      null,
      <String, Object?>{},
      {'text': 7},
      {'text': 'x', 'role': 'user'},
    ]) {
      expect(
        () => ModelRequestPiece.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
