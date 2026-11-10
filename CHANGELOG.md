# Changelog

## 0.1.0

- First release: `Result` (`Run`, `Done`, `Failed`), the closed set of
  programs (`ReadFile`, `WriteFile`, `Executable`) and their `Reach`,
  `Outcome` (`Ran`, `Refused`), `FileDriver` and `ProgramDriver`,
  `ExecResult`, and `PathInRepo`.
- `JourneyPath`, `JourneyPathId`, `Airlock`, `Decision` (`Allow`, `Deny`) and `Entry`
  (`Decided`, `Settled`): `Run.next` is the one way to carry out a run, and
  each run is decided and recorded before its driver is reached, and
  recorded again before its outcome flows on.
- `Tool`, `answeredBy` and `Reply`: a tool's code attached to its
  `is_tools_api` definition, and a call followed to what the model is told.
