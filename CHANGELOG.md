# Changelog

## 0.9.0

Breaking. Every name says what the thing is, and the airlock's two writes
are two methods.

- `Proposal` is `ActionProposedByAgentLoop`, kind
  `action-proposed-by-agent-loop` (was `proposed`). Same body.
- `Decided<P>` is `AirlockDecisionOnAction<P>`, with
  `AirlockDecisionOnAction.kind` = `airlock-decision-on-action` for the
  logbook entry the airlock keeps it as. It no longer extends anything.
- `DecidedWebRequest` is `AirlockDecisionOnWebRequest`, kind
  `airlock-decision-on-web-request` (was `web-request-decided`). It
  carries the request's exact body, no renderer, and now `proposed`, the
  proposal it answers, so no two decisions start byte-identical chains:
  the logbook service refuses a repeated chain start once it names entries
  by the hash of their text.
- The renderer is gone: `Renderer`, `RendererName`, `Rendered` (kind
  `rendered`), `DecidesAndRecordsActions.renderer` and `.rendered`, and
  the `RendererId` export. A `WebRequest` carries its exact `body`, the
  `Projection` it is drawn by, and `drawnFrom`, the recorded entry it is
  drawn from, in place of a renderer's name and entries. Once allowed, the
  airlock reads `drawnFrom` through `recordedOn`, draws the body by the
  projection, and reaches the web driver only when it is byte-identical
  to `body`. One projection: `teamsMessageFromModelReply`
  (`teams-message-from-model-reply`), a Teams message whose text is a
  model's reply. A web request's chain is its decision, then its result.
- `DecidesAndRecordsActions.recordedOn` gives `({kind, body})`, the body
  after its header, of an entry that belongs to the trajectory: on its own
  chain, or a `result-of-action-or-why-refused` the airlock kept for one of
  its proposals. Each reader checks the kind it expects, since a loop may
  write a body of any shape under its own kinds: a web request draws only
  from a `result-of-action-or-why-refused`, and a model call reads only a
  `model-request` and its `model-request-piece`s.
- `Entry<P>`, `Returned<P>` and `ReturnedProposal` are gone.
  `DecidesAndRecordsActions.record(entry)` is
  `recordDecision(decision)` and `recordResult(decision, result,
  resultAsJson:)`; a result is handed the decision it follows, so a web
  request's result names its decision as its previous without a lookup.
  `Trajectory.entries` is `decisions` and `results`, the latter
  `({decision, result})`.
- A proposal's answer is the logbook kind
  `result-of-action-or-why-refused` (was `returned`), body
  `{"proposed": <hex>, "result": <outcome>}` (the `outcome` key is now
  `result`), written by `resultOfActionOrWhyRefusedToJson` and
  `proposalRejectedToJson` and read by `readResultOfActionOrWhyRefused`,
  which gives `(proposed:, result:)` or null when the body is not one.
- Docs: the journal is the logbook (is_logbook, run on the box by the
  logbook service), and links and `Logbook.builtDefine` point at
  https://github.com/intersyntactic/logbook. A web request's chain is
  written out in full: the decision starts it, since the proposal's chain
  is its loop user's alone. A model call goes out as a sign-in the rules
  let it go out as; the loop holds none.

## 0.8.0

The model call is an action (Nick, 17 Nov 20:12: "shit so the model call
should really go through the airlock hey?", 20:16: "we do it tonight";
https://github.com/enspyrco/intersyntactic/pull/1168, replacing the
12 Nov ruling that the model is the agent planning). Breaking.

- `AskTheModel` (`Program.askTheModel`, proposed as `model`): a
  `ModelCall` of a `ModelSignInName`, a `ModelName` and the `ModelRequest`
  entry, answered by a `ModelReply`. Its reach is `CallsTheModel`. The one
  action the loop proposes for itself.
- `ModelRequest` (kind `model-request`) and `ModelRequestPiece` (kind
  `model-request-piece`): what a step sends, recorded before it is sent,
  its `systemPrompt` and `request` each a `RecordedText` of piece entries
  and a sha256, with `join`.
- `DecidesAndRecordsActions.recordedOn(trajectory, entry)`, new and
  required: an entry's content, only from that trajectory's own chain.
  `AskTheModel` reads its request and pieces through it, joins and checks
  each text, and hands is_effects's `AsksTheModel` driver exactly those.
- The reply streams as is_effects's `ReplyArriving` in `underway`, never
  recorded. Depends on is_effects ^0.7.0.

## 0.7.1

- Takes is_effects `>=0.6.0 <0.8.0`, not `^0.6.0`. is_flight_rules 0.1.0
  needs is_effects 0.7.0, and below 1.0 `^0.6.0` excludes it, so nothing
  could depend on both (loop-launcher-5b found it). is_effects 0.7.0 only
  adds to what this package uses: its new `Progress` case,
  `ReplyArriving`, is never switched over here. Built and tested against
  0.7.0.

## 0.7.0

Breaking. "Send" is retired (Nick, 17 Nov 13:31: no tiny words for
complex things), and an interface is named for what it can do, so
`implements` reads as a true sentence (Nick, 17 Nov 13:55: "\"What it can
do\", yes naming rule";
https://github.com/enspyrco/intersyntactic/pull/1164). A journey is now a
mission, and a journey path a trajectory (Nick, 17 Nov 19:07 and 19:09;
19:15: "Rename tonight, before any real write").

- `JourneyPath<R, P>` is `Trajectory<R, P>`, and `JourneyPathId` is
  is_shapes 0.5.0's `TrajectoryId` (it hashes as before). Every
  `journeyPath` field is `trajectory`, on the wire too: `WaitingToStart`
  is `{"trajectory": <hex>}`, and `DecidedWebRequest` writes `trajectory`.
  Depends on is_shapes ^0.5.0.
- `Apex` is `Crux` (Nick, 17 Nov 20:17: "CRUX! That's what I was thinking
  of when I said 'apex'"): a trajectory's crux is its agent loop, the one
  holder that extends it (https://github.com/enspyrco/intersyntactic/pull/1168).
  `Trajectory.at(place)` and `Crux.through(link, place:)` give it at one
  place; one step's tool calls go through the one crux at their places.
- `Airlock<R, P>` is `DecidesAndRecordsActions<R, P>`, and `RecordLink` is
  `ProposesActionsThroughTheRecord`. The airlock and its drivers are still
  called that: only the interfaces are renamed, since a noun is kept for
  a thing that exists. No alias is kept.
- Depends on is_effects ^0.6.0, whose 0.4.0 renamed its driver interfaces
  the same way and whose 0.5.0 renamed one again: `Driver` is
  `CarriesOutActions`, `FileDriver` is `ReadsAndWritesFiles`,
  `ProgramDriver` is `RunsPrograms` (its `start` is `runProgram`), and
  `WebDriver` is `CarriesOutWebRequests`. So `JourneyPath(drivers:)`
  takes `Iterable<CarriesOutActions>`. 0.6.0 renamed codecs this package
  does not call.

- `Send` is `WebRequest` (Nick, 16 Nov 18:46), `WebSend` is
  `MakeWebRequest`, and `Sends` is `MakesWebRequest`, whose field `send` is
  `request`. These read with the other programs and reaches (`ReadFile`,
  `Reads`).
- `DecidedSend` is `DecidedWebRequest`, kind `web-request-decided`, with
  the JSON key `request` in place of `send`. No entry was ever written with
  the old kind. `send_entries.dart` is `web_request_entries.dart`.
- is_effects 0.3.0 made the same change:
  `WebDriver.send` is `carryOutWebRequest`, and `Sent` is
  `WebRequestOutcome`, so `MakeWebRequest` gives a `WebRequestOutcome`.
  "Renderer" is not decided and is unchanged.

## 0.6.0

Breaking.

- `Run` is now `Action`, and the library's file `run.dart` is `action.dart`
  (Nick, 17 Nov: "we retired 'run' did we not?", then "So it goes Turn ->
  Step -> Tool Call -> Action" and "'The airlock sits between intents and
  action' just sounds so good"). An action is one round trip to the world,
  which the airlock decides, with exactly one `Outcome`. The verb stays:
  `Program.run(input, then:)` and `runOrRefusal` still run a program, and
  a loop still runs as its user.
- `Held` (kind `held`) is now `WaitingToStart` (kind `waiting-to-start`),
  named for what happens: the path has started and its work has not
  begun (Nick, 17 Nov: "waiting-to-start"; a traveller does not know what
  a loop is or what held means). `Held` shipped in 0.5.0 but was missing
  from its changelog. No entry was ever written with the old kind.
- Docs: "follow" is retired (https://github.com/enspyrco/intersyntactic/pull/1155).
  A reader subscribes to the record, an entry names its previous, and a
  tool's result is run through at an apex. No API changes.

## 0.5.0

Breaking. The agent loop and the airlock in separate processes (RULINGS,
"No server"), and the renderer following the journal instead of being run
by the airlock
(https://github.com/enspyrco/intersyntactic/issues/1147#issuecomment-6905923566).

- The airlock never talks to a renderer. `Renderers` is gone, and with it
  `JourneyPath.start(renderers:)`. `Airlock` gains `renderer(name)`, which
  resolves a name for the `Decided` entry as `Renderers.find` did, and
  `rendered(decided)`: the body the renderer recorded after that `Decided`,
  which the airlock follows the journal to, or why there is none. It is
  called only once `Decided` is kept, and what it gives is what is sent,
  so the exact bytes sent are in the record. The check that a renderer was
  built from the source its id names moves to the entry it records.
- A proposal is an entry in the record, and the airlock has no door of its
  own (Nick, 16 Nov, https://github.com/enspyrco/intersyntactic/pull/1156).
  `Apex.through(link, place:)`: an apex in the agent loop that proposes each
  run's program and input over a `RecordLink` as a `Proposal` (kind
  `proposed`), an effect not yet decided, on the loop's journey path's
  chain, and keeps the continuation. `JourneyPath.at` is unchanged, and
  `Apex` is now sealed, with the two kinds, so a tool does not change.
- A `Proposal` names no journey path: the journal takes a path's chain only
  from its loop user, so the airlock takes the path from the chain.
  `Proposal.read(json)` gives a `Proposal` or `Rejected`;
  `JourneyPath.consider(proposal, place, proposed:)` decides and records
  it, and `Decided` and `Returned` gain `proposed`, the entry that asked.
- What an effect returns is in the record, once (Nick, 16 Nov,
  https://github.com/enspyrco/intersyntactic/pull/1157): `ReturnedProposal`
  (kind `returned`) holds what came back in full, by the program's codec,
  or the refusal, naming the `proposed` entry; loop_launcher hands it to
  the path's loop. `ReturnedProposal.refused` answers a `Rejected` entry.
  `Returned`'s constructor is private, since only a journey path knows the
  program's codec.
- `JourneyPath.start(...)` is now the unnamed `JourneyPath(...)`, taking
  the same arguments: it is the airlock service's side of a journey path,
  and the airlock starts nothing; the docking station starts journey paths
  (Nick, 16 Nov).
- `LoopUser` (`loop-<n>`) and `Suit` (`suit-<n>`), moved here from
  loop_launcher so both services read one type: the OS users loop_launcher
  hands each path from pools made ahead of time and records in the path's
  `assigned` entry. A path's loop runs as its loop user and its programs as
  its suit, one per path, contained or open (Nick, 16 Nov: "suit";
  https://github.com/enspyrco/intersyntactic/pull/1158). `JourneyPath`
  takes `suit`.
- loop_launcher records itself (Nick, 16 Nov, 19:22), so the airlock
  service learns each path from the record: the path-start message
  (`PathStarted`, `Ready`), the path token and `JourneyPath.reissue`,
  briefly on main, never shipped.
- `Post` is now `Send`, and `WebPost` is `WebSend`; `Sends` holds `send`
  where it held `post` (Nick, 16 Nov: "post" is ambiguous, beside the HTTP
  method `Method.post` and a chat's posts). So the family reads `Send`,
  `Sends`, and is_effects's `Sent`.
- Programs, inputs and outputs travel by is_effects's codecs; a `Send` by
  its own, built on them.
- One send's chain in the journal has wire forms: `DecidedSend` (kind
  `send-decided`: journey path, place, the whole `Send`, the exact
  `Renderer` or none, and the decision), which a renderer follows the
  journal for and reads, and `Rendered` (kind `rendered`: the `EntryId` of
  the `DecidedSend` it follows, the renderer's source id as it reports it,
  and the body or why there is none), which the renderer writes and the
  airlock reads. `Returned` follows `Rendered`, or follows the
  `DecidedSend` directly when the renderer did not answer in time. Only a
  send's entries have a wire form: other runs' entries still record what a
  run reached and why, never a file's text or a program's output.
- Depends on `is_effects` ^0.2.1, for its codecs.

## 0.4.0

Breaking. The post design decided in
https://github.com/enspyrco/intersyntactic/issues/1147: everything a post
says is drawn from recorded journal entries, by a renderer the record names
exactly.

- `Program.web` is a `WebPost`, a `Program<Post, Sent>`, in place of
  `WebRequest`, a `Program<Request, Sent>`. A `Post` has an origin, method,
  `WebPath`, sign-in, headers (checked by is_effects's `validatedHeaders`),
  a `RendererName` and the `EntryId`s of the recorded entries its words are
  drawn from. It has no body, so a tool cannot put words in.
- `Renderers`, which the service that starts journey paths implements and
  passes to `JourneyPath.start(renderers:)`: `find` resolves a
  `RendererName` to an exact `Renderer` (its `RendererId` and the `ObjectId`
  of the executable run); `render` reads and checks each entry and runs the
  renderer, giving the body or why there is none. A render is refused
  when the executable reports being built from source other than the
  renderer's id, which rules out a stale or mis-built executable, not one
  built to lie.
- A post's renderer is resolved before the decision, and `Sends` holds the
  whole `Post` and that `Renderer`, so the `Decided` entry records which
  code will write the words. A name that resolves to nothing, or a journey
  path with no `Renderers`, is denied before the rules are asked. The body
  is drawn only once `Decided` is kept, and a render that is refused (an
  entry the journal does not hold, say) refuses the post with nothing sent.
- `Airlock.decide` takes the `Reach`, not the `Run`, and `Decided`,
  `Returned` and `Underway` hold the `reach` in place of the `run`. The
  public `Run.reach` is gone: a post's reach needs its renderer resolved.
- `Airlock.record`'s doc says what kept means: it survives the journal
  crashing or being killed, not a power cut
  (https://github.com/intersyntactic/journal/pull/12).
- Re-exports `EntryId` and `RendererId` from `is_shapes`, and `ObjectId`
  from `is_content_id`.
- Depends on `is_effects` ^0.2.0, `is_shapes` ^0.4.4 and `is_content_id`
  ^0.2.0.

## 0.3.1

- `DecidedBy` is `is_shapes`'s, re-exported, so the airlock and the docking
  port record who decided with one type. The values and their order are
  unchanged (`rules`, `person`), and so is `Decision.by`. Code written
  against 0.3.0 compiles as it was; code importing both packages now sees
  one `DecidedBy`, not two that clash.
- Depends on `is_shapes` ^0.4.3.

## 0.3.0

Breaking.

- `JourneyPathId` is `is_shapes`'s: a journey path is named by the hash of
  the record entry that started it, which whoever starts it writes
  (`JourneyPathId.of(entryBytes)`), the way a `JourneyId` names a journey.
  This package's own `JourneyPathId`, whose `parse` took any non-blank
  string, is gone, and it re-exports `is_shapes`'s.
- Narrowing is removed: `JourneyPath.narrowed`, the `Narrowed` entry and
  `Airlock.narrows`. A `Narrowed` entry went into the parent's record and
  named the child, so the child's id had to exist before the entry that
  would name it, and could not be its hash. Nothing narrowed. With it go
  stopping a child when its parent stops, and entries and progress
  reaching a parent's streams.
- `Entry<R, P>` is `Entry<P>` again, with `Decided<P>` and `Returned<P>`:
  only `Narrowed` held rules.
- Depends on `is_shapes` as well as `is_effects`.

## 0.2.0

Breaking.

Added to this entry with 0.3.0: the 0.2.0 release also made these changes,
which its own changelog left out.

- Every entry is at a place `P` in a turn, which the agent loop supplies:
  `JourneyPath<R, P>`, `Airlock<R, P>`, and a `place` on each entry and on
  `Underway`.
- `journeyPath.at(place)` gives an `Apex`, and a run is carried out with
  `run.next(apex)`.
- `Entry<R, P>`, so a switch over the kinds of entry is exhaustive.
- `WebRequest` (`Program.web`) sends an `is_effects` `Request` through a
  `WebDriver`. Its reach is `Sends(origin, signIn)`, which a rule grants
  together and which never holds the body; a null sign-in means none.
- `Result.map`, which gives a result's answer to a function and carries out
  nothing.
- `PathInRepo` is `is_effects`'s `RelativePath`.

The changes it did list:

- The vocabulary of effects and the driver interfaces move to `is_effects`:
  `PathInRepo`, `FileText`, `Args`, `ReadResult`, `Wrote`, `ExecResult`,
  `Outcome`, and `FileDriver` and `ProgramDriver`. A driver depends on
  `is_effects` alone and sees no run, journey path or decision. This package
  depends on `is_effects` and nothing else of ours.
- `Tool`, `answeredBy`, `Reply` and `ExecResult.output` move to `is_tool`
  (as `Answer`, `answeredBy`, `Reply` and `execResultOutput`), so a
  consumer can take this up before its tools move to `is_tools_api` 0.2.
- `Executable` wraps an `is_effects` `ProgramName`, compares by it, and has
  `Executable.parse`; `Starts.program` is the `ProgramName`.
- `Allow` and `Deny` take `by: DecidedBy.rules` or `DecidedBy.person`, so
  the record tells the rules' decision from the person's.
- Drivers report while a run is underway, on `JourneyPath.underway`.
- `Settled` is renamed `Returned`: a run goes out and comes back with its
  outcome, so a run's entries are `Decided`, then `Returned`.

## 0.1.0

- First release: `Result` (`Run`, `Done`, `Failed`), the closed set of
  programs (`ReadFile`, `WriteFile`, `Executable`) and their `Reach`,
  `Outcome` (`Ran`, `Refused`), `FileDriver` and `ProgramDriver`,
  `ExecResult`, and `PathInRepo`.
- `JourneyPath`, `JourneyPathId`, `Airlock`, `Decision` (`Allow`, `Deny`)
  and `Entry` (`Decided`, `Settled`, `Narrowed`): `Run.next` is the one way
  to carry out a run, and each run is decided and recorded before its driver
  is reached, and recorded again before its outcome flows on. Each narrowing
  is recorded, granted or not, before the new journey path exists.
- `Tool`, `answeredBy` and `Reply`: a tool's code attached to its
  `is_tools_api` definition, and a call followed to what the model is told.
