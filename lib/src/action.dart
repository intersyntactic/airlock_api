import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;

import 'package:checked_json/checked_json.dart';

import 'package:is_content_id/is_content_id.dart' show ObjectId;
import 'package:is_effects/is_effects.dart';
import 'package:is_shapes/is_shapes.dart' show DecidedBy, EntryId, TrajectoryId;

part 'pool_user.dart';
part 'web_request_entries.dart';
part 'proposal.dart';
part 'waiting_to_start.dart';
part 'model_request.dart';

/// What a tool's code returns for a call: an action whose outcome it needs
/// before it can answer, its answer, or that it could not answer. [A] is the
/// type of the answer, the tool's output type.
///
/// A tool holds no driver and touches nothing. Its result is carried through
/// at a [Crux], whose trajectory has each action decided and recorded, and
/// reached by a driver if it is allowed, and gives what became of it to the
/// action's continuation. So a tool can describe nothing an action cannot
/// express.
///
/// Not an [Outcome], which is what happened to one action. An [Action] never
/// reaches the model: [Done]'s value does, written out by the tool's
/// definition, and [Failed]'s reason does, as an error.
sealed class Result<A> {
  const Result();

  /// This result with its answer, once there is one, given to [f].
  ///
  /// Reaches no driver: an action's continuation is extended, so [f] is
  /// applied when a later [Action.next] reaches an answer, and every action
  /// on the way is still decided and recorded. So whoever turns a tool's
  /// answer into what the model is told can do it without carrying out the
  /// actions.
  Result<B> map<B>(B Function(A answer) f);
}

/// Run a program on an input, then continue with what became of it.
///
/// One round trip to the world, which the airlock decides: what a tool asks
/// for to carry out an intent (Nick, 17 Nov: "the airlock sits between
/// intents and action"). A read, a write, `git diff` and a web request to a chat
/// are all actions, each one of four programs on an input, and each has
/// exactly one [Outcome].
///
/// The continuation travels with the action, not in the tool, so one tool
/// can serve concurrent calls without keeping state for any of them. It is
/// private: what it is given comes from [next], after the airlock's decision,
/// never from whoever holds the action.
///
/// Typed only by the answer it leads to, [A]. The program's input and output
/// types stay inside, where [next] uses them, so whoever holds an action
/// never handles either, and a switch over a [Result] covers every action
/// with `case Action()`. Dart's generics are covariant: a caller passing an
/// outcome to the continuation itself would be checked only when it ran.
abstract final class Action<A> extends Result<A> {
  const Action._();

  /// This action proposed at [crux], and the result it leads to.
  ///
  /// The only way an action reaches the world. What it would do, its
  /// [Reach], is worked out first; the trajectory's airlock decides it,
  /// and records the decision, at the crux's place, before any driver is
  /// reached; a driver of the trajectory carries out an allowed action;
  /// the airlock records what became of it before the continuation sees it.
  /// If either record cannot be written, its error ends the call: no driver
  /// is reached without a recorded decision, and no outcome flows on
  /// unrecorded.
  Future<Result<A>> next(Crux crux);

  @override
  Action<B> map<B>(B Function(A answer) f);
}

/// An [Action] of a [Program] taking [I] and giving [O].
///
/// Made only by its program ([Program.run], [Program.runOrRefusal]), so [I]
/// is the program's own input type. Built from a program and an input side
/// by side, inference would widen [I] to fit both, and a [WriteFile] given a
/// `String` would compile.
final class _Action<I, O, A> extends Action<A> {
  const _Action(this._program, this._input, this._then) : super._();

  final Program<I, O> _program;
  final I _input;
  final Result<A> Function(Outcome<O> outcome) _then;

  @override
  Future<Result<A>> next(Crux crux) async =>
      _then(await crux._propose(_program, _input));

  @override
  Action<B> map<B>(B Function(A answer) f) =>
      _Action(_program, _input, (outcome) => _then(outcome).map(f));
}

/// The tool's answer. [value] reaches the model as its definition's
/// `Output` writes it out.
final class Done<A> extends Result<A> {
  const Done(this.value);

  final A value;

  @override
  Done<B> map<B>(B Function(A answer) f) => Done(f(value));
}

/// The tool could not answer, because [why]. A [Result] of every tool, since
/// [Never] is a subtype of every type; the model is told [why] as an error.
final class Failed extends Result<Never> {
  const Failed(this.why);

  final String why;

  /// Itself: there is no answer to give [f].
  @override
  Failed map<B>(B Function(Never answer) f) => this;
}

/// A program an action may run: what it takes, [I], and what it gives
/// back, [O].
///
/// A closed set: [ReadFile], [WriteFile], [Executable], [MakeWebRequest]
/// and [AskTheModel].
/// Programs reach drivers, so they are part of what is trusted, with the
/// drivers and the airlock; a new kind of action is a new driver and program
/// here.
///
/// A model call is one too, [AskTheModel]: the model is outside the
/// station, so the case's words leave the machine with every call
/// (https://github.com/enspyrco/intersyntactic/pull/1168, replacing the
/// ruling that the model is the agent planning and is not decided).
sealed class Program<I, O> {
  const Program();

  static const read = ReadFile();
  static const write = WriteFile();
  static const web = MakeWebRequest();
  static const askTheModel = AskTheModel();

  /// For the model and the record; an [Executable] is compared by it.
  String get name;

  /// The action of running this program on [input], continuing with [then].
  Action<A> run<A>(
    I input, {
    required Result<A> Function(Outcome<O> outcome) then,
  }) => _Action(this, input, then);

  /// An action whose refusal is the tool's failure: [then] is called only
  /// with the output.
  Action<A> runOrRefusal<A>(
    I input, {
    required Result<A> Function(O output) then,
  }) => _Action(
    this,
    input,
    (outcome) => switch (outcome) {
      Ran(:final output) => then(output),
      Refused(:final why) => Failed(why),
    },
  );

  /// What [input] would do to the world.
  Future<Reach> _reach(I input);

  /// How this program, its input and its output travel between the agent
  /// loop and the airlock.
  _Wire<I, O> get _wire;

  /// This program with the input [json] holds. Throws a [FormatException]
  /// when it holds none.
  _Work<I, O> _work(Object? json) =>
      _Work(this, _wire.inputFromJson(json, 'input'));

  /// [input], whose reach is [reach], performed by [trajectory]'s driver
  /// for this program, reporting to [report] while it runs, or null when it
  /// has none.
  Future<Outcome<O>>? _on(
    Trajectory<Object?, Object?> trajectory,
    I input,
    Reach reach,
    Report report,
  );
}

/// Reads the file at a path under the file driver's root.
final class ReadFile extends Program<RelativePath, ReadResult> {
  const ReadFile();

  @override
  String get name => 'read';

  @override
  Future<Reach> _reach(RelativePath path) async => Reads(path);

  @override
  _Wire<RelativePath, ReadResult> get _wire => const _Wire(
    {'program': 'read'},
    inputToJson: encodeRelativePath,
    inputFromJson: decodeRelativePath,
    outputToJson: encodeReadResult,
    outputFromJson: decodeReadResult,
  );

  @override
  Future<Outcome<ReadResult>>? _on(
    Trajectory<Object?, Object?> trajectory,
    RelativePath path,
    Reach reach,
    Report report,
  ) => trajectory._driver<ReadsAndWritesFiles>()?.read(path);
}

/// Writes a file, creating its folder.
final class WriteFile extends Program<FileText, Wrote> {
  const WriteFile();

  @override
  String get name => 'write';

  @override
  Future<Reach> _reach(FileText file) async => Writes(file);

  @override
  _Wire<FileText, Wrote> get _wire => const _Wire(
    {'program': 'write'},
    inputToJson: encodeFileText,
    inputFromJson: decodeFileText,
    outputToJson: encodeWrote,
    outputFromJson: decodeWrote,
  );

  @override
  Future<Outcome<Wrote>>? _on(
    Trajectory<Object?, Object?> trajectory,
    FileText file,
    Reach reach,
    Report report,
  ) => trajectory._driver<ReadsAndWritesFiles>()?.write(file);
}

/// A program started as a process, such as `git`: its input is plain
/// arguments, and it reaches whatever the process can.
final class Executable extends Program<Args, ExecResult> {
  const Executable(this.program);

  /// [raw] as a program, or null when it is not a [ProgramName].
  static Executable? parse(String raw) => switch (ProgramName.parse(raw)) {
    final program? => Executable(program),
    null => null,
  };

  final ProgramName program;

  @override
  String get name => program.value;

  @override
  Future<Reach> _reach(Args args) async => Starts(program, args);

  @override
  _Wire<Args, ExecResult> get _wire => _Wire(
    {'program': 'start', 'executable': program.value},
    inputToJson: encodeArgs,
    inputFromJson: decodeArgs,
    outputToJson: encodeExecResult,
    outputFromJson: decodeExecResult,
  );

  /// By [program], so a rule naming a program matches every action that
  /// runs it.
  @override
  bool operator ==(Object other) =>
      other is Executable && other.program == program;

  @override
  int get hashCode => program.hashCode;

  @override
  Future<Outcome<ExecResult>>? _on(
    Trajectory<Object?, Object?> trajectory,
    Args args,
    Reach reach,
    Report report,
  ) => trajectory._driver<RunsPrograms>()?.runProgram(
    program,
    args,
    report: report,
  );
}

/// The body of [entry], which must belong to [trajectory] and be of [kind],
/// as [DecidesAndRecordsActions.recordedOn] reads it; or [Refused] with why
/// not. The kind is checked, since a loop may write a body of any shape
/// under its own kinds on its own chain.
Future<Outcome<String>> _bodyOf(
  Trajectory<Object?, Object?> trajectory,
  EntryId entry,
  String kind,
) async => switch (await trajectory._airlock.recordedOn(trajectory.id, entry)) {
  Refused(:final why) => Refused(why),
  Ran(output: (kind: final recorded, :final body)) when recorded == kind => Ran(
    body,
  ),
  Ran(output: (kind: final recorded, body: _)) => Refused(
    'entry $entry is a $recorded, not a $kind',
  ),
};

/// The body of [entry], an [outcomeOfProposedActionKind] logbook entry of
/// [trajectory]'s, when the proposal it names asked the model; or [Refused]
/// with why not. Another program's result can read as a model reply, as a
/// read's `{"kind":"text","text":…}` does, so the proposal is read from the
/// trajectory's chain and checked.
Future<Outcome<String>> _modelReplyOutcome(
  Trajectory<Object?, Object?> trajectory,
  EntryId entry,
) async =>
    switch (await _bodyOf(trajectory, entry, outcomeOfProposedActionKind)) {
      Refused(:final why) => Refused(why),
      Ran(output: final recorded) => switch (readOutcomeOfProposedAction(
        recorded,
      )) {
        null => Refused('entry $entry names no proposal'),
        (:final proposed, result: _) => switch (await _bodyOf(
          trajectory,
          proposed,
          ActionProposedByAgentLoop.kind,
        )) {
          Refused(:final why) => Refused(why),
          Ran(output: final proposal) => switch (ActionProposedByAgentLoop.read(
            proposal,
          )) {
            ActionProposedByAgentLoop(program: AskTheModel()) => Ran(recorded),
            ActionProposedByAgentLoop() => Refused(
              'entry $entry answers $proposed, which asked no model',
            ),
            Rejected(:final why) => Refused(
              'entry $entry answers $proposed, which asked no model: $why',
            ),
          },
        },
      },
    };

/// Makes a [WebRequest] to a site, through the sign-in it names, with
/// exactly the body it holds.
///
/// An action, decided like any other: a request a tool makes to a chat, an
/// issue tracker or an API. A call to the model is not one of these: it is
/// [AskTheModel], through the model driver.
///
/// The request carries the exact bytes it sends, so the airlock decides what
/// will be sent, not the code that will produce it, and the decision holds
/// those bytes. They must come from the record: once allowed, the airlock
/// reads the entry the request is drawn from through
/// [DecidesAndRecordsActions.recordedOn], draws the body from it by the
/// request's [Projection], and reaches the web driver only when that is
/// byte-identical to the body. Any other body is refused, so a loop can send
/// only what its projection makes of what is recorded. A model reply is
/// drawn only from the outcome of a proposal to ask the model, read from the
/// trajectory's own chain.
final class MakeWebRequest extends Program<WebRequest, WebResponse> {
  const MakeWebRequest();

  @override
  String get name => 'web';

  @override
  Future<Reach> _reach(WebRequest request) async => MakesWebRequest(request);

  @override
  _Wire<WebRequest, WebResponse> get _wire => const _Wire(
    {'program': 'web'},
    inputToJson: _webRequestToJson,
    inputFromJson: _webRequestFromJson,
    outputToJson: encodeWebResponse,
    outputFromJson: decodeWebResponse,
  );

  @override
  Future<Outcome<WebResponse>>? _on(
    Trajectory<Object?, Object?> trajectory,
    WebRequest request,
    Reach reach,
    Report report,
  ) => switch (trajectory._driver<CarriesOutWebRequests>()) {
    null => null,
    final web => _make(web, trajectory, request),
  };

  static Future<Outcome<WebResponse>> _make(
    CarriesOutWebRequests web,
    Trajectory<Object?, Object?> trajectory,
    WebRequest request,
  ) async => switch (request.projection) {
    Projection.teamsMessageFromModelReply => switch (await _modelReplyOutcome(
      trajectory,
      request.drawnFrom,
    )) {
      Refused(:final why) => Refused(why),
      Ran(output: final recorded)
          when request.projection.drawnFrom(recorded) != request.body =>
        Refused(
          'the body is not ${request.projection.wire} of '
          '${request.drawnFrom}',
        ),
      Ran() => await _send(web, request),
    },
    Projection.trajectoryOpenCard
        when request.drawnFrom.hex != trajectory.id.hex =>
      Refused(
        'a trajectory open card is drawn from its own trajectory, '
        '${trajectory.id.hex}, not ${request.drawnFrom}',
      ),
    Projection.trajectoryOpenCard when request.body != trajectoryOpenCardBody =>
      const Refused('the body is not trajectory-open-card'),
    Projection.trajectoryOpenCard => await _send(web, request),
  };

  static Future<Outcome<WebResponse>> _send(
    CarriesOutWebRequests web,
    WebRequest request,
  ) => web.carryOutWebRequest(
    Request(
      request.origin,
      method: request.method,
      path: request.path,
      signIn: request.signIn,
      headers: request.headers,
      body: request.body,
    ),
  );
}

/// Asks the model, through the model driver, as the [ModelCall]'s sign-in,
/// with the system prompt and request its recorded [ModelRequest] holds.
///
/// The one action the loop proposes for itself rather than drawing from an
/// intent in the model's reply: the loop holds no sign-in and has no
/// network, so this is its only way to reach the model
/// (https://github.com/enspyrco/intersyntactic/pull/1168). The airlock
/// allows it only as a sign-in the trajectory's rules let a model call go
/// out as.
///
/// Once allowed, the airlock reads the [ModelRequest] and each of its
/// pieces from this trajectory's own chain, joins each text, checks it
/// against its sha256, and hands the driver exactly those texts. Any piece
/// missing, on another chain, or not joining to its hash refuses the call
/// before the driver is reached. The reply streams as [ReplyArriving] in
/// [Underway], never recorded; the whole [ModelReply] is the outcome,
/// recorded once.
final class AskTheModel extends Program<ModelCall, ModelReply> {
  const AskTheModel();

  @override
  String get name => 'model';

  @override
  Future<Reach> _reach(ModelCall call) async => CallsTheModel(call);

  @override
  _Wire<ModelCall, ModelReply> get _wire => const _Wire(
    {'program': 'model'},
    inputToJson: _modelCallToJson,
    inputFromJson: _modelCallFromJson,
    outputToJson: encodeModelReply,
    outputFromJson: decodeModelReply,
  );

  @override
  Future<Outcome<ModelReply>>? _on(
    Trajectory<Object?, Object?> trajectory,
    ModelCall call,
    Reach reach,
    Report report,
  ) => switch (trajectory._driver<AsksTheModel>()) {
    null => null,
    final driver => _ask(driver, trajectory, call, report),
  };

  static Future<Outcome<ModelReply>> _ask(
    AsksTheModel driver,
    Trajectory<Object?, Object?> trajectory,
    ModelCall call,
    Report report,
  ) async {
    final ModelRequest request;
    switch (await _bodyOf(trajectory, call.request, ModelRequest.kind)) {
      case Refused(:final why):
        return Refused(why);
      case Ran(output: final text):
        try {
          request = ModelRequest.fromJson(JsonObject.decode(text));
        } on FormatException catch (e) {
          return Refused('not a model request: ${e.message}');
        }
    }
    Future<Outcome<String>> joined(RecordedText recorded) async {
      final texts = <String>[];
      for (final piece in recorded.pieces) {
        switch (await _bodyOf(trajectory, piece, ModelRequestPiece.kind)) {
          case Refused(:final why):
            return Refused(why);
          case Ran(output: final text):
            try {
              texts.add(
                ModelRequestPiece.fromJson(JsonObject.decode(text)).text,
              );
            } on FormatException catch (e) {
              return Refused('not a model request piece: ${e.message}');
            }
        }
      }
      return recorded.join(texts);
    }

    final systemPrompt = await joined(request.systemPrompt);
    final asked = await joined(request.request);
    return switch ((systemPrompt, asked)) {
      (Refused(:final why), _) || (_, Refused(:final why)) => Refused(why),
      (Ran(output: final system), Ran(output: final text)) =>
        await driver.askTheModel(
          call.signIn,
          call.model,
          system,
          text,
          report: report,
        ),
    };
  }
}

/// A model call a loop proposes: as which of the person's model sign-ins,
/// to which model, and the [ModelRequest] entry, recorded on its
/// trajectory's chain before this, that holds exactly what is sent.
final class ModelCall {
  const ModelCall({
    required this.signIn,
    required this.model,
    required this.request,
  });

  final ModelSignInName signIn;
  final ModelName model;

  /// The [ModelRequest] entry.
  final EntryId request;
}

Object? _modelCallToJson(ModelCall call) => {
  'signIn': encodeModelSignInName(call.signIn),
  'model': encodeModelName(call.model),
  'request': call.request.hex,
};

ModelCall _modelCallFromJson(Object? input, String field) {
  final json = _object(field, input);
  return _at(field, () {
    _exactly(field, json, const {'signIn', 'model', 'request'});
    return ModelCall(
      signIn: decodeModelSignInName(json.raw('signIn'), '$field.signIn'),
      model: decodeModelName(json.raw('model'), '$field.model'),
      request:
          EntryId.parse(json.string('request')) ??
          (throw FormatException('$field.request: not an entry id')),
    );
  });
}

/// A web request a tool asks for: where to, as whom, and the exact [body]
/// it sends, with the recorded entry it is drawn from and how.
///
/// [path] and [headers] are checked as is_effects's `Request` checks them:
/// a [WebPath] cannot name another site, and [headers] hold no credential.
final class WebRequest {
  WebRequest(
    this.origin, {
    required this.body,
    required this.projection,
    required this.drawnFrom,
    this.method = Method.post,
    this.path = WebPath.root,
    this.signIn,
    Map<String, String> headers = const {},
  }) : headers = validatedHeaders(headers);

  final Origin origin;
  final Method method;
  final WebPath path;

  /// Who it goes as; null goes under no sign-in.
  final SignIn? signIn;
  final Map<String, String> headers;

  /// Exactly what is sent, which the airlock refuses unless [projection]
  /// draws it from [drawnFrom].
  final String body;

  /// How [body] is drawn from the entry [drawnFrom].
  final Projection projection;

  /// The recorded entry [body] is drawn from. It must belong to the
  /// trajectory, as [DecidesAndRecordsActions.recordedOn] reads it.
  final EntryId drawnFrom;
}

/// What an action would do to the world, typed, so the airlock can decide
/// and record it without knowing the action's types: one per [Program].
sealed class Reach {
  const Reach();
}

final class Reads extends Reach {
  const Reads(this.path);

  final RelativePath path;
}

final class Writes extends Reach {
  const Writes(this.file);

  final FileText file;
}

final class Starts extends Reach {
  const Starts(this.program, this.args);

  final ProgramName program;
  final Args args;
}

/// Reaches the world: a request goes to [origin], as [signIn], or under no
/// sign-in when null.
///
/// Null means no sign-in, never any: it is null exactly when the request
/// has none. So a rule granting a site under no sign-in must not match
/// a request that has one, or a grant to fetch a page anonymously would let
/// a trajectory make requests there as a bot.
///
/// A rule grants the origin and the sign-in together, never the origin
/// alone: every bot of a kind makes requests to the same sites, so a grant
/// by origin would let a trajectory go as any sign-in the web driver
/// holds.
///
/// Holds the whole [request], its exact body among it: the decision is about
/// what will be sent.
final class MakesWebRequest extends Reach {
  const MakesWebRequest(this.request);

  final WebRequest request;

  Origin get origin => request.origin;
  SignIn? get signIn => request.signIn;
}

/// Reaches the model: [call] goes out as its sign-in, to its model, with the
/// texts its [ModelRequest] entry holds. A rule grants it by the sign-in,
/// one the trajectory's rules let a model call go out as.
final class CallsTheModel extends Reach {
  const CallsTheModel(this.call);

  final ModelCall call;

  ModelSignInName get signIn => call.signIn;
  ModelName get model => call.model;
}

/// One agent's own trajectory: the line its actions are proposed on, with
/// rules [R] that say what it may do, and places [P] that say where in a
/// turn each entry happened.
///
/// Its drivers are those it was given, acting for the path, each wherever
/// it runs. They are reached only by an [Action] proposed at its crux, so
/// every such action passes its airlock.
///
/// This is the airlock service's side of a trajectory, set up when the
/// record shows the docking station started the path (its rules, in
/// `admitted`) and loop_launcher handed it users (`assigned`). The airlock
/// starts nothing. Whoever holds the drivers already has the power to touch
/// the world, so setting up a side grants nothing new.
final class Trajectory<R, P> {
  /// The side of the trajectory named [id], on [drivers], decided and
  /// recorded by [airlock], under [rules], whose programs run as [suit].
  ///
  /// [id] is the hash of the record entry that started the path, which the
  /// docking station writes, so no two trajectories share one and nothing here
  /// mints one.
  Trajectory({
    required this.id,
    required Iterable<CarriesOutActions> drivers,
    required this._airlock,
    required this.rules,
    required this.suit,
  }) : _drivers = List.unmodifiable(drivers);

  /// Names this trajectory in every entry it records.
  final TrajectoryId id;
  final R rules;

  /// The OS user this path's programs run as: the airlock service gives the
  /// path a program driver that runs as it. One per path, kept for the
  /// path's life.
  final Suit suit;

  final DecidesAndRecordsActions<R, P> _airlock;
  final List<CarriesOutActions> _drivers;
  final _decisions = StreamController<AirlockDecisionOnAction<P>>.broadcast(
    sync: true,
  );
  final _results =
      StreamController<
        ({AirlockDecisionOnAction<P> decision, Outcome<Object?> result})
      >.broadcast(sync: true);
  final _underway = StreamController<Underway<P>>.broadcast(sync: true);
  bool _stopped = false;

  /// This trajectory's tip at [place], where its actions are proposed in
  /// this process.
  ///
  /// Here, where [P] is known, so a place of another type does not compile;
  /// whoever is handed the crux never sees [P].
  Crux at(P place) => _AtPath(this, place);

  /// Refuses every action on this trajectory whose driver has not yet been
  /// reached. An action whose driver has been reached is not interrupted.
  /// Never undone.
  void stop() => _stopped = true;

  bool get stopped => _stopped;

  /// Each decision once the airlock has recorded it.
  Stream<AirlockDecisionOnAction<P>> get decisions => _decisions.stream;

  /// Each action's result, or why it was refused, once the airlock has
  /// recorded it, with the decision it follows.
  Stream<({AirlockDecisionOnAction<P> decision, Outcome<Object?> result})>
  get results => _results.stream;

  /// What drivers report while actions are underway: for a live view, and
  /// not recorded.
  Stream<Underway<P>> get underway => _underway.stream;

  D? _driver<D extends CarriesOutActions>() =>
      _drivers.whereType<D>().firstOrNull;

  Future<Outcome<O>> _consider<I, O>(
    Program<I, O> program,
    I input,
    P place, {
    EntryId? proposed,
  }) async {
    const stoppedByPerson = Deny('stopped', by: DecidedBy.person);
    final reach = await program._reach(input);
    var decision = stopped
        ? stoppedByPerson
        : await _airlock.decide(id, reach, rules);
    if (stopped) decision = stoppedByPerson;
    final decided = AirlockDecisionOnAction(
      id,
      place,
      reach,
      decision,
      proposed: proposed,
    );
    await _airlock.recordDecision(decided);
    _decisions.add(decided);
    final Outcome<O> result = switch (decision) {
      Deny(:final why) => Refused(why),
      Allow() =>
        await program._on(
              this,
              input,
              reach,
              (progress) => _underway.add(Underway(id, place, reach, progress)),
            ) ??
            Refused('this machine cannot run ${program.name}'),
    };
    await _airlock.recordResult(
      decided,
      result,
      resultAsJson: encodeOutcome(result, program._wire.outputToJson),
    );
    _results.add((decision: decided, result: result));
    return result;
  }

  /// [proposal], the logbook entry [proposed] on this path's chain,
  /// considered at [place] as an action proposed at [at]'s crux would be:
  /// decided and recorded, and carried out by a driver if it is allowed. Its
  /// decision and its result both name [proposed].
  ///
  /// Only for an entry on this path's own chain, which the logbook service
  /// takes only from this path's loop user. [place] is
  /// [ActionProposedByAgentLoop.place] read as a [P] by the airlock service,
  /// which knows [P].
  Future<void> consider(
    ActionProposedByAgentLoop proposal,
    P place, {
    required EntryId proposed,
  }) => proposal._work.on(this, place, proposed);
}

/// A trajectory's crux, at one place in a turn: its agent loop, the one
/// holder that extends the trajectory, proposing the next action there for
/// its airlock to decide, which records each entry at that place
/// (https://github.com/enspyrco/intersyntactic/pull/1168).
///
/// Made by [Trajectory.at] where the trajectory is, in the airlock
/// service, and by [Crux.through] in the agent loop, which is another
/// process: there an action's program and input go into the logbook as an
/// [ActionProposedByAgentLoop], and its continuation stays behind, since it
/// is the tool's own code. Either way, what comes after a tool's result
/// takes a crux and never handles the place. Two agents on one machine have
/// two cruxes; one step's two tool calls go through one trajectory's crux,
/// at two places.
sealed class Crux {
  const Crux();

  /// The crux for [turn] of the trajectory whose chain [link] writes to: it
  /// proposes each action at the turn's next step, from 0, so the model
  /// call, each action of a tool it asks for and the reply each get their
  /// own place, and a restarted loop gives each the same place again. Make
  /// one per turn and carry every action of the turn through it.
  factory Crux.through(
    ProposesActionsThroughTheRecord link, {
    required int turn,
  }) = _ThroughRecord;

  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input);
}

final class _AtPath<P> extends Crux {
  const _AtPath(this._trajectory, this._place);

  final Trajectory<Object?, P> _trajectory;
  final P _place;

  @override
  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input) =>
      _trajectory._consider(program, input, _place);
}

/// Decides each action on a trajectory, and records it.
///
/// What intersyntactic's airlock implements. It guards the drivers it is
/// given, not the mission: an agent that joins a mission with its own
/// drivers is decided, or not, by its own.
abstract interface class DecidesAndRecordsActions<R, P> {
  /// Whether a driver may carry out an action of [trajectory]'s that would
  /// do [reach], under [rules].
  ///
  /// Given the reach, not the action, so the decision is about exactly what is
  /// recorded: for a web request, the bytes it sends. Given the trajectory,
  /// so the airlock can read what holds for it now from its chain, such as
  /// the bot leased to it, at the moment of deciding; the decision names
  /// each entry it read in [Decision.reliedOn].
  Future<Decision> decide(TrajectoryId trajectory, Reach reach, R rules);

  /// Keeps [decision] in the logbook. An action's driver is reached only
  /// once its decision is kept; an error thrown here ends the call.
  ///
  /// Kept means it survives the logbook service crashing or being killed,
  /// not a power cut: the logbook service answers before forcing the entry
  /// to disk, and a power cut can leave an entry with missing bytes, which
  /// its `check()` reports. So "no driver is reached without a recorded
  /// decision" holds across crashes
  /// (https://github.com/intersyntactic/logbook/pull/12).
  ///
  /// A decision starts a chain of its own in the logbook (previous `-`):
  /// the chain a proposal is on is its loop user's, which the airlock may not
  /// extend. A web request's is an [AirlockDecisionOnWebRequest]; any other's
  /// body is the airlock's to choose, under
  /// [AirlockDecisionOnAction.kind]. No two may be byte-identical, since the
  /// logbook service refuses a repeated chain start, so one made for a
  /// proposal names it.
  Future<void> recordDecision(AirlockDecisionOnAction<P> decision);

  /// Keeps in the logbook what the action [decision] was about came to:
  /// [result], what it ran to or why it was refused, which [resultAsJson]
  /// holds as its program's codec writes it. The action's continuation sees
  /// [result] only once it is kept; an error thrown here ends the call. Kept
  /// as [recordDecision] keeps.
  ///
  /// It extends [decision]'s chain, its previous the decision. When
  /// [decision] answers a proposal,
  /// its body is [outcomeOfProposedActionToJson] of
  /// [AirlockDecisionOnAction.proposed] and [resultAsJson], under
  /// [outcomeOfProposedActionKind]: the one copy of what the action
  /// returned, which the loop that proposed it is waiting for.
  Future<void> recordResult(
    AirlockDecisionOnAction<P> decision,
    Outcome<Object?> result, {
    required Object? resultAsJson,
  });

  /// The kind and body of [entry], when it belongs to [trajectory]: the
  /// body as text, after its `<kind>\n<previous>\n` header. Or [Refused]
  /// with why not. Whoever reads it checks the kind it expects, since a
  /// loop may write a body of any shape under its own kinds.
  ///
  /// An entry belongs to a trajectory when it is on the trajectory's own
  /// chain, or when it is an [outcomeOfProposedActionKind] logbook entry the
  /// airlock kept for one of the trajectory's proposals: its `proposed` is
  /// on that chain. Only the airlock writes those, so a loop cannot make
  /// one. Any other entry is refused, never read: entry hashes are not
  /// secret, so without this a loop could name another trajectory's
  /// [ModelRequest], pieces or replies and have them sent as its own.
  /// [AskTheModel] reads its request and every piece through here, and
  /// [MakeWebRequest] the entry its body is drawn from.
  Future<Outcome<({String kind, String body})>> recordedOn(
    TrajectoryId trajectory,
    EntryId entry,
  );
}

/// What the airlock decided about one action, and [by] whom, so the record
/// tells "the rules let it through" from "the person said yes".
sealed class Decision {
  const Decision({required this.by, this.reliedOn = const []});

  final DecidedBy by;

  /// The logbook entries the airlock read to decide, beyond the rules: what
  /// held for the trajectory at that moment, such as the lease of the bot it
  /// may post as. Empty when the rules alone decided.
  final List<EntryId> reliedOn;
}

/// A driver may carry the action out.
final class Allow extends Decision {
  const Allow({required super.by, super.reliedOn});
}

/// No driver carries the action out, because [why]; its continuation is handed
/// [Refused] with that reason.
final class Deny extends Decision {
  const Deny(this.why, {required super.by, super.reliedOn});

  final String why;
}

/// What the airlock decided about an action that would do [reach], on the
/// trajectory named [trajectoryId], at [place] in a turn, before any driver
/// is reached. With no result recorded after it, the logbook shows the
/// action was cut short.
///
/// [place] is of type [P], which the agent loop supplies, since it knows
/// where in the turn it is, and the airlock records; nothing here computes
/// one.
final class AirlockDecisionOnAction<P> {
  const AirlockDecisionOnAction(
    this.trajectoryId,
    this.place,
    this.reach,
    this.decision, {
    this.proposed,
  });

  /// The kind of the logbook entry the airlock keeps it as, unless it is a
  /// web request's, which is an [AirlockDecisionOnWebRequest].
  static const kind = 'airlock-decision-on-action';

  final TrajectoryId trajectoryId;
  final P place;
  final Reach reach;
  final Decision decision;

  /// The [ActionProposedByAgentLoop] logbook entry that asked for the
  /// action; null for an action proposed in the airlock service's own
  /// process.
  final EntryId? proposed;
}

/// What a driver reported, [progress], while the action doing [reach] was
/// underway at [place] on the trajectory named [trajectoryId].
final class Underway<P> {
  const Underway(this.trajectoryId, this.place, this.reach, this.progress);

  final TrajectoryId trajectoryId;
  final P place;
  final Reach reach;
  final Progress progress;
}
