# Changelog

## 0.1.0

- First release: `Result` (`Run`, `Done`, `Failed`), `Program` with
  `ReadFile`, `WriteFile` and `Executable`, `Outcome` (`Ran`, `Refused`),
  `Home` and its `FileDriver` and `ProgramDriver`, `ExecResult`.
- `Airlock`, `Decision` (`Allow`, `Deny`) and `Cleared`: `Run.next` is the
  one way to carry out a run, and it asks the airlock first and has it
  record the outcome.
- `Tool` and `answeredBy`: a tool's code attached to its `is_tools_api`
  definition.
