part of 'run.dart';

/// The secret that shows a [Proposal] came from the agent loop of the
/// journey path it names.
///
/// The airlock service mints one when it sets up its side of a journey path
/// ([JourneyPath.token]) and hands it to loop_launcher, which gives it to
/// the loop it launches for that path, and to nothing else.
///
/// A check beside the main one, not instead of it. Each path's loop runs as
/// a loop user of its own, so [JourneyPath.consider] first takes a proposal
/// only from that user, as the kernel reports the socket's peer, which the
/// sender cannot choose (Nick, 16 Nov). The token is kept as well, for now.
///
/// Never recorded: no [Reach] holds it, and [toString] does not show it.
/// Never compared with `==`, which would stop at the first byte that differs
/// and so tell a guesser how many it had right; [JourneyPath] compares it in
/// constant time.
final class PathToken {
  PathToken._(this._bytes);

  /// A new token, from the system's secure random source.
  factory PathToken._mint() {
    final random = Random.secure();
    return PathToken._(
      Uint8List.fromList([
        for (var i = 0; i < _length; i++) random.nextInt(256),
      ]),
    );
  }

  /// [s] as a token, read back from the text [hex] gave; null unless it is
  /// 32 bytes in lower-case hex.
  static PathToken? parse(String s) {
    if (!_tokenHex.hasMatch(s)) return null;
    return PathToken._(
      Uint8List.fromList([
        for (var i = 0; i < s.length; i += 2)
          int.parse(s.substring(i, i + 2), radix: 16),
      ]),
    );
  }

  static const _length = 32;

  final Uint8List _bytes;

  /// The token as text, to hand to the loop and to put in a [Proposal]: the
  /// one way to read it, so every place it is written down can be found.
  String get hex =>
      [for (final b in _bytes) b.toRadixString(16).padLeft(2, '0')].join();

  /// Whether [other] is this token, taking as long whichever byte differs.
  bool _matches(PathToken other) {
    var differ = 0;
    for (var i = 0; i < _length; i++) {
      differ |= _bytes[i] ^ other._bytes[i];
    }
    return differ == 0;
  }

  @override
  String toString() => 'PathToken(hidden)';
}

final _tokenHex = RegExp(r'^[0-9a-f]{64}$');

/// Takes a [Proposal], as JSON, from an agent loop to the airlock service,
/// and brings back its answer, as JSON: the transport, which this package
/// does not have. A socket, say, whose peer's OS user the service checks as
/// well.
abstract interface class AirlockLink {
  Future<Object?> propose(Object? proposal);
}

/// An apex in the agent loop: proposes each run's program and input to the
/// airlock, and keeps the continuation.
final class _ThroughLink extends Apex {
  const _ThroughLink(
    this._link, {
    required this._journeyPath,
    required this._token,
    required this._place,
  });

  final AirlockLink _link;
  final JourneyPathId _journeyPath;
  final PathToken _token;
  final Object? _place;

  /// The outcome the airlock answered. An answer that is not one throws a
  /// [FormatException], ending the call: whether the run reached the world
  /// is then not known here, and the airlock's record says.
  @override
  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input) async =>
      decodeOutcome(
        await _link.propose({
          'journeyPath': _journeyPath.hex,
          'token': _token.hex,
          'place': _place,
          ...program._wire.program,
          'input': program._wire.inputToJson(input),
        }),
        program._wire.outputFromJson,
      );
}

/// How a program, its input and its output travel in a [Proposal] and its
/// answer, by is_effects's codecs. A decoder throws a [FormatException]
/// naming the field, as a dotted path from [field].
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

/// [send] as a proposal holds it.
Object? _sendToJson(Send send) => {
  'origin': encodeOrigin(send.origin),
  'method': encodeMethod(send.method),
  'path': encodeWebPath(send.path),
  'signIn': switch (send.signIn) {
    final signIn? => encodeSignIn(signIn),
    null => null,
  },
  'headers': encodeHeaders(send.headers),
  'renderer': send.renderer.value,
  'entries': [for (final entry in send.entries) entry.hex],
};

/// [json] as a send, each part checked as its type's `parse` checks it.
/// Throws a [FormatException] naming the part, as is_effects's decoders do.
Send _sendFromJson(Object? json, [String field = 'send']) {
  if (json is! Map<String, Object?>) {
    throw FormatException('$field: not an object');
  }
  return Send(
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

/// What a request from an agent loop came to, once read: a [Proposal] to
/// consider, or [Rejected].
sealed class Received {}

/// An effect an agent loop proposes, not yet decided: a run's program and
/// input, read from JSON and checked, but not yet shown to be from that
/// journey path's loop, which [JourneyPath.consider] checks by [token].
///
/// What leaves the loop is a proposal; the airlock decides it, and only a
/// driver carries an effect out. So a send goes proposed, decided,
/// rendered, returned; the record holds the last three, and a proposal that
/// is [Rejected] is in no journey path's record.
final class Proposal implements Received {
  Proposal._(this.journeyPath, this.token, this.place, this._work);

  /// [json] read as a proposal, or [Rejected] with why it is not one. Every
  /// part is checked here, as its type's own `parse` checks it, since the
  /// socket is not to be trusted to have gone through it.
  static Received read(Object? json) {
    if (json case {
      'journeyPath': final String path,
      'token': final String token,
      'program': final String program,
    }) {
      final journeyPath = JourneyPathId.parse(path);
      if (journeyPath == null) return Rejected('not a journey path: $path');
      final t = PathToken.parse(token);
      if (t == null) return const Rejected('not a token');
      final p = _programNamed(program, json['executable']);
      if (p == null) return Rejected('not a program: $program');
      try {
        return Proposal._(
          journeyPath,
          t,
          json['place'],
          p._work(json['input']),
        );
      } on FormatException catch (e) {
        return Rejected(e.message);
      }
    }
    return const Rejected('not a proposal');
  }

  /// The journey path it claims to be of.
  final JourneyPathId journeyPath;

  /// What shows it is from that path's loop. Compared in constant time, and
  /// never recorded.
  final PathToken token;

  /// The place in a turn, as the loop wrote it; the service reads it as its
  /// journey path's `P`.
  final Object? place;

  final _Work<Object?, Object?> _work;
}

/// A program with its input, decoded together so the input is the
/// program's own type.
final class _Work<I, O> {
  const _Work(this.program, this.input);

  final Program<I, O> program;
  final I input;

  Future<Object?> on<P>(JourneyPath<Object?, P> journeyPath, P place) async =>
      encodeOutcome(
        await journeyPath._consider(program, input, place),
        program._wire.outputToJson,
      );
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

/// What the airlock service answers a [Proposal] with.
sealed class ProposalAnswer {
  /// The answer as JSON, for the link to take back to the loop.
  Object? get json;
}

/// The proposal was decided, and the run it describes ran or was refused;
/// both are in the journey path's record.
final class Considered implements ProposalAnswer {
  const Considered._(this.json);

  @override
  final Object? json;
}

/// The request was not considered, and is in no journey path's record,
/// because [why]: it was not a proposal or a [PathStarted], named no
/// journey path the service holds, or did not show that path's token.
///
/// Recorded by the service in the airlock's own chain, with the journey path
/// it claimed and the OS user of the socket's peer, and never the token: a
/// wrong token is the one attack the token is there to stop, and a refusal
/// with no trace would leave nobody able to see it happened.
final class Rejected
    implements
        Received,
        ProposalAnswer,
        PathStartedReceived,
        PathStartedAnswer {
  const Rejected(this.why);

  final String why;

  /// The sender is told it was refused, with [why], in the form of a
  /// refused outcome, which a loop and loop_launcher both read.
  @override
  Object? get json => encodeOutcome(Refused(why), (Never _) => null);
}
