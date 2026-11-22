part of 'action.dart';

// An agent loop writes an [ActionProposedByAgentLoop] logbook entry on its
// trajectory's chain, which the logbook service takes only from that path's
// loop user. The airlock reads it, decides, and keeps its decision and then
// an [outcomeOfProposedActionKind] logbook entry naming the proposal, with
// what the action came to. loop_launcher hands that entry to the path's
// loop. The airlock has no door of its own.

/// Writes an [ActionProposedByAgentLoop] logbook entry and waits for what the
/// airlock wrote it came to: the transport, which this package does not
/// have. This package joins the two, so a loop never works out an id.
abstract interface class ProposesActionsThroughTheLogbook {
  /// Writes [body] as an [ActionProposedByAgentLoop.kind] logbook entry on
  /// the loop's trajectory's chain, and gives the id the logbook gave it:
  /// the hash of the whole entry as the logbook keeps it, which covers the
  /// entry before it
  /// on the chain. Never a hash of [body] alone.
  Future<EntryId> writeProposal(String body);

  /// The body of the [outcomeOfProposedActionKind] logbook entry that names
  /// [proposed], once the airlock has kept it.
  Future<String> outcomeNaming(EntryId proposed);
}

/// Where in its trajectory a loop proposed an action: in a [turn], one model
/// call and what it caused, either one of the loop's own proposals or an
/// action of one of the intents the model's reply holds. Each is fixed by
/// what the logbook already holds, never by the order things ran in, so a
/// loop that restarts proposes the same actions at the same places, and a
/// place the logbook already answers is one it need not propose again.
///
/// Written `[turn, intent, action]` or `[turn, "model-call" | "reply"]`.
/// Within a turn the model call comes first, then each intent's actions by
/// intent and action, then the reply.
sealed class PlaceInTrajectory implements Comparable<PlaceInTrajectory> {
  const PlaceInTrajectory._(this.turn);

  /// [json], as [toJson] writes it, read back; null when it is not one.
  static PlaceInTrajectory? parse(Object? json) => switch (json) {
    [final int turn, final String wire] when turn >= 0 =>
      LoopProposal.values
          .where((which) => which._wire == wire)
          .map((which) => ProposedByTheLoop._(turn, which))
          .firstOrNull,
    [final int turn, final int intent, final int action]
        when turn >= 0 && intent >= 0 && action >= 0 =>
      ProposedForAnIntent._(turn, intent, action),
    _ => null,
  };

  /// Counted from 0.
  final int turn;

  Object? toJson();

  /// Where this sits within its turn: model call, intents, reply.
  (int, int, int) get _withinTurn;

  @override
  int compareTo(PlaceInTrajectory other) {
    final (a1, a2, a3) = _withinTurn;
    final (b1, b2, b3) = other._withinTurn;
    for (final c in [
      turn.compareTo(other.turn),
      a1.compareTo(b1),
      a2.compareTo(b2),
      a3.compareTo(b3),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  }
}

/// Which of its own proposals the loop makes in a turn, which no intent
/// draws: the model call, and the reply it makes from the turn's final
/// text.
enum LoopProposal {
  modelCall('model-call'),
  reply('reply');

  const LoopProposal(this._wire);

  final String _wire;
}

/// The place of one of the loop's own proposals in [turn].
final class ProposedByTheLoop extends PlaceInTrajectory {
  const ProposedByTheLoop._(super.turn, this.which) : super._();

  /// [which] of [turn], counted from 0.
  factory ProposedByTheLoop.at(int turn, LoopProposal which) => turn >= 0
      ? ProposedByTheLoop._(turn, which)
      : throw ArgumentError('a turn is counted from 0: $turn');

  final LoopProposal which;

  @override
  Object? toJson() => [turn, which._wire];

  @override
  (int, int, int) get _withinTurn => switch (which) {
    LoopProposal.modelCall => (0, 0, 0),
    LoopProposal.reply => (2, 0, 0),
  };

  @override
  bool operator ==(Object other) =>
      other is ProposedByTheLoop && other.turn == turn && other.which == which;

  @override
  int get hashCode => Object.hash(turn, which);

  @override
  String toString() => '$turn.${which._wire}';
}

/// The place of [action] of [intent] in [turn]: the intent is a tool call
/// the model's reply holds, by its place in that reply, and the action is
/// one the tool's steps propose, in the order they propose them.
final class ProposedForAnIntent extends PlaceInTrajectory {
  const ProposedForAnIntent._(super.turn, this.intent, this.action) : super._();

  /// All three counted from 0.
  factory ProposedForAnIntent.at(int turn, int intent, int action) =>
      turn >= 0 && intent >= 0 && action >= 0
      ? ProposedForAnIntent._(turn, intent, action)
      : throw ArgumentError(
          'a place is counted from 0: $turn, $intent, $action',
        );

  final int intent;
  final int action;

  @override
  Object? toJson() => [turn, intent, action];

  @override
  (int, int, int) get _withinTurn => (1, intent, action);

  @override
  bool operator ==(Object other) =>
      other is ProposedForAnIntent &&
      other.turn == turn &&
      other.intent == intent &&
      other.action == action;

  @override
  int get hashCode => Object.hash(turn, intent, action);

  @override
  String toString() => '$turn.$intent.$action';
}

/// A crux in the agent loop for one intent, or one of the loop's own
/// proposals, in one turn: proposes each action's program and input through
/// the logbook at its next place, and keeps the continuation.
final class _ThroughLogbook extends Crux {
  /// Every action of [intent] in [turn], numbered from 0.
  factory _ThroughLogbook.forIntent(
    ProposesActionsThroughTheLogbook link, {
    required int turn,
    required int intent,
  }) {
    final first = ProposedForAnIntent.at(turn, intent, 0);
    return _ThroughLogbook._(
      link,
      (n) => n == 0 ? first : ProposedForAnIntent._(turn, intent, n),
    );
  }

  /// The one action of the loop's own proposal [which] in [turn].
  factory _ThroughLogbook.forTheLoop(
    ProposesActionsThroughTheLogbook link, {
    required int turn,
    required LoopProposal which,
  }) {
    final only = ProposedByTheLoop.at(turn, which);
    return _ThroughLogbook._(link, (n) => n == 0 ? only : null);
  }

  _ThroughLogbook._(this._link, this._placeOf);

  final ProposesActionsThroughTheLogbook _link;

  /// The place of the [n]th action proposed through this crux, or null when
  /// it has none.
  final PlaceInTrajectory? Function(int n) _placeOf;
  int _proposed = 0;

  /// The outcome the airlock wrote to the logbook. An answer that is not
  /// one, or that names another proposal, throws a [FormatException],
  /// ending the call: whether the action reached the world is then not
  /// known here, and the airlock's entries in the logbook say.
  @override
  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input) async {
    final place =
        _placeOf(_proposed++) ??
        (throw StateError(
          "a crux for the loop's own proposal carries one action, not "
          '${program.name} as well',
        ));
    final proposed = await _link.writeProposal(
      jsonEncode({
        'place': place.toJson(),
        ...program._wire.program,
        'input': program._wire.inputToJson(input),
      }),
    );
    return switch (readOutcomeOfProposedAction(
      await _link.outcomeNaming(proposed),
    )) {
      (proposed: final named, :final result) when named == proposed =>
        decodeOutcome(result, program._wire.outputFromJson),
      (proposed: final named, result: _) => throw FormatException(
        'the outcome for $proposed names $named',
      ),
      null => throw FormatException('no outcome for $proposed'),
    };
  }
}

/// How a program, its input and its output travel in an
/// [ActionProposedByAgentLoop] and its result, by is_effects's codecs. A
/// decoder throws a [FormatException] naming the field, as a dotted path
/// from [field].
final class _Wire<I, O> {
  const _Wire(
    this.program, {
    required this.inputToJson,
    required this.inputFromJson,
    required this.outputToJson,
    required this.outputFromJson,
  });

  /// The keys that name the program in a proposal.
  final Map<String, Object?> program;
  final Object? Function(I input) inputToJson;
  final I Function(Object? json, String field) inputFromJson;
  final Object? Function(O output) outputToJson;
  final O Function(Object? json, String field) outputFromJson;
}

Object? _webFetchToJson(WebFetch fetch) => {
  'origin': encodeOrigin(fetch.origin),
  'path': encodeWebPath(fetch.path),
  'signIn': switch (fetch.signIn) {
    final signIn? => encodeSignIn(signIn),
    null => null,
  },
  'keep': encodeBodyToKeep(fetch.keep),
};

/// [json] as a fetch, exactly its four keys, so a body or headers slipped
/// into one is refused rather than dropped.
WebFetch _webFetchFromJson(Object? input, [String field = 'fetch']) {
  final json = _object(field, input);
  return _at(field, () {
    _exactly(field, json, const {'origin', 'path', 'signIn', 'keep'});
    return WebFetch(
      decodeOrigin(json.raw('origin'), '$field.origin'),
      path: decodeWebPath(json.raw('path'), '$field.path'),
      signIn: switch (json.raw('signIn')) {
        null => null,
        final name => decodeSignIn(name, '$field.signIn'),
      },
      keep: decodeBodyToKeep(json.raw('keep'), '$field.keep'),
    );
  });
}

/// What an [ActionProposedByAgentLoop.kind] logbook entry came to, once
/// read: an [ActionProposedByAgentLoop] to consider, or [Rejected].
sealed class Received {}

/// An action an agent loop proposes, not yet decided: its program and
/// input, read from a [kind] entry and checked.
///
/// It names no trajectory: the airlock takes the path from the chain the
/// entry is on, whose entries the logbook service takes only from that
/// path's loop user. So a loop cannot claim another path, since there is no
/// claim to make.
///
/// What leaves the loop is a proposal; the airlock decides it, and only a
/// driver carries an action out.
final class ActionProposedByAgentLoop implements Received {
  ActionProposedByAgentLoop._(this.place, this._work);

  /// The entry's kind in the logbook.
  static const kind = 'action-proposed-by-agent-loop';

  /// [body], a [kind] logbook entry's body, read as a proposal, or
  /// [Rejected] with why it is not one; never a throw, so the loop that
  /// wrote it is answered. Every part is checked here, as its type's own
  /// `parse` checks it, since a loop is not to be trusted to have gone
  /// through it.
  static Received read(String body) {
    final JsonObject json;
    try {
      json = JsonObject.decode(body);
    } on FormatException {
      return const Rejected('not a proposal');
    }
    final program = json.raw('program');
    if (program is! String) return const Rejected('not a proposal');
    final p = _programNamed(program, json.raw('executable'));
    if (p == null) return Rejected('not a program: $program');
    final place = PlaceInTrajectory.parse(json.raw('place'));
    if (place == null) return const Rejected('not a place');
    try {
      return ActionProposedByAgentLoop._(place, p._work(json.raw('input')));
    } on FormatException catch (e) {
      return Rejected(e.message);
    }
  }

  /// Where in its trajectory the loop proposed it.
  final PlaceInTrajectory place;

  /// The program this proposes, as a type: a reader tells a model call from
  /// a web request by it, as `program: AskTheModel()` in a pattern.
  Program<Object?, Object?> get program => _work.program;

  /// What this proposes to do, which its input says in full: for a
  /// [MakesWebRequests], the exact requests the decision will hold.
  Reach get reach => _work.reach;

  final _Work<Object?, Object?> _work;
}

/// A program with its input, decoded together so the input is the
/// program's own type.
final class _Work<I, O> {
  const _Work(this.program, this.input);

  final Program<I, O> program;
  final I input;

  /// What [input] would do to the world.
  Reach get reach => program._reach(input);

  Future<void> on<P>(
    Trajectory<Object?, P> trajectory,
    P place,
    EntryId proposed,
  ) => trajectory._consider(program, input, place, proposed: proposed);
}

/// The program [name] names, with [executable] the program's name when it
/// is `start`.
Program<Object?, Object?>? _programNamed(String name, Object? executable) =>
    switch ((name, executable)) {
      ('read', null) => Program.read,
      ('read-bytes', null) => Program.readBytes,
      ('write', null) => Program.write,
      ('make-web-requests', null) => Program.makeWebRequests,
      ('fetch', null) => Program.fetch,
      ('model', null) => Program.askTheModel,
      ('start', final String program) => Executable.parse(program),
      _ => null,
    };

/// An [ActionProposedByAgentLoop.kind] logbook entry that is not a
/// proposal, because [why]. The airlock service keeps
/// [proposalRejectedToJson] naming it, so the loop that wrote it is
/// answered and no other path is stalled.
final class Rejected implements Received {
  const Rejected(this.why);

  final String why;
}

/// The kind of the logbook entry that keeps the outcome of an action a loop
/// proposed: what it ran to, or why it was refused. Only the airlock writes
/// it. Its body is [outcomeOfProposedActionToJson].
///
/// The one copy of what the action returned: a read's text, a program's
/// output, a site's answer, a model's reply. The airlock writes it on the
/// decision's chain, never the path's, which only the loop user writes.
/// loop_launcher hands it to the loop whose path's chain holds the proposal,
/// and the loop reads the result with the program it proposed.
const outcomeOfProposedActionKind = 'outcome-of-proposed-action';

/// The body of an [outcomeOfProposedActionKind] logbook entry answering
/// the [ActionProposedByAgentLoop] logbook entry [proposed]: [resultAsJson],
/// as is_effects's `encodeOutcome` writes it with that program's codec.
/// [proposed] is the id the logbook gave that entry, the hash of the whole
/// entry as the logbook keeps it, never a hash of its body.
Object? outcomeOfProposedActionToJson(EntryId proposed, Object? resultAsJson) =>
    {'proposed': proposed.hex, 'result': resultAsJson};

/// The body answering [proposed], a logbook entry that was [Rejected]
/// because [why]: refused, with no action decided.
Object? proposalRejectedToJson(EntryId proposed, String why) =>
    outcomeOfProposedActionToJson(
      proposed,
      encodeOutcome<Never>(Refused(why), (_) => null),
    );

/// [body] read back as an [outcomeOfProposedActionKind] logbook entry's
/// body: the proposal it answers and its result, which only the program
/// that was proposed can read further. Null when [body] is not exactly one,
/// as when the airlock kept the result of an action no loop proposed.
({EntryId proposed, Object? result})? readOutcomeOfProposedAction(String body) {
  final JsonObject json;
  try {
    json = JsonObject.decode(body);
  } on FormatException {
    return null;
  }
  if (json.keys.length != 2 || !json.has('result')) return null;
  return switch (json.raw('proposed')) {
    final String hex => switch (EntryId.parse(hex)) {
      final proposed? => (proposed: proposed, result: json.raw('result')),
      null => null,
    },
    _ => null,
  };
}
