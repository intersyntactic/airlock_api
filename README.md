# is_airlock_api

The airlock's contract. Tools describe actions; the airlock decides each
one and writes its decision to the logbook; drivers operate the world. A tool touches nothing: for
each call it returns a `Result`, which is carried through on a trajectory.

What an action takes and gives back, and the drivers that carry it out, are
`is_effects`'s, so a driver never sees this package. Joining an
`is_tools_api` definition to what a tool does is `is_tool`'s.

```dart
final dart = Executable.parse('dart')!;

/// Writes [file], then formats it.
Result<ExecResult> writeAndFormat(FileText file) => Program.write.runOrRefusal(
  file,
  then: (wrote) =>
      dart.runOrRefusal(Args(['format', file.path.value]), then: Done.new),
);

// In the agent loop, one crux per intent (a tool call in the model's reply);
// `link` writes each proposal to the logbook and waits for the outcome the
// airlock writes back:
final crux = Crux.forIntent(link, turn: turn, intent: intent);
var result = writeAndFormat(file);
while (result is Action<ExecResult>) {
  result = await result.next(crux);
}
```

## A result

- `Result<A>`: what a tool returns for a call, where `A` is its output type.
  `Action` (do this, then hand what happened to the continuation),
  `Done(value)` (the answer), or `Failed(why)` (it couldn't). `Failed` is a
  `Result<Never>`, so one fits every tool. A tool may take several actions,
  with ordinary logic between them; each is decided on its own.
- `result.map(f)`: the same result with its answer, once there is one, given
  to `f`. It reaches no driver: an action's continuation is extended, so
  every action is still decided and written to the logbook at a crux. Turning a tool's
  answer into what the model is told takes no trajectory.

## An action

- `Program`: a closed set, `ReadFile` (`Program.read`), `ReadFileBytes`
  (`Program.readBytes`, a file's exact bytes), `WriteFile`
  (`Program.write`), `Executable` (a `ProgramName`, with plain `Args`),
  `FetchFromWeb` (`Program.fetch`, below), `MakeWebRequests`
  (`Program.makeWebRequests`, below) and `AskTheModel` (`Program.askTheModel`, below). Programs reach
  drivers, so they belong with the drivers and the airlock to what is
  trusted; a new kind of action is a new driver and
  program.
- `Action<A>`: a program, its input and the continuation, all private. Made
  only by its program (`program.run(input, then:)`), so its input is the
  program's own type. Nothing about an action shows outside; when it is
  proposed, what it would do is worked out as its `Reach`, which the
  airlock decides and writes to the logbook: `Reads(path, as:)`, `Writes(file)`,
  `Starts(program, args)`, `FetchesFromWeb(fetch)`,
  `MakesWebRequests(requests)` or `CallsTheModel(call)`. A rule grants a web
  request by origin, sign-in and path together, never the origin alone,
  and a model call by its model sign-in.
- A rule grants `Starts` by the program's name, and the program driver
  runs only the programs its box installed. That bounds what may be asked
  for, not what a program can do once it runs: the wall is the suit, the OS
  user the trajectory wears. A box that offers `sh`, `dart` or `git` has
  given that bound away, since each can run anything the suit can. A
  contained trajectory's box offers single-purpose programs, such as
  `teams-reply-drawing`, which turns a reply's text and recorded
  address into the exact requests to send.

## The web

The airlock knows no chat and no module. The tool on the other side of a
proposal knows how to build what it sends; the airlock decides where it
may go.

- `FetchFromWeb` (proposed as `fetch`) takes a `WebFetch`: an origin, a
  `WebPath`, a sign-in, and what of the response to keep (is_effects's
  `BodyToKeep`: none, text or bytes). It sends a GET with no body and no
  headers, so the only words it carries are in its path, which is decided
  as written; a rule can bound it by prefix. Its reach, `FetchesFromWeb`,
  is its own, so a grant to post to a site is not a grant to fetch from
  it. A proposal carrying a body or headers is rejected, not stripped.
- `MakeWebRequests` (proposed as `make-web-requests`) takes the exact
  `ProposedRequest`s a tool built, such as a reply to the event that started the
  trajectory, as is_effects's codec writes them. One decision holds every
  one, as `MakesWebRequests(requests)`: the airlock grants each request's origin,
  sign-in and path together, all or none, so a reply reaches only the
  conversation the rules name, and the logbook keeps exactly what was
  sent.
  It checks where a body goes, never what it says. A GET is a fetch, a
  header other than `content-type` is refused (a credential is the
  driver's to add), and so is an empty list, all at the boundary. Once
  allowed, they are sent in order; the first that fails stops the rest,
  `Refused('sent k of n: …')`, with no retry.
- An `Allow` for either names the path prefix each request was granted
  under, one per request, and the driver is handed only a `GrantedRequest`
  that carries it, so a redirect on the same site stays under it too. `/`
  grants the whole site. A web action allowed with any other number of
  prefixes, or under one that doesn't cover its path, is refused before a
  driver is reached.

## A model call

The model is outside the station: the case's words leave the machine with
every call, so a model call is an action, the one the loop proposes for
itself rather than drawing from an intent in the model's reply
(https://github.com/enspyrco/intersyntactic/pull/1168, replacing the ruling
that the model is the agent planning and is not decided). The loop holds no
sign-in and has no network; the model driver, holding every model sign-in,
makes the call.

- The loop writes what it will send to the logbook first: each text, the
  system prompt and the request, as `ModelRequestPiece` entries (kind
  `model-request-piece`, `{"text"}`), then a `ModelRequest` (kind
  `model-request`) naming them: `systemPrompt` and `request`, each a
  `TextFromPieces` (its pieces in order and the sha256 of its UTF-8
  bytes), and `builtFrom`, the turns they were drawn from. Pieces are named
  by entry, so the logbook kept each before it is sent; repeated history
  is still stored once, as one object under many entries.
- `AskTheModel` (proposed as `model`) takes a `ModelCall`: the
  `ModelSignInName` it goes as, the `ModelName`, and the `ModelRequest`
  entry. Its reach, `CallsTheModel`, is decided by the sign-in.
- Once allowed, the airlock reads the request and each piece with
  `DecidesActionsAndWritesToTheLogbook.entryOn(trajectory, entry)`, which
  gives an entry only when it belongs to the trajectory: on its own chain,
  or the airlock's result for one of its proposals. So no loop can have
  another's conversation sent. It joins each text and checks its sha256
  (`TextFromPieces.join`), and hands the driver (is_effects's
  `AsksTheModel`) exactly those texts. Anything missing, elsewhere, or not
  joining refuses the call before the driver is reached, each for its own
  reason. The reply streams as `ReplyArriving` in `underway`, never written
  to the logbook; the whole `ModelReply` is the outcome, written once.
- What the logbook proves stops at the driver: the texts it holds are the
  texts the model driver was given. A driver that runs a program (such as
  `claude -p`) sends what that program sends, which may add context of its
  own on the way to the model provider.

## A trajectory

One agent's own line of work in a mission: its id, its rules `R`, and its airlock and
drivers. Its drivers act for the path, each wherever it runs.
Every entry written for it is at a place `P` in a turn, which the agent
loop supplies and the airlock writes; nothing here computes one.

- `Trajectory(id:, drivers:, airlock:, rules:, suit:)`: the
  airlock service's side of a trajectory, set up when the logbook shows
  the docking station started the path (its rules, in `admitted`) and
  loop_launcher handed it users (`assigned`). The airlock starts nothing.
  Holding the drivers
  is already the power to touch the world, so setting up a side grants
  nothing new.
- A `Crux`: where the agent loop, the one holder that extends the
  trajectory, proposes its next action for the airlock to decide
  (https://github.com/enspyrco/intersyntactic/pull/1168). Whatever comes
  after a tool's result takes a `Crux` and never handles `P`. Two agents
  on one machine have two cruxes; one step's two tool calls go through one
  turn's crux, at two places.
- `TrajectoryId`, from `is_shapes`: a trajectory is named by the hash of
  the logbook entry that started it (`TrajectoryId.of(entryBytes)`), which
  the docking station writes, the way a `MissionId` names a mission. So no two
  trajectories share an id, after a restart too, and nothing here mints
  one. Every entry names it.
- `action.next(crux)`, the only way an action reaches the world: it is
  proposed at the crux, and the airlock decides it; the airlock writes the
  decision (`AirlockDecisionOnAction`) to the logbook and only then is a
  driver reached; the airlock writes the action's result, or why it was
  refused, and only then does the continuation see it. An entry that
  cannot be written ends the call. A decision with no result after it is
  an action cut short. Kept means it survives the logbook service
  crashing, not a power cut
  (https://github.com/intersyntactic/logbook/pull/12).
- `AirlockDecisionOnAction.toJson` / `fromJson`: a decision of every reach
  as the logbook holds it (`airlock-decision-on-action`), its reach written
  as the program and input that make it, as a proposal writes them, so a
  `MakesWebRequests` keeps its exact requests and the airlock can read back
  which places it decided and what it let out.
- A `Decision` is `Allow` or `Deny(why)`, each saying who made it,
  `DecidedBy.rules` or `DecidedBy.person`; a stopped trajectory's refusal
  is the person's. `reliedOn` names the logbook entries the airlock read
  to decide beyond the rules, such as the lease of the bot the trajectory
  may post as.
- `stop()`: refuses every action on this trajectory whose driver has not
  yet been reached. An action whose driver has been reached is not
  interrupted.
- `decisions`: each decision once the logbook has kept it. `results`: each
  result, with the decision it follows, once kept. `underway`: what
  drivers report while an action is underway, for a live view, and never
  written to the logbook. Each names its trajectory and place.
- `DecidesActionsAndWritesToTheLogbook<R, P>`: `decide`, given the
  trajectory and an action's `Reach`, so the airlock can read what holds
  for that trajectory now, then `writeDecision(decision)` and
  `writeResult(decision, result, resultAsJson:)`; and `entryOn`, for
  `AskTheModel`; implemented by
  intersyntactic's airlock. An interface is
  named for what it can do, so `implements` reads as a true sentence
  (https://github.com/enspyrco/intersyntactic/pull/1164).

## Between the agent loop and the airlock

The agent loop and the airlock are separate services, and the logbook is
the only channel between them: the airlock has no door of its own
(https://github.com/enspyrco/intersyntactic/pull/1156). An action's
continuation is the tool's own code, so it stays in the loop; its program
and input go into the logbook as an `ActionProposedByAgentLoop`, an action
not yet decided,
and what came back returns through the logbook
(https://github.com/enspyrco/intersyntactic/pull/1157). The airlock decides
and writes to the logbook, and only a driver carries an action out.

- A crux is made only in the agent loop; the airlock service has none, and
  decides only what it reads from the logbook with `Trajectory.consider`.
  `Crux.forIntent(link, turn:, intent:)`, one per tool call in the model's
  reply, proposes each action of that tool at the intent's next action,
  from 0, so two tools running at once never take each other's places.
  `Crux.forTheModelCall(link, turn:)` carries the turn's one model call,
  and refuses a second action with a `StateError` before writing it.
  `Crux.forTheReply(link, turn:)` numbers the actions of the reply the loop
  makes from the turn's final text, such as running the program that
  builds the message and then sending what it built. A restarted loop
  gives each action the same place again. `link`, which
  `ProposesActionsThroughTheLogbook`, is the transport, which this package
  does not have: `writeProposal(body)` writes an
  `action-proposed-by-agent-loop` logbook entry on the loop's trajectory's
  chain and gives back the id the logbook gave it, and
  `outcomeNaming(id)` waits for the `outcome-of-proposed-action` logbook
  entry that names it, which loop_launcher hands the loop. This package
  joins the two and refuses an outcome naming another proposal, so a loop
  never works out an id.
- `PlaceInTrajectory`, sealed: in a turn (one model call and what it
  caused), `ProposedForTheModelCall(turn)`, written `[turn, "model-call"]`;
  `ProposedForAnIntent(turn, intent, action)`, written
  `[turn, intent, action]`; or `ProposedForTheReply(turn, action)`, written
  `[turn, "reply", action]`, in that order within a turn. `parse` gives null for anything
  else, 0.14's `[turn, step]` among them, and a proposal without one is
  `Rejected('not a place')`.
- An `ActionProposedByAgentLoop` (kind `action-proposed-by-agent-loop`)
  names no trajectory. The logbook service
  takes the entries on a path's chain only from that path's loop user, so
  the airlock takes the path from the chain the entry is on, and a loop has
  no claim to make about another path.
- `ActionProposedByAgentLoop.read(json)` gives an
  `ActionProposedByAgentLoop` or `Rejected(why)`, checking every part as
  its type's own `parse` does, with is_effects's codecs.
  `trajectory.consider(proposal, place, proposed: entryId)` decides it,
  writes the decision to the logbook, and carries it out if allowed; its
  decision and its result both name the proposal.
- A result (kind `outcome-of-proposed-action`, body
  `{"proposed": <hex>, "result": <outcome>}`): what came back from a
  proposed action, in full, as the program's codec writes it, or why it was
  refused. It is the one copy of what an action returned: a read's text, a
  program's output, a site's answer, a model's reply. The airlock writes it
  on the decision's chain, never the path's, which only the loop user
  writes. `outcomeOfProposedActionToJson(proposed, resultAsJson)` writes
  one, `proposalRejectedToJson(proposed, why)` answers a proposal that was
  `Rejected`, so its loop is answered and no other path is stalled, and
  `readOutcomeOfProposedAction(json)` reads one back as
  `(proposed:, result:)`, or null when it is not one.
- `WaitingToStart` (kind `waiting-to-start`, `{"trajectory": <hex>}`,
  read strictly): loop_launcher writes it once, on a chain of its own,
  when a path that has no `assigned` entry yet has to wait for room. Its
  `assigned` ends the wait. Why it waits goes to the operator only, so the
  entry carries no reason.
- `LoopUser` (`loop-<n>`) and `Suit` (`suit-<n>`): the OS users
  loop_launcher hands each path from pools infra makes ahead of time, and
  writes in the path's `assigned` entry. The path's loop runs as its loop
  user, and its programs run as its suit, the identity the path wears,
  contained or open (https://github.com/enspyrco/intersyntactic/pull/1158):
  the airlock service gives the path a program driver that runs as it.
- An answer the loop cannot read as an outcome throws a `FormatException`
  and ends the call: whether the action reached the world is then known only
  to the airlock's entries in the logbook.
- Progress (`underway`) stays in the airlock service; anyone who
  subscribes to the logbook sees the entries.

A trajectory is not narrowed from another. For one agent to do less than
another in the same mission (a reviewer that reads while the others write,
https://github.com/enspyrco/intersyntactic/issues/1049), the plan is that
it would be started with fewer rules, its starting entry naming its parent
and its rules, so the airlock could check they are no wider. It would still
be named by that entry's hash: a child names its parent, the way a git
commit does, never the other way round. None of that is built: today the
docking station gives a trajectory whatever rules it likes.

## What the contract does not promise

An airlock guards the drivers it is given, not the mission. An agent
that joins a mission with its own drivers and its own airlock, or none, is
outside it. So "every action through these drivers is in the logbook"
holds, and "every action in the mission is in the logbook" is not this
package's to promise;
the mission's rules bound our trajectories, not anyone else's.

The library imports `is_effects`, `is_shapes` and `is_content_id` and
nothing else outside the SDK; a test reads every directive's URI from Dart's parse tree and
holds it to that.
