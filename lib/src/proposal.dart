part of 'action.dart';

// An agent loop writes an [ActionProposedByAgentLoop] logbook entry on its
// trajectory's chain, which the logbook service takes only from that path's
// loop user. The airlock reads it, decides, and keeps its decision and then
// a [resultOfActionOrWhyRefusedKind] logbook entry naming the proposal, with
// what the action came to. loop_launcher hands that entry to the path's
// loop. The airlock has no door of its own.

/// Records an [ActionProposedByAgentLoop], as JSON, and brings back what the
/// airlock recorded it came to, as JSON: the transport, which this package
/// does not have.
///
/// For an agent loop: write an [ActionProposedByAgentLoop.kind] logbook
/// entry on the loop's trajectory's chain, wait for the
/// [resultOfActionOrWhyRefusedKind] entry that names it, and give back the
/// `result` [readResultOfActionOrWhyRefused] reads from it.
abstract interface class ProposesActionsThroughTheRecord {
  Future<Object?> propose(Object? proposal);
}

/// A crux in the agent loop: proposes each action's program and input through
/// the record, and keeps the continuation.
final class _ThroughRecord extends Crux {
  const _ThroughRecord(this._link, {required this._place});

  final ProposesActionsThroughTheRecord _link;
  final Object? _place;

  /// The outcome the airlock recorded. An answer that is not one throws a
  /// [FormatException], ending the call: whether the action reached the world
  /// is then not known here, and the airlock's record says.
  @override
  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input) async =>
      decodeOutcome(
        await _link.propose({
          'place': _place,
          ...program._wire.program,
          'input': program._wire.inputToJson(input),
        }),
        program._wire.outputFromJson,
      );
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
  'renderer': request.renderer.value,
  'entries': [for (final entry in request.entries) entry.hex],
};

/// [json] as a web request, each part checked as its type's `parse` checks
/// it. Throws a [FormatException] naming the part, as is_effects's decoders
/// do.
WebRequest _webRequestFromJson(Object? json, [String field = 'request']) {
  if (json is! Map<String, Object?>) {
    throw FormatException('$field: not an object');
  }
  return WebRequest(
    decodeOrigin(json['origin'], '$field.origin'),
    method: decodeMethod(json['method'], '$field.method'),
    path: decodeWebPath(json['path'], '$field.path'),
    signIn: switch (json['signIn']) {
      null => null,
      final name => decodeSignIn(name, '$field.signIn'),
    },
    headers: decodeHeaders(json['headers'], '$field.headers'),
    renderer:
        switch (json['renderer']) {
          final String name => RendererName.parse(name),
          _ => null,
        } ??
        (throw FormatException('$field.renderer: not a renderer name')),
    entries: switch (json['entries']) {
      final List<Object?> ids => [
        for (final id in ids)
          (id is String ? EntryId.parse(id) : null) ??
              (throw FormatException('$field.entries: not an entry id: $id')),
      ],
      _ => throw FormatException('$field.entries: not a list'),
    },
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

  /// [json] read as a proposal, or [Rejected] with why it is not one. Every
  /// part is checked here, as its type's own `parse` checks it, since a loop
  /// is not to be trusted to have gone through it.
  static Received read(Object? json) {
    if (json case {'program': final String program}) {
      final p = _programNamed(program, json['executable']);
      if (p == null) return Rejected('not a program: $program');
      try {
        return ActionProposedByAgentLoop._(
          json['place'],
          p._work(json['input']),
        );
      } on FormatException catch (e) {
        return Rejected(e.message);
      }
    }
    return const Rejected('not a proposal');
  }

  /// The place in a turn, as the loop wrote it; the airlock service reads
  /// it as its trajectory's `P`.
  final Object? place;

  final _Work<Object?, Object?> _work;
}

/// A program with its input, decoded together so the input is the
/// program's own type.
final class _Work<I, O> {
  const _Work(this.program, this.input);

  final Program<I, O> program;
  final I input;

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

/// The kind of the logbook entry that keeps what an action a loop proposed
/// came to: what it ran to, or why it was refused. Its body is
/// [resultOfActionOrWhyRefusedToJson].
///
/// The one copy of what the action returned: a read's text, a program's
/// output, a site's answer, a model's reply. The airlock writes it on the
/// decision's chain, never the path's, which only the loop user writes.
/// loop_launcher hands it to the loop whose path's chain holds the proposal,
/// and the loop reads the result with the program it proposed.
const resultOfActionOrWhyRefusedKind = 'result-of-action-or-why-refused';

/// The body of a [resultOfActionOrWhyRefusedKind] logbook entry answering
/// the [ActionProposedByAgentLoop] logbook entry [proposed]: [resultAsJson],
/// as is_effects's `encodeOutcome` writes it with that program's codec.
Object? resultOfActionOrWhyRefusedToJson(
  EntryId proposed,
  Object? resultAsJson,
) => {'proposed': proposed.hex, 'result': resultAsJson};

/// The body answering [proposed], a logbook entry that was [Rejected]
/// because [why]: refused, with no action decided.
Object? proposalRejectedToJson(EntryId proposed, String why) =>
    resultOfActionOrWhyRefusedToJson(
      proposed,
      encodeOutcome<Never>(Refused(why), (_) => null),
    );

/// [json] read back as a [resultOfActionOrWhyRefusedKind] body: the
/// proposal it answers and its result, which only the program that was
/// proposed can read further. Null when [json] is not exactly one, as
/// when the airlock kept the result of an action no loop proposed.
({EntryId proposed, Object? result})? readResultOfActionOrWhyRefused(
  Object? json,
) => switch (json) {
  {'proposed': final String hex, 'result': final result}
      when json.length == 2 =>
    switch (EntryId.parse(hex)) {
      final proposed? => (proposed: proposed, result: result),
      null => null,
    },
  _ => null,
};
