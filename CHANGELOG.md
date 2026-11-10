# Changelog

## 0.2.0

Breaking.

- What leaves the home: `SendRequest` (`Program.send`), its `Request` and
  `Response`, the `Sends` reach and `NetworkDriver`. A `Destination` names
  what is on the other end (`ProviderApi` under a named `SignIn`,
  `SelfRunModel`, `Web`), as rules written by direction name it; a sign-in's
  secret is the driver's. `Args.leavesTo` says where a started program will
  send, and the airlock decides on it.
- Depends on no package of ours: `Tool`, `answeredBy`, `Reply` and
  `ExecResult.output` move to `is_tool` (as `Answer`, `answeredBy`, `Reply`
  and `execResultOutput`), so a host can take this up before its tools move
  to `is_tools_api` 0.2.
- `Executable.parse` replaces `Executable(name)`: a blank name, or one with
  whitespace, is null. Executables compare by name.
- `Allow` and `Deny` take `by: DecidedBy.rules` or `DecidedBy.person`, so
  the record tells the rules' decision from the person's.
- Drivers report while a run is underway (`Printed`, `Received`), on
  `JourneyPath.underway`; `ProgramDriver.start` takes a `report`.
- `Args.timeout` and `Args.silenceLimit`, per run.
- `PathInRepo` says that what stays inside the repo is the text, not where a
  symlink points.

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
