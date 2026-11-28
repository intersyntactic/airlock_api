import 'dart:convert';

import 'package:is_web_request_vocabulary/is_web_request_vocabulary.dart';
import 'package:is_shapes/is_shapes.dart' show TrajectoryId;
import 'package:is_sign_in_vocabulary/is_sign_in_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';

final hart = SignIn.parse('hart-bot')!;
final teams = Origin.parse('https://smba.trafficmanager.net')!;
final conversation = WebPath.parse('/v3/conversations/c/activities')!;

TrajectoryId idOf(String startedBy) => TrajectoryId.of(utf8.encode(startedBy));

/// The body of a Teams message saying [text].
String teamsMessageOf(String text) =>
    jsonEncode({'type': 'message', 'text': text});

/// A POST of the Teams message [text] to [conversation] as [hart], as a tool
/// builds one.
ProposedRequest teamsPost(
  String text, {
  Map<String, String> headers = const {'content-type': 'application/json'},
}) => ProposedRequest(
  teams,
  method: Method.post,
  path: conversation,
  signIn: hart,
  headers: headers,
  body: teamsMessageOf(text),
);
