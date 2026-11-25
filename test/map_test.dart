import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

/// Answers every write as a new file, and keeps the name of each program
/// proposed.
final class _Proposer implements ProposesActions {
  final proposed = <String>[];

  @override
  Future<Outcome<O>> propose<I, O>(Program<I, O> program, I input) async {
    proposed.add(program.name);
    return switch (const Ran(Wrote(replaced: false))) {
      final Outcome<O> wrote when program is WriteFile => wrote,
      _ => NothingRan('not a write: ${program.name}'),
    };
  }
}

void main() {
  test('map proposes nothing, and applies its function once the action '
      'answers', () async {
    final proposer = _Proposer();
    var applied = 0;

    Result<String> result = Program.write
        .runOrFail(FileText(RelativePath('notes.txt'), 'hi'), then: Done.new)
        .map((wrote) {
          applied++;
          return wrote.replaced ? 'replaced' : 'created';
        });

    expect(result, isA<Action<String>>());
    expect(applied, 0);
    expect(proposer.proposed, isEmpty);

    while (result is Action<String>) {
      result = await result.next(proposer);
    }

    expect(
      result,
      isA<Done<String>>().having((d) => d.value, 'value', 'created'),
    );
    expect(applied, 1);
    expect(proposer.proposed, ['write']);
  });

  test('a failure maps to itself', () {
    const failed = Failed('no');
    expect(identical(failed.map((Never answer) => 'unused'), failed), isTrue);
  });

  test('runOrFail fails the tool unless the action ran to the end', () async {
    Future<Result<String>> after(Outcome<Wrote> outcome) => Program.write
        .runOrFail(
          FileText(RelativePath('a'), ''),
          then: (_) => const Done('ok'),
        )
        .next(_Answering(outcome));
    expect(await after(const Ran(Wrote(replaced: true))), isA<Done<String>>());
    expect(
      await after(const NothingRan('denied')),
      isA<Failed>().having((f) => f.why, 'why', 'denied'),
    );
    expect(
      await after(const StoppedPartway(why: 'disk full', done: null)),
      isA<Failed>().having((f) => f.why, 'why', 'stopped partway: disk full'),
    );
  });
}

/// Answers the one write proposed with [outcome].
final class _Answering implements ProposesActions {
  _Answering(this.outcome);

  final Outcome<Wrote> outcome;

  @override
  Future<Outcome<O>> propose<I, O>(Program<I, O> program, I input) async =>
      switch (outcome) {
        final Outcome<O> answer => answer,
        _ => throw StateError('not a write: ${program.name}'),
      };
}
