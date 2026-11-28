# is_airlock_api

The airlock's contract: types and their JSON, nothing that carries an
action out. Tools describe actions; the agent loop proposes each one
through the logbook; the airlock (`is_airlock`) decides it, writes its
decision to the logbook, and has a driver carry it out.

What an action takes and gives back, and the drivers that carry it out, are
each action's own vocabulary's (files, programs, web requests, the model).
Joining an `is_tools_api` definition to what a tool does is
`is_tool`'s.

```dart
final dart = Executable.parse('dart')!;

/// Writes [file], then formats it.
Result<ExecResult> writeAndFormat(FileText file) => Program.write.runOrFail(
  file,
  then: (wrote) =>
      dart.runOrFail(Args(['format', file.path.value]), then: Done.new),
);

// `proposer` is the agent loop's: it writes each proposal to the logbook
// and waits for the outcome the airlock writes back.
var result = writeAndFormat(file);
while (result is Action<ExecResult>) {
  result = await result.next(proposer);
}
```

## A result

- `Result<A>`: what a tool returns for a call, where `A` is its output type.
  `Action` (do this, then hand what happened to the continuation),
  `Done(value)` (the answer), or `Failed(why)` (it couldn't). `Failed` is a
  `Result<Never>`, so one fits every tool. A tool may take several actions,
  with ordinary logic between them; each is decided on its own.
- `result.map(f)`: the same result with its answer, once there is one, given
  to `f`. It proposes nothing: an action's continuation is extended.
- `action.next(proposer)`: the action proposed through a
  `ProposesActions`, and the result it leads to. `ProposesActions` has one
  method, `propose(program, input)`, giving the action's `Outcome`. The
  agent loop implements it over the logbook; a test can implement it
  directly.

## An action

- `Program`: a closed set, `ReadFile` (`Program.read`), `ReadFileBytes`
  (`Program.readBytes`), `WriteFile` (`Program.write`), `Executable` (a
  `ProgramName`, with plain `Args`), `FetchFromWeb` (`Program.fetch`),
  `MakeWebRequests` (`Program.makeWebRequests`), `AskTheModel`
  (`Program.askTheModel`) and `ReplyToOwnConversation`
  (`Program.replyToOwnConversation`).
- `Action<A>`: a program, its input and the continuation, all private. Made
  only by its program (`program.run(input, then:)`, `program.runOrFail`), so
  its input is the program's own type.
- `program.reachOf(input)`: what the input would do to the world, which the
  airlock decides and the logbook keeps: `Reads(path, as:)`,
  `Writes(file)`, `Starts(program, args)`, `FetchesFromWeb(fetch)`,
  `MakesWebRequests(requests)`, `CallsTheModel(call)` or
  `RepliesToOwnConversation(content)`.
- `CarriesOutEachProgram`: one method per program, each given that
  program's own input type, returning null when the machine cannot run it.
  `program.carriedOutBy(by, input)` calls the program's own method, so
  whoever carries programs out (the airlock, over its drivers) never casts,
  and a new program is a new method there that the compiler asks for.

## The web

- `FetchFromWeb` (proposed as `fetch`) takes a `WebFetch`: an origin, a
  `WebPath`, a sign-in, and what of the response to keep (is_web_request_vocabulary's
  `BodyToKeep`). A proposal carrying a body or headers is rejected, not
  stripped.
- `MakeWebRequests` (proposed as `make-web-requests`) takes the exact
  `ProposedRequest`s a tool built. A GET, a header other than
  `content-type`, an empty list, and a granted prefix named by the tool are
  all rejected when the proposal is read.
- An `Allow` for either names the path prefix each request was granted
  under, one per request. `/` grants the whole site.

## A reply

- `ReplyToOwnConversation` (proposed as `reply-to-own-conversation`) takes
  a `ReplyContent` alone: the model names no conversation and no sign-in.
  Its reach, `RepliesToOwnConversation(content)`, holds the text and footer
  exactly.
- `Allow.toReplyTo(endpoint, asSignIn:)` grants the `ReplyEndpoint` the
  docking station recorded for the trajectory and the sign-in a reply to it
  goes as, kept in the decision entry as `grantedReply`. Its outcome is a
  list of `PostedMessage`s.

## A model call

- The loop writes what it will send to the logbook first: each text as a
  `ModelRequestPiece` entry (kind `model-request-piece`, `{"text"}`), then
  a `ModelRequestFromPieces` (kind `model-request`) naming them:
  `systemPrompt` and `request`, each a `TextFromPieces` (its pieces in
  order and the sha256 of its UTF-8 bytes), and `builtFrom`, the messages they
  were drawn from. `TextFromPieces.join` checks the joined text against its
  hash.
- `AskTheModel` (proposed as `model`) takes a `ModelCallNamingRequestEntry`: the
  `ModelSignInName` it goes as, the `ModelName`, and the
  `ModelRequestFromPieces` entry. Its reach, `CallsTheModel`, is decided by
  the sign-in.

## Decisions

- A `Decision` is `Allow` or `Deny(why)`, each saying who made it
  (`DecidedBy`); `Allow.by` is null when no rule governs the reach.
  `reliedOn` names the logbook entries the airlock read to decide beyond
  the rules.
- `AirlockDecisionOnAction.toJson` / `fromJson`: a decision of every reach
  as the logbook holds it (kind `airlock-decision-on-action`), its reach
  written as the program and input that make it, naming the proposal it
  answers.

## Between the agent loop and the airlock

The logbook is the only channel between them: the airlock has no door of
its own.

- `program.proposal(input, at: place)`: the body of an
  `action-proposed-by-agent-loop` logbook entry. It names no trajectory:
  the airlock takes the path from the chain the entry is on, which only the
  path's loop user writes.
- `ActionProposedByAgentLoop.read(body)` gives an
  `ActionProposedByAgentLoop` or `Rejected(why)`, checking every part as
  its type's own `parse` does. `proposal.open(<I, O>(program, input) => …)`
  hands back the program and its input with their types matched.
- `PlaceInTrajectory`, sealed: `ProposedForTheModelCall(step)`, written
  `[step, "model-call"]`; `ProposedForAnIntent(step, intent, action)`,
  written `[step, intent, action]`; or `ProposedForTheReply(step, action)`,
  written `[step, "reply", action]`, in that order within a step. A step is
  one model call and what it caused, counted across the trajectory. `parse`
  gives null for anything else.
- A result (kind `outcome-of-proposed-action`, body
  `{"proposed": <hex>, "result": <outcome>}`): `program.outcomeToJson`
  writes the outcome and `program.outcomeFromJson` reads it back;
  `outcomeOfProposedActionToJson(proposed, resultAsJson)` writes the body,
  `proposalRejectedToJson(proposed, why)` answers a `Rejected` proposal,
  and `readOutcomeOfProposedAction(body)` reads one back as
  `(proposed:, result:)`, or null.
- `WaitingToStart` (kind `waiting-to-start`, `{"trajectory": <hex>}`):
  loop_launcher writes it once, on a chain of its own, when a path with no
  `assigned` entry yet has to wait for room.
- `LoopUser` (`loop-<n>`) and `Suit` (`suit-<n>`): the OS users
  loop_launcher hands each path, written in its `assigned` entry.

## What this package holds

Types and their JSON. Two tests hold it there: one reads every directive's
URI from Dart's parse tree and allows only the vocabularies; the other finds every `async` function body in `lib` and
allows none, since waiting on something is carrying an action out.
