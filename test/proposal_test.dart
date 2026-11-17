import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show
        LogAirlock,
        MemoryFiles,
        RecordedPrograms,
        RecordedWeb,
        answerOf,
        hart,
        start,
        teams,
        webRequest,
        writeAndFormat;

/// A journey path's chain and the airlock's, in memory: each `proposed`
/// entry the loop writes goes through `jsonEncode` and back, as the journal
/// would keep it, and is named by the hash of its bytes; the airlock service
/// considers it on [path], and the loop is handed the `returned` entry that
/// names it, through `jsonEncode` and back, as loop_launcher would hand it.
/// Places are ints. Keeps why each rejected entry was rejected.
final class RecordedLink implements ProposesActionsThroughTheRecord {
  RecordedLink(this.path, this.airlock);

  final JourneyPath<Set<String>, int> path;
  final LogAirlock airlock;
  final rejected = <String>[];

  /// What loop_launcher would hand the loop, when a test wants another
  /// answer.
  Object? Function(Object? outcome) answerWith = (outcome) => outcome;

  @override
  Future<Object?> propose(Object? proposal) async {
    final bytes = utf8.encode(jsonEncode(proposal));
    final proposed = EntryId.of(bytes);
    switch (Proposal.read(utf8.decode(bytes))) {
      case Rejected(:final why):
        rejected.add(why);
        airlock.returned[proposed] = ReturnedProposal.refused(proposed, why);
      case final Proposal proposal:
        switch (proposal.place) {
          case final int place:
            await path.consider(proposal, place, proposed: proposed);
          default:
            rejected.add('not a place');
            airlock.returned[proposed] = ReturnedProposal.refused(
              proposed,
              'not a place',
            );
        }
    }
    final answer = ReturnedProposal.fromJson(
      JsonObject.decode(jsonEncode(airlock.returned[proposed]!.toJson())),
    );
    expect(answer.proposed, proposed);
    return answerWith(answer.outcome);
  }
}

/// The agent loop's apex at [place] on [link]'s path.
Apex loopApex(RecordedLink link, {int place = 1}) =>
    Apex.through(link, place: place);

void main() {
  test(
    'an action proposed through the record is decided, recorded and '
    'carried out as in the airlock, and its continuation runs in the loop',
    () async {
      final airlock = LogAirlock();
      final files = MemoryFiles();
      final link = RecordedLink(
        start(airlock, [files, RecordedPrograms()]),
        airlock,
      );
      expect(
        await answerOf(writeAndFormat('a.dart'), loopApex(link, place: 3)),
        'Formatted 1 file',
      );
      expect(files.files, {'a.dart': 'void main() {}'});
      expect(airlock.log, [
        '3: allow write a.dart',
        '3: ran write a.dart',
        '3: allow dart format a.dart',
        '3: ran dart format a.dart',
      ]);
      expect(link.rejected, isEmpty);
    },
  );

  test("what an action returned reaches the loop from the record, in full, and "
      'its entries name the proposal', () async {
    final airlock = LogAirlock();
    final files = MemoryFiles()..files['a.dart'] = 'the text';
    final path = start(airlock, [files]);
    final link = RecordedLink(path, airlock);
    final entries = <Entry<int>>[];
    path.entries.listen(entries.add);
    expect(
      await answerOf(
        Program.read.runOrRefusal(
          RelativePath('a.dart'),
          then: (read) => Done(switch (read) {
            ReadText(:final text) => text,
            _ => 'not read',
          }),
        ),
        loopApex(link),
      ),
      'the text',
    );
    expect(entries, hasLength(2));
    final proposed = (entries[0] as Decided<int>).proposed;
    expect(proposed, isNotNull);
    expect((entries[1] as Returned<int>).proposed, proposed);
    expect(airlock.returned.keys, [proposed]);
    expect(
      jsonEncode(airlock.returned[proposed]!.toJson()),
      contains('the text'),
    );
  });

  test(
    'a web request through the record is drawn from recorded entries',
    () async {
      final web = RecordedWeb();
      final airlock = LogAirlock();
      final turn = airlock.remember('done');
      final path = start(airlock, [web], rules: {'$teams as $hart'});
      expect(
        await answerOf(
          webRequest(teams, hart, entries: [turn]),
          loopApex(RecordedLink(path, airlock)),
        ),
        '201 activity-1',
      );
      expect(web.requests.single.body, 'done');
    },
  );

  test('a refusal comes back through the record in its own words', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles()], rules: {'read'});
    expect(
      await answerOf(
        writeAndFormat('a.dart'),
        loopApex(RecordedLink(path, airlock)),
      ),
      'failed: not in the rules',
    );
  });

  test(
    'an action proposed in-process has no entry in the record to answer',
    () async {
      final airlock = LogAirlock();
      final path = start(airlock, [MemoryFiles()]);
      final returned = <Returned<int>>[];
      path.entries.listen((e) => e is Returned<int> ? returned.add(e) : null);
      await answerOf(writeAndFormat('a.dart'), path.at(1));
      expect(returned, hasLength(2));
      expect(returned.map(ReturnedProposal.of), everyElement(isNull));
    },
  );

  test('input that its type would not accept is rejected at the boundary, '
      'naming the field, and answered refused', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [RecordedWeb()], rules: {'$teams as $hart'});
    final link = RecordedLink(path, airlock);
    final proposal = {'place': 1, 'program': 'web'};
    Map<String, Object?> requestWith(Map<String, Object?> change) => {
      'origin': '$teams',
      'method': 'post',
      'path': '/v3/conversations/c/activities',
      'signIn': 'hart-bot',
      'headers': <String, String>{},
      'renderer': 'teams-reply',
      'entries': <String>[],
      ...change,
    };
    final answers = [
      for (final change in [
        {'path': '//evil.example/x'},
        {
          'headers': {'Authorization': 'Bearer x'},
        },
        {'renderer': 'Teams Reply'},
        {
          'entries': ['not an id'],
        },
      ])
        await link.propose({...proposal, 'input': requestWith(change)}),
    ];
    expect(link.rejected, hasLength(4));
    expect(link.rejected[0], startsWith('input.path'));
    expect(link.rejected[1], startsWith('input.headers'));
    expect(link.rejected[2], startsWith('input.renderer'));
    expect(link.rejected[3], startsWith('input.entries'));
    expect(
      answers.map(
        (a) => decodeOutcome<Never>(a, (_, _) => throw StateError('ran')),
      ),
      everyElement(isA<Refused>()),
    );
    expect(airlock.log, isEmpty);
  });

  test('what is not a proposal is rejected', () async {
    final airlock = LogAirlock();
    final link = RecordedLink(start(airlock, [MemoryFiles()]), airlock);
    final proposal = {'place': 1, 'input': 'a.dart'};
    for (final request in [
      null,
      'read a.dart',
      {...proposal, 'program': 'delete'},
      {...proposal, 'program': 'start'},
      {...proposal, 'program': 'read', 'place': 'first'},
    ]) {
      await link.propose(request);
    }
    expect(link.rejected, [
      'not a proposal',
      'not a proposal',
      'not a program: delete',
      'not a program: start',
      'not a place',
    ]);
    expect(airlock.log, isEmpty);
  });

  test('an answer that is no outcome ends the call', () async {
    final airlock = LogAirlock();
    final link = RecordedLink(start(airlock, [MemoryFiles()]), airlock)
      ..answerWith = (_) => {'kind': 'maybe'};
    await expectLater(
      answerOf(writeAndFormat('a.dart'), loopApex(link)),
      throwsFormatException,
    );
  });

  test('a returned entry reads back only with an entry id it answers', () {
    final id = EntryId.of(utf8.encode('proposed'));
    final refused = ReturnedProposal.refused(id, 'why');
    final back = ReturnedProposal.fromJson(
      JsonObject.decode(jsonEncode(refused.toJson())),
    );
    expect(back.proposed, id);
    expect(back.outcome, refused.outcome);
    for (final json in [
      null,
      {'outcome': null},
      {'proposed': 'nope', 'outcome': null},
    ]) {
      expect(
        () => ReturnedProposal.fromJson(JsonObject.decode(jsonEncode(json))),
        throwsFormatException,
      );
    }
  });
}
