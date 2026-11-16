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
- `LoopUser` (`loop-<n>`) and `JourneyUser` (`journey-<n>`), moved here
  from loop_launcher so both services read one type: the OS users
  loop_launcher hands each path from pools made ahead of time and records
  in the path's `assigned` entry. A path's loop runs as its loop user and
  its programs as its journey user (Nick, 16 Nov). `JourneyPath` takes
  `journeyUser`.
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
