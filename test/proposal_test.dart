import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:test/test.dart';

import 'contract_test.dart'
    show
        LogAirlock,
        MemoryFiles,
        RecordedPrograms,
        RecordedWeb,
        follow,
        hart,
        send,
        start,
        teams,
        writeAndFormat;

/// The airlock service's side of a link, in memory: each request and answer
/// goes through `jsonEncode` and back, as it would over a socket, so
/// anything that is not JSON fails here. Places are ints. Keeps why each
/// rejected request was rejected, as the service would record it.
///
/// The kernel reports the socket's peer; here [peer] does, and when it is
/// null the peer is the path's own loop user, as for an honest loop.
final class ServiceLink implements AirlockLink {
  ServiceLink(Iterable<JourneyPath<Set<String>, int>> paths, {this.peer})
    : paths = {for (final path in paths) path.id: path};

  final Map<JourneyPathId, JourneyPath<Set<String>, int>> paths;
  final rejected = <String>[];
  final LoopUser? peer;

  /// What the service would send back, when a test wants another answer.
  Object? Function(Object? answer) answerWith = (answer) => answer;

  @override
  Future<Object?> propose(Object? request) async {
    final ProposalAnswer answer = switch (Proposal.read(_wire(request))) {
      final Rejected rejected => rejected,
      final Proposal proposal => switch ((
        paths[proposal.journeyPath],
        proposal.place,
      )) {
        (null, _) => Rejected('no journey path ${proposal.journeyPath}'),
        (final path?, final int place) => await path.consider(
          proposal,
          place,
          from: peer ?? path.loopUser,
        ),
        _ => const Rejected('not a place'),
      },
    };
    if (answer case Rejected(:final why)) rejected.add(why);
    return answerWith(_wire(answer.json));
  }

  Object? _wire(Object? json) => jsonDecode(jsonEncode(json));
}

/// The agent loop's apex at [place] on [path], through [link], holding the
/// token as text, the way the loop is handed it.
Apex loopApex(
  ServiceLink link,
  JourneyPath<Object?, Object?> path, {
  int place = 1,
  String? token,
}) => Apex.through(
  link,
  journeyPath: path.id,
  token: PathToken.parse(token ?? path.token.hex)!,
  place: place,
);

void main() {
  test('a run proposed through the link is decided, recorded and run as '
      'in the airlock, and its continuation runs in the loop', () async {
    final airlock = LogAirlock();
    final files = MemoryFiles();
    final path = start(airlock, [files, RecordedPrograms()]);
    final link = ServiceLink([path]);
    expect(
      await follow(writeAndFormat('a.dart'), loopApex(link, path, place: 3)),
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
  });

  test('a send through the link is drawn from recorded entries', () async {
    final web = RecordedWeb();
    final airlock = LogAirlock();
    final turn = airlock.remember('done');
    final path = start(airlock, [web], rules: {'$teams as $hart'});
    expect(
      await follow(
        send(teams, hart, entries: [turn]),
        loopApex(ServiceLink([path]), path),
      ),
      '201 activity-1',
    );
    expect(web.sent.single.body, 'done');
  });

  test('a refusal comes back through the link in its own words', () async {
    final path = start(LogAirlock(), [MemoryFiles()], rules: {'read'});
    expect(
      await follow(
        writeAndFormat('a.dart'),
        loopApex(ServiceLink([path]), path),
      ),
      'failed: not in the rules',
    );
  });

  test('a wrong token is rejected, and recorded in no journey path', () async {
    final airlock = LogAirlock();
    final files = MemoryFiles();
    final path = start(airlock, [files]);
    final link = ServiceLink([path]);
    expect(
      await follow(
        writeAndFormat('a.dart'),
        loopApex(link, path, token: '0' * 64),
      ),
      "failed: not this journey path's token",
    );
    expect(files.files, isEmpty);
    expect(airlock.log, isEmpty);
    expect(link.rejected, ["not this journey path's token"]);
  });

  test("a proposal from another user is rejected, even with the path's "
      'token, and recorded in no journey path', () async {
    final airlock = LogAirlock();
    final files = MemoryFiles();
    final path = start(airlock, [files]);
    final link = ServiceLink([path], peer: LoopUser.parse('loop-9'));
    expect(
      await follow(writeAndFormat('a.dart'), loopApex(link, path)),
      "failed: not this journey path's loop user: loop-9",
    );
    expect(files.files, isEmpty);
    expect(airlock.log, isEmpty);
  });

  test("one path's token is rejected on another", () async {
    final airlock = LogAirlock();
    final mine = start(airlock, [MemoryFiles()]);
    final theirs = JourneyPath<Set<String>, int>(
      id: JourneyPathId.of(utf8.encode('started theirs')),
      drivers: [MemoryFiles()],
      airlock: airlock,
      rules: const {'write'},
      loopUser: LoopUser.parse('loop-2')!,
      journeyUser: JourneyUser.parse('journey-2')!,
    );
    expect(
      await follow(
        writeAndFormat('a.dart'),
        loopApex(ServiceLink([mine, theirs]), theirs, token: mine.token.hex),
      ),
      "failed: not this journey path's token",
    );
    expect(airlock.log, isEmpty);
  });

  test('a proposal naming another journey path is rejected by the path it '
      'reached', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [MemoryFiles()]);
    final other = JourneyPathId.of(utf8.encode('started elsewhere'));
    final answer = await path.consider(
      switch (Proposal.read({
        'journeyPath': other.hex,
        'token': path.token.hex,
        'place': 1,
        'program': 'read',
        'input': 'a.dart',
      })) {
        final Proposal proposal => proposal,
        final Rejected r => fail(r.why),
      },
      1,
      from: path.loopUser,
    );
    expect(answer, isA<Rejected>());
    expect(airlock.log, isEmpty);
  });

  test('input that its type would not accept is rejected at the boundary, '
      'naming the field', () async {
    final airlock = LogAirlock();
    final path = start(airlock, [RecordedWeb()], rules: {'$teams as $hart'});
    final link = ServiceLink([path]);
    final proposal = {
      'journeyPath': path.id.hex,
      'token': path.token.hex,
      'place': 1,
      'program': 'web',
    };
    Map<String, Object?> sendWith(Map<String, Object?> change) => {
      'origin': '$teams',
      'method': 'post',
      'path': '/v3/conversations/c/activities',
      'signIn': 'hart-bot',
      'headers': <String, String>{},
      'renderer': 'teams-reply',
      'entries': <String>[],
      ...change,
    };
    for (final change in [
      {'path': '//evil.example/x'},
      {
        'headers': {'Authorization': 'Bearer x'},
      },
      {'renderer': 'Teams Reply'},
      {
        'entries': ['not an id'],
      },
    ]) {
      await link.propose({...proposal, 'input': sendWith(change)});
    }
    expect(link.rejected, hasLength(4));
    expect(link.rejected[0], startsWith('input.path'));
    expect(link.rejected[1], startsWith('input.headers'));
    expect(link.rejected[2], startsWith('input.renderer'));
    expect(link.rejected[3], startsWith('input.entries'));
    expect(airlock.log, isEmpty);
  });

  test('what is not a proposal is rejected', () async {
    final path = start(LogAirlock(), [MemoryFiles()]);
    final link = ServiceLink([path]);
    final proposal = {
      'journeyPath': path.id.hex,
      'token': path.token.hex,
      'place': 1,
      'input': 'a.dart',
    };
    for (final request in [
      null,
      'read a.dart',
      {...proposal, 'program': 'delete'},
      {...proposal, 'program': 'start'},
      {...proposal, 'program': 'read', 'token': 'short'},
      {...proposal, 'program': 'read', 'journeyPath': 'nope'},
    ]) {
      await link.propose(request);
    }
    expect(link.rejected, [
      'not a proposal',
      'not a proposal',
      'not a program: delete',
      'not a program: start',
      'not a token',
      'not a journey path: nope',
    ]);
  });

  test('an answer that is no outcome ends the call', () async {
    final path = start(LogAirlock(), [MemoryFiles()]);
    final link = ServiceLink([path])..answerWith = (_) => {'kind': 'maybe'};
    await expectLater(
      follow(writeAndFormat('a.dart'), loopApex(link, path)),
      throwsFormatException,
    );
  });

  test('a token reads back from its text, hides itself, and is new for '
      'each journey path', () {
    final a = start(LogAirlock(), []).token;
    final b = start(LogAirlock(), []).token;
    expect(PathToken.parse(a.hex)!.hex, a.hex);
    expect(a.hex, isNot(b.hex));
    expect('$a', isNot(contains(a.hex)));
    expect(
      ['', 'A' * 64, '0' * 63, '0' * 65, 'g' * 64].map(PathToken.parse),
      everyElement(isNull),
    );
  });
}
