part of 'action.dart';

// An agent loop writes an [ActionProposedByAgentLoop] logbook entry on its
// trajectory's chain, which the logbook service takes only from that path's
// loop user. The airlock reads it, decides, and keeps its decision and then
// an [outcomeOfProposedActionKind] logbook entry naming the proposal, with
// what the action came to. loop_launcher hands that entry to the path's
// loop. The airlock has no door of its own.

/// Writes an [ActionProposedByAgentLoop] logbook entry and waits for what the
/// airlock recorded it came to: the transport, which this package does not
/// have. This package joins the two, so a loop never works out an id.
abstract interface class ProposesActionsThroughTheRecord {
  /// Writes [body] as an [ActionProposedByAgentLoop.kind] logbook entry on
  /// the loop's trajectory's chain, and gives the id the logbook gave it:
  /// the hash of the whole recorded entry, which covers the entry before it
  /// on the chain. Never a hash of [body] alone.
  Future<EntryId> writeProposal(String body);

  /// The body of the [outcomeOfProposedActionKind] logbook entry that names
  /// [proposed], once the airlock has kept it.
  Future<String> outcomeNaming(EntryId proposed);
}

/// Where in its trajectory a loop proposed an action: the [turn], one model
/// call and what it caused, and the [step] within it. The model call is
/// step 0 and a tool call's actions follow it, so a loop that restarts
/// proposes the same steps at the same places, and a place the record
/// already answers is one it need not propose again.
final class PlaceInTrajectory implements Comparable<PlaceInTrajectory> {
  const PlaceInTrajectory._(this.turn, this.step);

  /// The place [step] of [turn]; both are counted from 0.
  factory PlaceInTrajectory.at(int turn, int step) => turn >= 0 && step >= 0
      ? PlaceInTrajectory._(turn, step)
      : throw ArgumentError('a place is counted from 0: $turn, $step');

  /// [json], as [toJson] writes it, read back; null when it is not one.
  static PlaceInTrajectory? parse(Object? json) => switch (json) {
    [final int turn, final int step] when turn >= 0 && step >= 0 =>
      PlaceInTrajectory._(turn, step),
    _ => null,
  };

  final int turn;
  final int step;

  Object? toJson() => [turn, step];

  /// By [turn], then by [step]: a trajectory's places in the order they
  /// were proposed.
  @override
  int compareTo(PlaceInTrajectory other) => turn != other.turn
      ? turn.compareTo(other.turn)
      : step.compareTo(other.step);

  @override
  bool operator ==(Object other) =>
      other is PlaceInTrajectory && other.turn == turn && other.step == step;

  @override
  int get hashCode => Object.hash(turn, step);

  @override
  String toString() => '$turn.$step';
}

/// A crux in the agent loop for one turn: proposes each action's program and
/// input through the record at the turn's next step, and keeps the
/// continuation.
final class _ThroughRecord extends Crux {
  _ThroughRecord(this._link, {required this._turn});

  final ProposesActionsThroughTheRecord _link;
  final int _turn;
  int _nextStep = 0;

  /// The outcome the airlock recorded. An answer that is not one, or that
  /// names another proposal, throws a [FormatException], ending the call:
  /// whether the action reached the world is then not known here, and the
  /// airlock's record says.
  @override
  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input) async {
    final place = PlaceInTrajectory.at(_turn, _nextStep++);
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

/// [request] as a proposal holds it.
Object? _webRequestToJson(WebRequest request) => {
  'origin': encodeOrigin(request.origin),
  'method': encodeMethod(request.method),
  'path': encodeWebPath(request.path),
  'signIn': switch (request.signIn) {
    final signIn? => encodeSignIn(signIn),
    null => null,
  },
  'headers': encodeHeaders(request.headers),
  'body': request.body,
  'projection': request.projection.wire,
  'drawnFrom': request.drawnFrom.hex,
};

/// [json] as a web request, each part checked as its type's `parse` checks
/// it. Throws a [FormatException] naming the part, as is_effects's decoders
/// do.
WebRequest _webRequestFromJson(Object? input, [String field = 'request']) {
  final json = _object(field, input);
  return _at(
    field,
    () => WebRequest(
      decodeOrigin(json.raw('origin'), '$field.origin'),
      method: decodeMethod(json.raw('method'), '$field.method'),
      path: decodeWebPath(json.raw('path'), '$field.path'),
      signIn: switch (json.raw('signIn')) {
        null => null,
        final name => decodeSignIn(name, '$field.signIn'),
      },
      headers: decodeHeaders(json.raw('headers'), '$field.headers'),
      body: json.string('body'),
      projection:
          Projection.parse(json.string('projection')) ??
          (throw FormatException('$field.projection: not a projection')),
      drawnFrom:
          EntryId.parse(json.string('drawnFrom')) ??
          (throw FormatException('$field.drawnFrom: not an entry id')),
    ),
  );
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
      ('write', null) => Program.write,
      ('web', null) => Program.web,
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
/// recorded entry, never a hash of its body.
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
