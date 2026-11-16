# Changelog

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
- `Apex.through(link, journeyPath:, token:, place:)`: an apex in the agent
  loop that proposes each run's program and input over an `AirlockLink`
  (`propose`) as a `Proposal`, an effect not yet decided, and keeps the
  continuation (Nick, 16 Nov: "Proposal"; only a driver carries an effect
  out). `JourneyPath.at` is unchanged, and `Apex` is now sealed, with the
  two kinds, so a tool does not change.
- `JourneyPath.start(...)` is now the unnamed `JourneyPath(...)`, taking
  the same arguments: it is the airlock service's side of a journey path,
  and the airlock starts nothing; the docking port starts journey paths
  (Nick, 16 Nov).
- `PathToken`, minted with each `JourneyPath` as `JourneyPath.token`: what
  shows a proposal is from that journey path's loop (Nick, 16 Nov: a token
  per path). Compared in constant time, never recorded, hidden by
  `toString`.
- `PathStarted`: loop_launcher, following the docking port's entries that
  start a journey path, tells the airlock service the path has started,
  under its id and rules, and is answered `Ready` with the token for the
  loop it launches, or `Rejected` (Nick, 16 Nov). Sent again after either service restarts: same id,
  new token, with `JourneyPath.reissue` for a path whose side is still
  set up; `stopped` keeps the person's stop across, and nothing un-stops a
  path. `JourneyPath.token` is now a getter.
- `Proposal.read(json)` gives a `Proposal` or `Rejected`;
  `JourneyPath.consider(proposal, place)` gives `Considered` or `Rejected`.
  A rejected request is in no journey path's record; the service records
  it in the airlock's own chain.
- Programs, inputs and outputs travel by is_effects's codecs; a `Post` by
  its own, built on them.
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
