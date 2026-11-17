import 'dart:async';
import 'dart:convert' show utf8;

import 'package:is_content_id/is_content_id.dart' show ObjectId;
import 'package:is_effects/is_effects.dart';
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, EntryId, RendererId, TrajectoryId;

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
/// A closed set: [ReadFile], [WriteFile], [Executable] and [MakeWebRequest].
/// Programs reach drivers, so they are part of what is trusted, with the
/// drivers and the airlock; a new kind of action is a new driver and program
/// here.
///
/// A trajectory's prompts are not programs: the model is the agent
/// planning, so a prompt is not decided, and no tool is in it. How it
/// reaches the model and is recorded is not this contract's.
sealed class Program<I, O> {
  const Program();

  static const read = ReadFile();
  static const write = WriteFile();
  static const web = MakeWebRequest();

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

  /// What [input] would do to the world. Only a web request asks [findRenderer]
  /// for the renderer it names.
  Future<Reach> _reach(I input, _FindRenderer findRenderer);

  /// How this program, its input and its output travel between the agent
  /// loop and the airlock.
  _Wire<I, O> get _wire;

  /// This program with the input [json] holds. Throws a [FormatException]
  /// when it holds none.
  _Work<I, O> _work(Object? json) =>
      _Work(this, _wire.inputFromJson(json, 'input'));

  /// [input], whose reach is [reach], performed by [trajectory]'s driver
  /// for this program, reporting to [report] while it runs, or null when it
  /// has none. Only a web request waits on [rendered], for its body.
  Future<Outcome<O>>? _on(
    Trajectory<Object?, Object?> trajectory,
    I input,
    Reach reach,
    _Rendered rendered,
    Report report,
  );
}

/// The renderer a name names, or null: [DecidesAndRecordsActions.renderer].
typedef _FindRenderer = Future<Renderer?> Function(RendererName name);

/// The body a renderer recorded for this action's [Decided] entry, or why
/// there is none: [DecidesAndRecordsActions.rendered].
typedef _Rendered = Future<Outcome<String>> Function();

/// Reads the file at a path under the file driver's root.
final class ReadFile extends Program<RelativePath, ReadResult> {
  const ReadFile();

  @override
  String get name => 'read';

  @override
  Future<Reach> _reach(RelativePath path, _FindRenderer findRenderer) async =>
      Reads(path);

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
    _Rendered rendered,
    Report report,
  ) => trajectory._driver<ReadsAndWritesFiles>()?.read(path);
}

/// Writes a file, creating its folder.
final class WriteFile extends Program<FileText, Wrote> {
  const WriteFile();

  @override
  String get name => 'write';

  @override
  Future<Reach> _reach(FileText file, _FindRenderer findRenderer) async =>
      Writes(file);

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
    _Rendered rendered,
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
  Future<Reach> _reach(Args args, _FindRenderer findRenderer) async =>
      Starts(program, args);

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
    _Rendered rendered,
    Report report,
  ) => trajectory._driver<RunsPrograms>()?.runProgram(
    program,
    args,
    report: report,
  );
}

/// Makes a [WebRequest] to a site, through the sign-in it names, with the
/// body its renderer drew from recorded entries and recorded.
///
/// An action, decided like any other: a request a tool makes to a chat, an
/// issue tracker or an API. Not a prompt, which is the agent planning and is
/// not decided.
///
/// The renderer is named exactly before the decision, so the [Decided]
/// entry says which code will write the words. The renderer subscribes to
/// the record for that entry, draws the body, and records it; the web driver
/// carries the request out with what was recorded. So the words exist only
/// once the decision is kept, the exact bytes that went out are in the
/// record, and the airlock never talks to a renderer
/// (https://github.com/enspyrco/intersyntactic/issues/1147#issuecomment-6905923566).
final class MakeWebRequest extends Program<WebRequest, WebRequestOutcome> {
  const MakeWebRequest();

  @override
  String get name => 'web';

  @override
  Future<Reach> _reach(WebRequest request, _FindRenderer findRenderer) async =>
      MakesWebRequest(request, await findRenderer(request.renderer));

  @override
  _Wire<WebRequest, WebRequestOutcome> get _wire => const _Wire(
    {'program': 'web'},
    inputToJson: _webRequestToJson,
    inputFromJson: _webRequestFromJson,
    outputToJson: encodeWebRequestOutcome,
    outputFromJson: decodeWebRequestOutcome,
  );

  @override
  Future<Outcome<WebRequestOutcome>>? _on(
    Trajectory<Object?, Object?> trajectory,
    WebRequest request,
    covariant MakesWebRequest reach,
    _Rendered rendered,
    Report report,
  ) => switch ((trajectory._driver<CarriesOutWebRequests>(), reach.renderer)) {
    (null, _) => null,
    (final web?, _?) => _make(web, rendered(), request),
    // Decided as a denial before any driver, so not reached.
    (_, null) => Future.value(Refused('no renderer named ${request.renderer}')),
  };

  static Future<Outcome<WebRequestOutcome>> _make(
    CarriesOutWebRequests web,
    Future<Outcome<String>> rendering,
    WebRequest request,
  ) async => switch (await rendering) {
    Refused(:final why) => Refused(why),
    Ran(output: final body) => await web.carryOutWebRequest(
      Request(
        request.origin,
        method: request.method,
        path: request.path,
        signIn: request.signIn,
        headers: request.headers,
        body: body,
      ),
    ),
  };
}

/// A web request a tool asks for: where to, as whom, and which recorded
/// entries the words are drawn from, by which renderer. It holds no words of
/// its own, so a tool cannot put any in a request.
///
/// [path] and [headers] are checked as is_effects's `Request` checks them:
/// a [WebPath] cannot name another site, and [headers] hold no credential.
final class WebRequest {
  WebRequest(
    this.origin, {
    required this.renderer,
    Iterable<EntryId> entries = const [],
    this.method = Method.post,
    this.path = WebPath.root,
    this.signIn,
    Map<String, String> headers = const {},
  }) : entries = List.unmodifiable(entries),
       headers = validatedHeaders(headers);

  final Origin origin;
  final Method method;
  final WebPath path;

  /// Who it goes as; null goes under no sign-in.
  final SignIn? signIn;
  final Map<String, String> headers;

  /// The renderer that draws the body, by name.
  final RendererName renderer;

  /// The recorded entries the body is drawn from, in the order the renderer
  /// is given them: turns, events, the airlock's own entries, chunks of a
  /// reply. Any one the journal does not hold refuses the request.
  final List<EntryId> entries;
}

/// A renderer's name, such as `teams-reply`: what a [WebRequest] names, and the
/// airlock resolves to the exact [Renderer] before deciding it.
final class RendererName {
  const RendererName._(this.value);

  /// [raw] as a renderer's name, or null unless it is lowercase letters,
  /// digits and `-`, starting with a letter.
  static RendererName? parse(String raw) =>
      _rendererName.hasMatch(raw) ? RendererName._(raw) : null;

  final String value;

  @override
  bool operator ==(Object other) =>
      other is RendererName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final _rendererName = RegExp(r'^[a-z][a-z0-9-]*$');

/// A renderer named exactly: [id], its source, and [executable], the render
/// runner built with it.
///
/// [id] names the renderer proper, a published pub package whose `lib/` is
/// only the pure function from entries to a body, which a person can read
/// and check: the sha256 of its published archive, the value `pubspec.lock`
/// records and pub.dev reports as `archive_sha256` (Nick, 16 Nov). The
/// archive does not hold the packages it depends on, so [executable], built
/// with every one of them, is what pins the whole of the code that wrote a
/// request's body; the two are recorded together. So the check that a [Rendered]
/// entry came from this renderer rests on [executable]; [id] is enough on
/// its own only for a renderer with no dependencies, which `teams-reply`
/// holds itself to with a test.
///
/// [executable] names the render runner built with it: the one shared
/// program that runs a renderer and writes its [Rendered] entry, reading
/// each request's entries from the journal, compiled once per renderer
/// with [id] as a define, which it reports in [Rendered.renderer]. Since
/// the define is compiled in, each renderer's render runner has its own
/// build, and that build is what the journal's writer approves. Both are
/// recorded in the [Decided] entry, so an old request can be rebuilt from
/// the journal and checked
/// (https://github.com/enspyrco/intersyntactic/issues/1147).
final class Renderer {
  const Renderer(this.id, {required this.executable});

  final RendererId id;

  /// The journal object holding the render runner's bytes, built with
  /// [id].
  final ObjectId executable;
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
/// Holds the whole [request] and the [renderer] its name resolved to, never
/// a body, which does not exist yet when this is decided: the record says
/// which entries the words were drawn from and which code drew them, so it
/// holds no copy of what was said.
final class MakesWebRequest extends Reach {
  const MakesWebRequest(this.request, this.renderer);

  final WebRequest request;

  /// The exact renderer [request] names, or null when its name named none
  /// on this machine. A request with no renderer is denied before the rules
  /// are asked, since there would be no way to draw its words.
  final Renderer? renderer;

  Origin get origin => request.origin;
  SignIn? get signIn => request.signIn;
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
  final _entries = StreamController<Entry<P>>.broadcast(sync: true);
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

  /// Each entry once the airlock has recorded it.
  Stream<Entry<P>> get entries => _entries.stream;

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
    final reach = await program._reach(input, _airlock.renderer);
    var decision = switch (reach) {
      _ when stopped => stoppedByPerson,
      MakesWebRequest(renderer: null, :final request) => Deny(
        'no renderer named ${request.renderer}',
        by: DecidedBy.rules,
      ),
      Reads() ||
      Writes() ||
      Starts() ||
      MakesWebRequest() => await _airlock.decide(reach, rules),
    };
    if (stopped) decision = stoppedByPerson;
    final decided = Decided(id, place, reach, decision, proposed: proposed);
    await _record(decided);
    final Outcome<O> outcome = switch (decision) {
      Deny(:final why) => Refused(why),
      Allow() =>
        await program._on(
              this,
              input,
              reach,
              () => _airlock.rendered(decided),
              (progress) => _underway.add(Underway(id, place, reach, progress)),
            ) ??
            Refused('this machine cannot run ${program.name}'),
    };
    await _record(
      Returned._(
        id,
        place,
        reach,
        outcome,
        encodeOutcome(outcome, program._wire.outputToJson),
        proposed,
      ),
    );
    return outcome;
  }

  Future<void> _record(Entry<P> entry) async {
    await _airlock.record(entry);
    _entries.add(entry);
  }

  /// [proposal], the `proposed` entry [proposed] on this path's chain,
  /// considered at [place] as an action proposed at [at]'s crux would be:
  /// decided and recorded, and carried out by a driver if it is allowed. Its
  /// [Decided] and [Returned] entries name [proposed].
  ///
  /// Only for an entry on this path's own chain, which the journal takes
  /// only from this path's loop user, and only once the journal enforces
  /// that. [place] is [Proposal.place] read as a [P] by the airlock service,
  /// which knows [P].
  Future<void> consider(
    Proposal proposal,
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
/// process: there an action's program and input go into the record as a
/// [Proposal], and its continuation stays behind, since it is the tool's own
/// code. Either
/// way, what comes after a tool's result takes a crux and never handles
/// the place. Two agents on one machine have two cruxes; one step's two tool
/// calls go through one trajectory's crux, at two places.
sealed class Crux {
  const Crux();

  /// The crux, at [place], of the trajectory whose chain [link] writes to.
  ///
  /// [place] is already the JSON its trajectory reads places from, since
  /// the loop and the airlock service agree its type between them.
  const factory Crux.through(
    ProposesActionsThroughTheRecord link, {
    required Object? place,
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
  /// Whether a driver may carry out an action that would do [reach], under
  /// [rules].
  ///
  /// Given the reach, not the action, so the decision is about exactly what is
  /// recorded: for a web request, the renderer its name resolved to.
  Future<Decision> decide(Reach reach, R rules);

  /// Keeps [entry]. An action's driver is reached only once its [Decided] entry
  /// is kept, and its outcome flows on only once its [Returned] entry is; an
  /// error thrown here ends the call.
  ///
  /// Kept means it survives the journal crashing or being killed, not a
  /// power cut: the journal answers before forcing the entry to disk, and a
  /// power cut can leave an entry with missing bytes, which its `check()`
  /// reports. So "no driver is reached without a recorded [Decided]" holds
  /// across crashes (https://github.com/intersyntactic/journal/pull/12).
  Future<void> record(Entry<P> entry);

  /// The renderer called [name], or null when there is none, so the
  /// [Decided] entry for a web request names its renderer exactly.
  Future<Renderer?> renderer(RendererName name);

  /// The body the renderer recorded for [decided], an allowed web request's
  /// [Decided] entry, once the airlock has read it from the record; or
  /// [Refused] with why there is none.
  ///
  /// Called only after [decided] is kept. The renderer subscribes to the
  /// record for it, reads the entries the request draws from, and records the
  /// body, or a refusal when an entry is missing or fails its checks, in an
  /// entry of its own whose previous is [decided]. The airlock never talks
  /// to a renderer: it reads that entry, and accepts it only from the
  /// renderer [decided] names. A renderer that does not answer in time is
  /// the airlock's to refuse, and its [Returned] entry's previous is then
  /// [decided] instead.
  ///
  /// The render runner reports the renderer it was built with, the
  /// archive hash its `pubspec.lock` records, given as a define at compile
  /// time (as is_journal's `Journal.builtDefine` gives a journal its code
  /// hash), and an entry
  /// whose renderer reports anything other than the id [decided] names is
  /// refused. That rules out a stale or mis-built renderer being taken for
  /// this one, not someone building one that lies.
  Future<Outcome<String>> rendered(Decided<P> decided);
}

/// What the airlock decided about one action, and [by] whom, so the record
/// tells "the rules let it through" from "the person said yes".
sealed class Decision {
  const Decision({required this.by});

  final DecidedBy by;
}

/// A driver may carry the action out.
final class Allow extends Decision {
  const Allow({required super.by});
}

/// No driver carries the action out, because [why]; its continuation is handed
/// [Refused] with that reason.
final class Deny extends Decision {
  const Deny(this.why, {required super.by});

  final String why;
}

/// One entry in a trajectory's record: [Decided] before an action goes out,
/// and [Returned] when it comes back.
///
/// Each is at a [place] in a turn, of type [P], which the agent loop
/// supplies, since it knows where in the turn it is, and the airlock
/// records; nothing here computes one.
///
/// Every kind takes [P] and nothing more, so a switch over the kinds is
/// exhaustive: a kind with a type parameter its parent does not have cannot
/// be covered by a case.
sealed class Entry<P> {
  const Entry(this.trajectoryId, this.place);

  /// The trajectory this entry is of.
  final TrajectoryId trajectoryId;

  /// Where in a turn this entry happened.
  final P place;
}

/// An action that would do [reach] was decided, and no driver has been
/// reached yet. Without a [Returned] entry after it, the record shows the
/// action was cut short.
final class Decided<P> extends Entry<P> {
  const Decided(
    super.trajectoryId,
    super.place,
    this.reach,
    this.decision, {
    this.proposed,
  });

  final Reach reach;
  final Decision decision;

  /// The `proposed` entry that asked for the action; null for an action
  /// proposed in the airlock service's own process.
  final EntryId? proposed;
}

/// The action that would do [reach] came back, with its [outcome], whether
/// it ran or was refused. Made only by a trajectory, which knows the
/// action's program, so [ReturnedProposal.of] can write what came back in
/// full.
final class Returned<P> extends Entry<P> {
  const Returned._(
    super.trajectoryId,
    super.place,
    this.reach,
    this.outcome,
    this._outcomeJson,
    this.proposed,
  );

  final Reach reach;
  final Outcome<Object?> outcome;

  /// [outcome] as its program's codec writes it.
  final Object? _outcomeJson;

  /// The `proposed` entry that asked for the action; null for an action
  /// proposed in the airlock service's own process.
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
