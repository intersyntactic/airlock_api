/// The airlock's contract: what a tool returns for a call, the runs of
/// programs it describes, the journey path each run is carried out on, and
/// the [Airlock] that decides and records each one.
///
/// The airlock itself, which decides and records, is not here: this library
/// holds only the types it and the tools agree on. What an effect takes and
/// gives back, and the drivers that carry it out, are `is_effects`'s; joining
/// an `is_tools_api` definition to what a tool does is `is_tool`'s.
library;

export 'src/run.dart';
