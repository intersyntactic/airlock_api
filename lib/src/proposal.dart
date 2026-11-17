part of 'action.dart';

// A proposal is an entry in the record (Nick, 16 Nov, 20:15): an agent loop
// writes a `proposed` entry on its journey path's chain, which the journal
// takes only from that path's loop user; the airlock reads it, decides,
// records, and writes a `returned` entry naming it, with what came back
// (20:45: "what an action returns is in the record, once"). loop_launcher
// hands that entry to the path's loop. The airlock has no door of its own.

/// Records a [Proposal], as JSON, and brings back the outcome the airlock
/// recorded for it, as JSON: the transport, which this package does not
/// have.
///
/// For an agent loop: write a [Proposal.kind] entry on the loop's journey
/// path's chain, wait for the [ReturnedProposal] that names it, and give
/// back its [ReturnedProposal.outcome].
abstract interface class RecordLink {
  Future<Object?> propose(Object? proposal);
}

/// An apex in the agent loop: proposes each action's program and input through
/// the record, and keeps the continuation.
final class _ThroughRecord extends Apex {
  const _ThroughRecord(this._link, {required this._place});

  final RecordLink _link;
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

/// How a program, its input and its output travel in a [Proposal] and its
/// [ReturnedProposal], by is_effects's codecs. A decoder throws a
/// [FormatException] naming the field, as a dotted path from [field].
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

/// What a `proposed` entry came to, once read: a [Proposal] to consider, or
/// [Rejected].
sealed class Received {}

/// An action an agent loop proposes, not yet decided: its program and
/// input, read from a [kind] entry and checked.
///
/// It names no journey path: the airlock takes the path from the chain the
/// entry is on, whose entries the journal takes only from that path's loop
/// user. So a loop cannot claim another path, since there is no claim to
/// make.
///
/// What leaves the loop is a proposal; the airlock decides it, and only a
/// driver carries an action out.
final class Proposal implements Received {
  Proposal._(this.place, this._work);

  /// The entry's kind in the journal.
  static const kind = 'proposed';

  /// [json] read as a proposal, or [Rejected] with why it is not one. Every
  /// part is checked here, as its type's own `parse` checks it, since a loop
  /// is not to be trusted to have gone through it.
  static Received read(Object? json) {
    if (json case {'program': final String program}) {
      final p = _programNamed(program, json['executable']);
      if (p == null) return Rejected('not a program: $program');
      try {
        return Proposal._(json['place'], p._work(json['input']));
      } on FormatException catch (e) {
        return Rejected(e.message);
      }
    }
    return const Rejected('not a proposal');
  }

  /// The place in a turn, as the loop wrote it; the airlock service reads
  /// it as its journey path's `P`.
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
    JourneyPath<Object?, P> journeyPath,
    P place,
    EntryId proposed,
  ) => journeyPath._consider(program, input, place, proposed: proposed);
}

/// The program [name] names, with [executable] the program's name when it
/// is `start`.
Program<Object?, Object?>? _programNamed(String name, Object? executable) =>
    switch ((name, executable)) {
      ('read', null) => Program.read,
      ('write', null) => Program.write,
      ('web', null) => Program.web,
      ('start', final String program) => Executable.parse(program),
      _ => null,
    };

/// A `proposed` entry that is not a proposal, because [why]. The airlock
/// service records [ReturnedProposal.refused] naming it, so the loop that
/// wrote it is answered and no other path is stalled.
final class Rejected implements Received {
  const Rejected(this.why);

  final String why;
}

/// A proposal's [Returned] entry as the journal holds it: what came back
/// from the action the `proposed` entry [proposed] asked for, as that program's
/// codec writes it, or the refusal.
///
/// The one copy of what an action returned (Nick, 16 Nov, 20:45): a read's
/// text, a program's output, a site's answer. The airlock writes it on its
/// own chain, never the path's, which only the loop user writes.
/// loop_launcher hands it to the loop whose path's chain holds [proposed],
/// and the loop reads [outcome] with the program it proposed.
final class ReturnedProposal {
  const ReturnedProposal._(this.proposed, this.outcome);

  /// The entry's kind in the journal.
  static const kind = 'returned';

  /// [returned] as the journal holds it; null when no proposal asked for
  /// its action.
  static ReturnedProposal? of<P>(Returned<P> returned) =>
      switch (returned.proposed) {
        final proposed? => ReturnedProposal._(proposed, returned._outcomeJson),
        null => null,
      };

  /// The answer to [proposed], a `proposed` entry that was [Rejected]
  /// because [why]: refused, with no action decided.
  factory ReturnedProposal.refused(EntryId proposed, String why) =>
      ReturnedProposal._(
        proposed,
        encodeOutcome<Never>(Refused(why), (_) => null),
      );

  /// [json] read back. Throws a [FormatException] naming the part. Reads
  /// [outcome] no further, since only the program that was proposed knows
  /// its output's type.
  static ReturnedProposal fromJson(Object? json, [String field = 'returned']) {
    final map = _object(field, json);
    return ReturnedProposal._(
      EntryId.parse(_string('$field.proposed', map['proposed'])) ??
          (throw FormatException('$field.proposed: not an entry id')),
      map['outcome'],
    );
  }

  /// The `proposed` entry this answers.
  final EntryId proposed;

  /// What came back, as is_effects's `encodeOutcome` writes it with the
  /// proposed program's output codec.
  final Object? outcome;

  Object? toJson() => {'proposed': proposed.hex, 'outcome': outcome};
}
