/// The airlock's contract: what a tool returns for a call, the programs its
/// actions run, what each would do to the world ([Reach]), what the airlock
/// decided ([AirlockDecisionOnAction]), and how proposals and their outcomes
/// are written in the logbook.
///
/// Types and their JSON only. Proposing an action is the agent loop's,
/// through [ProposesActions]; deciding and carrying one out is the
/// airlock's (`is_airlock`), through [CarriesOutEachProgram]. Writing the
/// web requests that post a reply is a module's, through
/// [WritesReplyRequests] and [WritesPinnedBodyReplyRequests]. What an action
/// takes and gives back, and the drivers that carry it out, are each
/// action's own vocabulary's (files, programs, web requests, the model);
/// joining an `is_tools_api` definition to what a tool does
/// is `is_tool`'s.
library;

export 'package:checked_json/checked_json.dart'
    show JsonFieldException, JsonObject;
export 'package:is_content_id/is_content_id.dart' show ObjectId;
export 'package:is_shapes/is_shapes.dart' show DecidedBy, EntryId, TrajectoryId;

export 'src/action.dart';
