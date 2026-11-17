/// The airlock's contract: what a tool returns for a call, the actions it
/// describes, the trajectory each action is proposed on, and what the
/// airlock implements to decide and record each one,
/// [DecidesAndRecordsActions].
///
/// The airlock itself, which decides and records, is not here: this library
/// holds only the types it and the tools agree on. What an action takes and
/// gives back, and the drivers that carry it out, are `is_effects`'s; joining
/// an `is_tools_api` definition to what a tool does is `is_tool`'s.
library;

export 'package:is_content_id/is_content_id.dart' show ObjectId;
export 'package:is_shapes/is_shapes.dart' show DecidedBy, EntryId, TrajectoryId;

export 'src/action.dart';
