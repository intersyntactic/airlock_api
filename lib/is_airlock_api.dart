/// The airlock's contract: what a tool returns for a call, the runs of
/// programs it describes, the journey path each run is carried out on, and
/// the [Airlock] that decides and records each one.
///
/// The airlock itself, which decides and records, is not here: this library
/// holds only the types it, the drivers and the tools agree on. It depends on
/// no package of ours, so a host can take it up before its tools move to
/// `is_tools_api`'s definitions; `is_tool` joins a definition to what a tool
/// does.
library;

export 'src/path_in_repo.dart';
export 'src/run.dart';
export 'src/values.dart';
