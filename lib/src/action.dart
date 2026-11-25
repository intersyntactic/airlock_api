import 'dart:convert' show jsonEncode, utf8;

import 'package:checked_json/checked_json.dart';

import 'package:is_content_id/is_content_id.dart' show ObjectId;
import 'package:is_effects/is_effects.dart';
import 'package:is_model_vocabulary/is_model_vocabulary.dart';
import 'package:is_reply_vocabulary/is_reply_vocabulary.dart';
import 'package:is_sign_in_vocabulary/is_sign_in_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';
import 'package:is_shapes/is_shapes.dart' show DecidedBy, EntryId, TrajectoryId;

part 'pool_user.dart';
part 'wire_reading.dart';
part 'proposal.dart';
part 'waiting_to_start.dart';
part 'model_request.dart';
part 'decision_entry.dart';

/// What a tool's code returns for a call: an action whose outcome it needs
/// before it can answer, its answer, or that it could not answer. [A] is the
/// type of the answer, the tool's output type.
///
/// A tool holds no driver and touches nothing. Each action it returns is
/// proposed through [ProposesActions], which has it decided by the airlock
/// and gives what became of it to the action's continuation. So a tool can
/// describe nothing an action cannot express.
///
/// Not an [Outcome], which is what happened to one action. An [Action] never
/// reaches the model: [Done]'s value does, written out by the tool's
/// definition, and [Failed]'s reason does, as an error.
sealed class Result<A> {
  const Result();

  /// This result with its answer, once there is one, given to [f].
  ///
  /// Proposes nothing: an action's continuation is extended, so [f] is
  /// applied when a later [Action.next] reaches an answer, and every action
  /// on the way is still proposed. So whoever turns a tool's answer into
  /// what the model is told can do it without proposing the actions.
  Result<B> map<B>(B Function(A answer) f);
}

/// Run a program on an input, then continue with what became of it.
///
/// One round trip to the world, which the airlock decides: what a tool asks
/// for to carry out an intent. A read, a write, `git diff` and a web request
/// to a chat are all actions, each one program on an input, and each has
/// exactly one [Outcome].
///
/// The continuation travels with the action, not in the tool, so one tool
/// can serve concurrent calls without keeping state for any of them. It is
/// private: what it is given comes from [next], never from whoever holds
/// the action.
///
/// Typed only by the answer it leads to, [A]. The program's input and output
/// types stay inside, where [next] uses them, so whoever holds an action
/// never handles either, and a switch over a [Result] covers every action
/// with `case Action()`. Dart's generics are covariant: a caller passing an
/// outcome to the continuation itself would be checked only when it ran.
abstract final class Action<A> extends Result<A> {
  const Action._();

  /// This action proposed through [proposer], and the result it leads to.
  Future<Result<A>> next(ProposesActions proposer);

  @override
  Action<B> map<B>(B Function(A answer) f);
}

/// Proposes an action and gives back what became of it: in the agent loop,
/// through the logbook, for the airlock to decide and a driver to carry
/// out.
abstract interface class ProposesActions {
  /// [program] run on [input], proposed; its outcome once the airlock has
  /// decided it and, if allowed, a driver has carried it out.
  Future<Outcome<O>> propose<I, O>(Program<I, O> program, I input);
}

/// An [Action] of a [Program] taking [I] and giving [O].
///
/// Made only by its program ([Program.run], [Program.runOrFail]), so [I]
/// is the program's own input type. Built from a program and an input side
/// by side, inference would widen [I] to fit both, and a [WriteFile] given a
/// `String` would compile.
final class _Action<I, O, A> extends Action<A> {
  const _Action(this._program, this._input, this._then) : super._();

  final Program<I, O> _program;
  final I _input;
  final Result<A> Function(Outcome<O> outcome) _then;

  @override
  Future<Result<A>> next(ProposesActions proposer) =>
      proposer.propose(_program, _input).then(_then);

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
/// A closed set: [ReadFile], [ReadFileBytes], [WriteFile], [Executable],
/// [MakeWebRequests], [FetchFromWeb], [AskTheModel] and
/// [ReplyToOwnConversation]. Whoever carries one out implements
/// [CarriesOutEachProgram], which names each, so a new kind of action is a
/// new program here and a new method there.
///
/// A model call is one too, [AskTheModel]: the model is outside the
/// station, so the case's words leave the machine with every call.
sealed class Program<I, O> {
  const Program();

  static const read = ReadFile();
  static const readBytes = ReadFileBytes();
  static const write = WriteFile();
  static const makeWebRequests = MakeWebRequests();
  static const fetch = FetchFromWeb();
  static const askTheModel = AskTheModel();
  static const replyToOwnConversation = ReplyToOwnConversation();

  /// For the model and the logbook; an [Executable] is compared by it.
  String get name;

  /// The action of running this program on [input], continuing with [then].
  Action<A> run<A>(
    I input, {
    required Result<A> Function(Outcome<O> outcome) then,
  }) => _Action(this, input, then);

  /// An action that fails the tool unless it ran to the end: [then] is
  /// called only with the output. Stopping partway says so in the failure,
  /// since unlike nothing running, the world has changed.
  Action<A> runOrFail<A>(
    I input, {
    required Result<A> Function(O output) then,
  }) => _Action(
    this,
    input,
    (outcome) => switch (outcome) {
      Ran(:final output) => then(output),
      NothingRan(:final why) => Failed(why),
      StoppedPartway(:final why) => Failed('stopped partway: $why'),
    },
  );

  /// What [input] would do to the world, as far as the input alone says:
  /// what the airlock decides and the logbook keeps.
  Reach reachOf(I input);

  /// [input] carried out by [by]'s method for this program; null when [by]
  /// cannot run it.
  Future<Outcome<O>>? carriedOutBy(CarriesOutEachProgram by, I input);

  /// The body of an [ActionProposedByAgentLoop.kind] logbook entry
  /// proposing this program on [input] at [place].
  String proposal(I input, {required PlaceInTrajectory at}) => jsonEncode({
    'place': at.toJson(),
    ..._wire.program,
    'input': _wire.inputToJson(input),
  });

  /// [outcome] as the airlock writes it in an
  /// [outcomeOfProposedActionKind] logbook entry, by this program's codec.
  Object? outcomeToJson(Outcome<O> outcome) =>
      encodeOutcome(outcome, _wire.outputToJson);

  /// [json], as [outcomeToJson] wrote it, read back. Throws a
  /// [FormatException] naming the field.
  Outcome<O> outcomeFromJson(Object? json) =>
      decodeOutcome(json, _wire.outputFromJson);

  /// How this program, its input and its output travel between the agent
  /// loop and the airlock.
  _Wire<I, O> get _wire;

  /// This program with the input [json] holds. Throws a [FormatException]
  /// when it holds none.
  _Work<I, O> _work(Object? json, [String field = 'input']) =>
      _Work(this, _wire.inputFromJson(json, field));
}

/// Carries out each kind of [Program]: one method per program, each given
/// that program's own input type. What the airlock implements over its
/// drivers. A method returns null when this machine cannot run that
/// program.
abstract interface class CarriesOutEachProgram {
  Future<Outcome<ReadResult>>? readFile(RelativePath path);

  Future<Outcome<BytesReadResult>>? readFileBytes(RelativePath path);

  Future<Outcome<Wrote>>? writeFile(FileText file);

  Future<Outcome<ExecResult>>? runExecutable(ProgramName program, Args args);

  /// Exactly [requests], in order, each bounded by the path prefix the
  /// airlock granted it.
  Future<Outcome<List<WebResponse>>>? makeWebRequests(
    List<ProposedRequest> requests,
  );

  Future<Outcome<WebResponse>>? fetchFromWeb(WebFetch fetch);

  Future<Outcome<ModelReply>>? askTheModel(ModelCall call);

  /// [content] posted to the endpoint and as the sign-in the airlock
  /// granted, in [Allow.grantedReply].
  Future<Outcome<List<PostedMessage>>>? replyToOwnConversation(
    ReplyContent content,
  );
}

/// Reads the file at a path under the file driver's root.
final class ReadFile extends Program<RelativePath, ReadResult> {
  const ReadFile();

  @override
  String get name => 'read';

  @override
  Reach reachOf(RelativePath path) => Reads(path);

  @override
  Future<Outcome<ReadResult>>? carriedOutBy(
    CarriesOutEachProgram by,
    RelativePath path,
  ) => by.readFile(path);

  @override
  _Wire<RelativePath, ReadResult> get _wire => const _Wire(
    {'program': 'read'},
    inputToJson: encodeRelativePath,
    inputFromJson: decodeRelativePath,
    outputToJson: encodeReadResult,
    outputFromJson: decodeReadResult,
  );
}

/// Reads the exact bytes of the file at a path under the file driver's root,
/// such as a .docx's zip. Every byte returned goes into the logbook, so the
/// driver refuses a file over its size limit.
final class ReadFileBytes extends Program<RelativePath, BytesReadResult> {
  const ReadFileBytes();

  @override
  String get name => 'read-bytes';

  @override
  Reach reachOf(RelativePath path) => Reads(path, as: ReadsAs.bytes);

  @override
  Future<Outcome<BytesReadResult>>? carriedOutBy(
    CarriesOutEachProgram by,
    RelativePath path,
  ) => by.readFileBytes(path);

  @override
  _Wire<RelativePath, BytesReadResult> get _wire => const _Wire(
    {'program': 'read-bytes'},
    inputToJson: encodeRelativePath,
    inputFromJson: decodeRelativePath,
    outputToJson: encodeBytesReadResult,
    outputFromJson: decodeBytesReadResult,
  );
}

/// Writes a file, creating its folder.
final class WriteFile extends Program<FileText, Wrote> {
  const WriteFile();

  @override
  String get name => 'write';

  @override
  Reach reachOf(FileText file) => Writes(file);

  @override
  Future<Outcome<Wrote>>? carriedOutBy(
    CarriesOutEachProgram by,
    FileText file,
  ) => by.writeFile(file);

  @override
  _Wire<FileText, Wrote> get _wire => const _Wire(
    {'program': 'write'},
    inputToJson: encodeFileText,
    inputFromJson: decodeFileText,
    outputToJson: encodeWrote,
    outputFromJson: decodeWrote,
  );
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
  Reach reachOf(Args args) => Starts(program, args);

  @override
  Future<Outcome<ExecResult>>? carriedOutBy(
    CarriesOutEachProgram by,
    Args args,
  ) => by.runExecutable(program, args);

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
}

/// Makes [ProposedRequest]s to the web, exactly these, in order, each to its origin
/// as its sign-in: what the tool that proposed them built.
///
/// The airlock knows no chat and no module. It decides the exact requests,
/// granting each one's origin, sign-in and path together, so the decision
/// is about exactly what will be sent and can refuse any of it before a
/// byte leaves. It checks where a body goes, never what it says. A GET is a
/// [FetchFromWeb], and a header other than `content-type` is refused, so
/// nothing rides out in a header. Once allowed, the web driver sends them
/// in order and stops at the first that fails, without retrying.
final class MakeWebRequests
    extends Program<List<ProposedRequest>, List<WebResponse>> {
  const MakeWebRequests();

  @override
  String get name => 'make-web-requests';

  @override
  Reach reachOf(List<ProposedRequest> requests) => MakesWebRequests(requests);

  @override
  Future<Outcome<List<WebResponse>>>? carriedOutBy(
    CarriesOutEachProgram by,
    List<ProposedRequest> requests,
  ) => by.makeWebRequests(requests);

  @override
  _Wire<List<ProposedRequest>, List<WebResponse>> get _wire => const _Wire(
    {'program': 'make-web-requests'},
    inputToJson: _requestsToJson,
    inputFromJson: _requestsFromJson,
    outputToJson: _webResponsesToJson,
    outputFromJson: _webResponsesFromJson,
  );
}

/// Fetches from a site, through the sign-in it names, with a GET that sends
/// no body and no headers, and keeps the response's body as [WebFetch.keep]
/// asks: a document's bytes, or a listing's text.
///
/// Nothing is drawn from the logbook, since nothing is sent but the
/// address. The path is decided as written, so what the model chose for it
/// reaches only the origin the rules grant with that sign-in; a rule can
/// bound it further by prefix. Every byte kept goes into the logbook in the
/// outcome.
final class FetchFromWeb extends Program<WebFetch, WebResponse> {
  const FetchFromWeb();

  @override
  String get name => 'fetch';

  @override
  Reach reachOf(WebFetch fetch) => FetchesFromWeb(fetch);

  @override
  Future<Outcome<WebResponse>>? carriedOutBy(
    CarriesOutEachProgram by,
    WebFetch fetch,
  ) => by.fetchFromWeb(fetch);

  @override
  _Wire<WebFetch, WebResponse> get _wire => const _Wire(
    {'program': 'fetch'},
    inputToJson: _webFetchToJson,
    inputFromJson: _webFetchFromJson,
    outputToJson: encodeWebResponse,
    outputFromJson: decodeWebResponse,
  );
}

/// Replies to the conversation the trajectory was started from: posts the
/// [ReplyContent] there and nowhere else, as the sign-in the airlock chose.
///
/// The model gives the content alone. Where it goes and as whom are
/// [Allow.grantedReply]: the endpoint the docking station recorded when it
/// admitted the event that started the trajectory, and the sign-in the
/// rules let a reply to it go as. The outcome is each [PostedMessage],
/// answering the granted endpoint, so the conversation the logbook records
/// is the grant's.
final class ReplyToOwnConversation
    extends Program<ReplyContent, List<PostedMessage>> {
  const ReplyToOwnConversation();

  @override
  String get name => 'reply-to-own-conversation';

  @override
  Reach reachOf(ReplyContent content) => RepliesToOwnConversation(content);

  @override
  Future<Outcome<List<PostedMessage>>>? carriedOutBy(
    CarriesOutEachProgram by,
    ReplyContent content,
  ) => by.replyToOwnConversation(content);

  @override
  _Wire<ReplyContent, List<PostedMessage>> get _wire => const _Wire(
    {'program': 'reply-to-own-conversation'},
    inputToJson: encodeReplyContent,
    inputFromJson: decodeReplyContent,
    outputToJson: _postedMessagesToJson,
    outputFromJson: _postedMessagesFromJson,
  );
}

/// A GET a tool asks for: where to, as whom, and what of the response's
/// body to keep. It has no body or headers to carry words.
final class WebFetch {
  const WebFetch(
    this.origin, {
    required this.keep,
    this.path = WebPath.root,
    this.signIn,
  });

  final Origin origin;
  final WebPath path;

  /// Who it goes as; null goes under no sign-in.
  final SignIn? signIn;
  final BodyToKeep keep;
}

/// Asks the model, through the model driver, as the [ModelCall]'s sign-in,
/// with the system prompt and request its [ModelRequestFromPieces] entry holds.
///
/// The one action the loop proposes for itself rather than drawing from an
/// intent in the model's reply: the loop holds no sign-in and has no
/// network, so this is its only way to reach the model. The airlock allows
/// it only as a sign-in the trajectory's rules let a model call go out as.
///
/// Once allowed, the airlock reads the [ModelRequestFromPieces] and each of
/// its pieces from this trajectory's own chain, joins each text, checks it
/// against its sha256, and hands the driver exactly those texts. Any piece
/// missing, on another chain, or not joining to its hash refuses the call
/// before the driver is reached. The whole [ModelReply] is the outcome,
/// written once.
final class AskTheModel extends Program<ModelCall, ModelReply> {
  const AskTheModel();

  @override
  String get name => 'model';

  @override
  Reach reachOf(ModelCall call) => CallsTheModel(call);

  @override
  Future<Outcome<ModelReply>>? carriedOutBy(
    CarriesOutEachProgram by,
    ModelCall call,
  ) => by.askTheModel(call);

  @override
  _Wire<ModelCall, ModelReply> get _wire => const _Wire(
    {'program': 'model'},
    inputToJson: _modelCallToJson,
    inputFromJson: _modelCallFromJson,
    outputToJson: encodeModelReply,
    outputFromJson: decodeModelReply,
  );
}

/// A model call a loop proposes: as which of the person's model sign-ins,
/// to which model, and the [ModelRequestFromPieces] entry, written on its
/// trajectory's chain before this, that holds exactly what is sent.
final class ModelCall {
  const ModelCall({
    required this.signIn,
    required this.model,
    required this.request,
  });

  final ModelSignInName signIn;
  final ModelName model;

  /// The [ModelRequestFromPieces] entry.
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

/// What an action would do to the world, typed, so the airlock can decide
/// and write it to the logbook without knowing the action's types: one per
/// [Program].
sealed class Reach {
  const Reach();
}

/// Reads the file at [path], as text or as its exact bytes. Either way it
/// reveals the same file, so a rule granting [path] grants both.
final class Reads extends Reach {
  const Reads(this.path, {this.as = ReadsAs.text});

  final RelativePath path;

  /// Which program reads it, so the logbook names the one that ran.
  final ReadsAs as;
}

/// How a [Reads] reads its file: [ReadFile] or [ReadFileBytes].
enum ReadsAs { text, bytes }

final class Writes extends Reach {
  const Writes(this.file);

  final FileText file;
}

final class Starts extends Reach {
  const Starts(this.program, this.args);

  final ProgramName program;
  final Args args;
}

/// Reaches the world: makes [requests], exactly these, in order, each to its
/// origin as its sign-in.
///
/// Holds every exact request, bodies among them, so the decision is about
/// what will be sent: the airlock grants each request's origin, sign-in and
/// path together, never the origin alone, and all of them or none. Never
/// empty, never a GET, and no header but `content-type`, as read from a
/// proposal.
final class MakesWebRequests extends Reach {
  MakesWebRequests(List<ProposedRequest> requests)
    : requests = List.unmodifiable(requests);

  final List<ProposedRequest> requests;
}

/// Reaches the world with an address alone: a GET goes to [origin], as
/// [signIn] or under none when null, and its response's body is kept as
/// [fetch] asks. Its own reach, so a grant to post somewhere is not a grant
/// to fetch from it, or the other way round.
///
/// A null sign-in means no sign-in, never any: a rule granting a site under
/// no sign-in must not match a fetch that has one, or a grant to read a
/// page anonymously would let a trajectory read there as a bot. A rule
/// grants the origin and the sign-in together, never the origin alone.
final class FetchesFromWeb extends Reach {
  const FetchesFromWeb(this.fetch);

  final WebFetch fetch;

  Origin get origin => fetch.origin;
  SignIn? get signIn => fetch.signIn;
  WebPath get path => fetch.path;
}

/// Reaches the world: posts [content] to the conversation the trajectory
/// was started from, and only there. It names no conversation and no
/// sign-in, since the airlock grants the trajectory's own endpoint and the
/// sign-in to reply as, so a grant to reply is never a grant to post
/// anywhere else. Holds the exact text and footer, so the decision is
/// about what will be sent.
final class RepliesToOwnConversation extends Reach {
  const RepliesToOwnConversation(this.content);

  final ReplyContent content;
}

/// Reaches the model: [call] goes out as its sign-in, to its model, with the
/// texts its [ModelRequestFromPieces] entry holds. A rule grants it by the sign-in,
/// one the trajectory's rules let a model call go out as.
final class CallsTheModel extends Reach {
  const CallsTheModel(this.call);

  final ModelCall call;

  ModelSignInName get signIn => call.signIn;
  ModelName get model => call.model;
}

/// What the airlock decided about one action.
sealed class Decision {
  const Decision({this.reliedOn = const []});

  /// The logbook entries the airlock read to decide, beyond the rules: what
  /// held for the trajectory at that moment, such as the lease of the bot it
  /// may post as. Empty when the rules alone decided.
  final List<EntryId> reliedOn;
}

/// A driver may carry the action out.
///
/// [grantedPathPrefixes] is the prefix each web request was granted under,
/// which bounds where it and its redirects may go on its origin: one per
/// request of a [MakesWebRequests], in order, one for a [FetchesFromWeb],
/// none for any other reach. A web action allowed with any other count is
/// refused before a driver is reached, never sent unbounded. `/` grants the
/// whole site.
final class Allow extends Decision {
  Allow({
    required this.by,
    super.reliedOn,
    required List<PathPrefix> grantedPathPrefixes,
  }) : grantedPathPrefixes = List.unmodifiable(grantedPathPrefixes),
       grantedReply = null;

  /// An allowed action that makes no web request, so is granted no path.
  const Allow.withNoPaths({required this.by, super.reliedOn})
    : grantedPathPrefixes = const [],
      grantedReply = null;

  /// An allowed [RepliesToOwnConversation], granted the trajectory's own
  /// endpoint [to] to post to, as [asSignIn].
  Allow.toReplyTo(
    ReplyEndpoint to, {
    required SignIn asSignIn,
    required this.by,
    super.reliedOn,
  }) : grantedPathPrefixes = const [],
       grantedReply = (to: to, asSignIn: asSignIn);

  /// Where an allowed [RepliesToOwnConversation] posts and as whom: the
  /// endpoint the docking station recorded for the trajectory, never one
  /// the proposal names, and the sign-in the rules let a reply to it go as.
  /// Null for every other reach, and a reply allowed without one is
  /// refused before anything is sent.
  final ({ReplyEndpoint to, SignIn asSignIn})? grantedReply;

  /// Whom it was allowed by, so the logbook tells "the rules let it
  /// through" from "the person said yes"; null when no rule governs this
  /// reach, such as a read or write bounded only by the file driver's root.
  final DecidedBy? by;

  final List<PathPrefix> grantedPathPrefixes;
}

/// No driver carries the action out, because [why]; its continuation is handed
/// [NothingRan] with that reason.
final class Deny extends Decision {
  const Deny(this.why, {required this.by, super.reliedOn});

  final String why;

  /// Whom it was denied by.
  final DecidedBy by;
}

/// What the airlock decided about an action that would do [reach], on the
/// trajectory named [trajectoryId], at [place] in a turn, before any driver
/// is reached. With no result written after it, the logbook shows the
/// action was cut short.
///
/// [place] is of type [P], which the agent loop supplies, since it knows
/// where in the turn it is, and the airlock writes; nothing here computes
/// one.
final class AirlockDecisionOnAction<P> {
  const AirlockDecisionOnAction(
    this.trajectoryId,
    this.place,
    this.reach,
    this.decision, {
    required this.proposed,
  });

  /// The kind of the logbook entry the airlock keeps it as.
  static const kind = 'airlock-decision-on-action';

  /// [json] read back as [toJson] wrote it, its place read by
  /// [placeFromJson], null for one that is not a place. Each part is
  /// checked as its type's `parse` checks it; throws a [FormatException]
  /// naming the part.
  static AirlockDecisionOnAction<P> fromJson<P>(
    JsonObject json,
    P? Function(Object? json) placeFromJson, [
    String field = 'decided',
  ]) => _at(
    field,
    () => AirlockDecisionOnAction(
      TrajectoryId.parse(json.string('trajectory')) ??
          (throw FormatException('$field.trajectory: not a trajectory')),
      placeFromJson(json.raw('place')) ??
          (throw FormatException('$field.place: not a place')),
      _reachFromJson(json.object('reach'), '$field.reach'),
      _decisionFromJson(json.object('decision'), '$field.decision'),
      proposed: _proposedFromJson(json, field),
    ),
  );

  /// This decision as the logbook holds it, for every reach, its place
  /// written by [placeToJson]. The reach is the program and input that
  /// make it, as a proposal writes them.
  Object? toJson(Object? Function(P place) placeToJson) => {
    'trajectory': trajectoryId.hex,
    'place': placeToJson(place),
    'reach': _reachToJson(reach),
    'decision': _decisionToJson(decision),
    'proposed': proposed.hex,
  };

  final TrajectoryId trajectoryId;
  final P place;
  final Reach reach;
  final Decision decision;

  /// The [ActionProposedByAgentLoop] logbook entry that asked for the
  /// action.
  final EntryId proposed;
}
