# Changelog

## 0.3.0

Breaking.

- `JourneyPathId` is `is_shapes`'s: a journey path is named by the hash of
  the record entry that started it, which the host writes
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

- Every entry is at a host-supplied place `P` in a turn:
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
  (as `Answer`, `answeredBy`, `Reply` and `execResultOutput`), so a host can
  take this up before its tools move to `is_tools_api` 0.2.
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
