part of 'action.dart';

// An agent loop writes an [ActionProposedByAgentLoop] logbook entry on its
// trajectory's chain, which the logbook service takes only from that path's
// loop user. The airlock reads it, decides, and keeps its decision and then
// an [outcomeOfProposedActionKind] logbook entry naming the proposal, with
// what the action came to. loop_launcher hands that entry to the path's
// loop. The airlock has no door of its own.

/// Where in its trajectory a loop proposed an action. A trajectory is a run
/// of steps, each one model call and what it caused; a place names the
/// [step], counted across the whole trajectory, and within it either the
/// model call, an action of one of the intents the model's reply holds, or
/// an action of the reply the loop makes from the model's final text. A
/// turn, a user's message through to its final reply, may take several
/// steps; a place never counts turns. Each is fixed by what the logbook
/// already holds, never by the order things ran in, so a loop that restarts
/// proposes the same actions at the same places, and a place the logbook
/// already answers is one it need not propose again.
///
/// Written `[step, "model-call"]`, `[step, intent, action]` or
/// `[step, "reply", action]`, in that order within a step.
sealed class PlaceInTrajectory implements Comparable<PlaceInTrajectory> {
  const PlaceInTrajectory._(this.step);

  /// [json], as [toJson] writes it, read back; null when it is not one.
  static PlaceInTrajectory? parse(Object? json) => switch (json) {
    [final int step, ProposedForTheModelCall._wire] when step >= 0 =>
      ProposedForTheModelCall._(step),
    [final int step, final int intent, final int action]
        when step >= 0 && intent >= 0 && action >= 0 =>
      ProposedForAnIntent._(step, intent, action),
    [final int step, ProposedForTheReply._wire, final int action]
        when step >= 0 && action >= 0 =>
      ProposedForTheReply._(step, action),
    _ => null,
  };

  /// Counted from 0.
  final int step;

  Object? toJson();

  /// Where this sits within its step: model call, intents, reply.
  (int, int, int) get _withinStep;

  @override
  int compareTo(PlaceInTrajectory other) {
    final (a1, a2, a3) = _withinStep;
    final (b1, b2, b3) = other._withinStep;
    for (final c in [
      step.compareTo(other.step),
      a1.compareTo(b1),
      a2.compareTo(b2),
      a3.compareTo(b3),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  }
}

/// The place of [step]'s model call, which no intent draws: one action, the
/// first of the step.
final class ProposedForTheModelCall extends PlaceInTrajectory {
  const ProposedForTheModelCall._(super.step) : super._();

  /// Counted from 0.
  factory ProposedForTheModelCall.at(int step) => step >= 0
      ? ProposedForTheModelCall._(step)
      : throw ArgumentError('a step is counted from 0: $step');

  static const _wire = 'model-call';

  @override
  Object? toJson() => [step, _wire];

  @override
  (int, int, int) get _withinStep => (0, 0, 0);

  @override
  bool operator ==(Object other) =>
      other is ProposedForTheModelCall && other.step == step;

  @override
  int get hashCode => Object.hash(step, _wire);

  @override
  String toString() => '$step.$_wire';
}

/// The place of [action] of [step]'s reply, which the loop makes from the
/// model's final text and no intent draws, such as running the program that
/// builds the message and then sending what it built; the last of the step.
final class ProposedForTheReply extends PlaceInTrajectory {
  const ProposedForTheReply._(super.step, this.action) : super._();

  /// Both counted from 0.
  factory ProposedForTheReply.at(int step, int action) =>
      step >= 0 && action >= 0
      ? ProposedForTheReply._(step, action)
      : throw ArgumentError('a place is counted from 0: $step, $action');

  static const _wire = 'reply';

  final int action;

  @override
  Object? toJson() => [step, _wire, action];

  @override
  (int, int, int) get _withinStep => (2, 0, action);

  @override
  bool operator ==(Object other) =>
      other is ProposedForTheReply &&
      other.step == step &&
      other.action == action;

  @override
  int get hashCode => Object.hash(step, _wire, action);

  @override
  String toString() => '$step.$_wire.$action';
}

/// The place of [action] of [intent] in [step]: the intent is a tool call
/// the model's reply holds, by its place in that reply, and the action is
/// one the tool's propose expressions propose, in the order they propose
/// them.
final class ProposedForAnIntent extends PlaceInTrajectory {
  const ProposedForAnIntent._(super.step, this.intent, this.action) : super._();

  /// All three counted from 0.
  factory ProposedForAnIntent.at(int step, int intent, int action) =>
      step >= 0 && intent >= 0 && action >= 0
      ? ProposedForAnIntent._(step, intent, action)
      : throw ArgumentError(
          'a place is counted from 0: $step, $intent, $action',
        );

  final int intent;
  final int action;

  @override
  Object? toJson() => [step, intent, action];

  @override
  (int, int, int) get _withinStep => (1, intent, action);

  @override
  bool operator ==(Object other) =>
      other is ProposedForAnIntent &&
      other.step == step &&
      other.intent == intent &&
      other.action == action;

  @override
  int get hashCode => Object.hash(step, intent, action);

  @override
  String toString() => '$step.$intent.$action';
}

/// How a program, its input and its output travel in an
/// [ActionProposedByAgentLoop] and its result, by each action vocabulary's codecs. A
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

  /// [f] given the program and its input, each with its own type: how the
  /// airlock carries out what was proposed without a cast.
  T open<T>(T Function<I, O>(Program<I, O> program, I input) f) =>
      _work.open(f);

  final _Work<Object?, Object?> _work;
}

/// A program with its input, decoded together so the input is the
/// program's own type.
final class _Work<I, O> {
  const _Work(this.program, this.input);

  final Program<I, O> program;
  final I input;

  /// What [input] would do to the world.
  Reach get reach => program.reachOf(input);

  T open<T>(T Function<I2, O2>(Program<I2, O2> program, I2 input) f) =>
      f<I, O>(program, input);
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
      ('reply-to-own-conversation', null) => Program.replyToOwnConversation,
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
/// as is_outcome_vocabulary's `encodeOutcome` writes it with that program's codec.
/// [proposed] is the id the logbook gave that entry, the hash of the whole
/// entry as the logbook keeps it, never a hash of its body.
Object? outcomeOfProposedActionToJson(EntryId proposed, Object? resultAsJson) =>
    {'proposed': proposed.hex, 'result': resultAsJson};

/// The body answering [proposed], a logbook entry that was [Rejected]
/// because [why]: refused, with no action decided.
Object? proposalRejectedToJson(EntryId proposed, String why) =>
    outcomeOfProposedActionToJson(
      proposed,
      encodeOutcome<Never>(NothingRan(why), (_) => null),
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

Object? _postedMessagesToJson(List<PostedMessage> posted) => [
  for (final message in posted) encodePostedMessage(message),
];

List<PostedMessage> _postedMessagesFromJson(Object? json, String field) =>
    switch (json) {
      final List<Object?> list => [
        for (final (i, message) in list.indexed)
          decodePostedMessage(message, '$field[$i]'),
      ],
      _ => throw FormatException('$field: not a list'),
    };
