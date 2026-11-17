import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

/// [texts] as the record would hold them, each a piece entry, and the
/// [RecordedText] naming them.
RecordedText recorded(List<String> texts) => RecordedText(
  pieces: [
    for (final (i, text) in texts.indexed)
      EntryId.of(utf8.encode('$i ${jsonEncode(ModelRequestPiece(text))}')),
  ],
  sha256: ObjectId.of(utf8.encode(texts.join())),
);

void main() {
  // A request cut where it won't split mid-message: the history so far,
  // then the new turn. The system prompt is whole.
  const system = ['You are reviewing a case file. Héllo, naïve café.'];
  const asked = [
    'Turn 1: what does clause 4 say?\n',
    'Turn 2: and how does it bear on the lease?\n',
  ];
  final request = ModelRequest(
    systemPrompt: recorded(system),
    request: recorded(asked),
    builtFrom: [EntryId.of(utf8.encode('turn 1'))],
  );

  test('each text joins only as recorded, in order', () {
    expect((request.request.join(asked) as Ran<String>).output, asked.join());
    expect(
      (request.systemPrompt.join(system) as Ran<String>).output,
      system.join(),
    );
    for (final wrong in [
      [asked[0], '${asked[1]} '],
      asked.reversed.toList(),
      [asked[0]],
      [...asked, ''],
    ]) {
      expect(request.request.join(wrong), isA<Refused>(), reason: '$wrong');
    }
    // Each half is checked against its own hash, never the other's.
    expect(request.request.join(system), isA<Refused>());
    expect(request.systemPrompt.join(asked), isA<Refused>());
  });

  test('a model request and its pieces read back as written', () {
    final back = ModelRequest.fromJson(
      jsonDecode(jsonEncode(request.toJson())),
    );
    expect(back.request.pieces, request.request.pieces);
    expect(back.request.sha256, request.request.sha256);
    expect(back.systemPrompt.pieces, request.systemPrompt.pieces);
    expect(back.systemPrompt.sha256, request.systemPrompt.sha256);
    expect(back.builtFrom, request.builtFrom);
    expect(back.request.join(asked), isA<Ran<String>>());
    expect(
      ModelRequestPiece.fromJson(
        jsonDecode(jsonEncode(ModelRequestPiece(asked[1]).toJson())),
      ).text,
      asked[1],
    );
    expect(ModelRequest.kind, 'model-request');
    expect(ModelRequestPiece.kind, 'model-request-piece');
  });

  test('a model request and its pieces are read strictly', () {
    final good =
        jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>;
    final text = good['request']! as Map<String, Object?>;
    for (final json in [
      null,
      <String, Object?>{},
      {...good, 'trajectory': 'x'},
      {...good, 'systemPrompt': null},
      {...good, 'builtFrom': null},
      for (final bad in <Object?>[
        {...text, 'pieces': <Object?>[]},
        {
          ...text,
          'pieces': ['nope'],
        },
        {...text, 'sha256': 'nope'},
        {...text, 'body': text['sha256']},
        {'pieces': text['pieces']},
      ])
        {...good, 'request': bad},
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
