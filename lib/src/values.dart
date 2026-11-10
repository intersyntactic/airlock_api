import 'path_in_repo.dart';

/// What became of a run.
sealed class Outcome<O> {
  const Outcome();
}

/// It ran, and gave [output].
final class Ran<O> extends Outcome<O> {
  const Ran(this.output);

  final O output;
}

/// It did not run: the airlock denied it, the journey path was stopped, its
/// driver refused it, or this machine has no driver for its program. An
/// [Outcome] of every program, since [Never] is a subtype of every type.
final class Refused extends Outcome<Never> {
  const Refused(this.why);

  final String why;
}

/// [text] for the file at [path]. The driver decides whether it may be
/// written; that [path] stays inside the repo is settled by its type.
final class FileText {
  const FileText(this.path, this.text);

  final PathInRepo path;
  final String text;
}

/// What a started program is given.
final class Args {
  const Args(
    this.args, {
    this.stdin,
    this.inFolder = PathInRepo.root,
    this.timeout,
    this.silenceLimit,
    this.leavesTo = const [],
  });

  final List<String> args;

  /// Written to the program's stdin, then closed. Null: stdin is closed at
  /// once.
  final String? stdin;

  /// The folder it runs in.
  final PathInRepo inFolder;

  /// How long it may run before it is killed; null for the driver's own.
  final Duration? timeout;

  /// How long it may print nothing before it is killed; null for the
  /// driver's own.
  final Duration? silenceLimit;

  /// Where it says it will send things out of the home, such as a model's
  /// CLI sending to its provider. The airlock decides on these as it does on
  /// a [Request]'s destination. Where a journey path requires containment,
  /// the journey's OS user is let reach these and no others; elsewhere it is
  /// what the program says, not a limit.
  final List<Destination> leavesTo;
}

/// Where a run sends something out of the home.
///
/// Named by what is on the other end, as a journey path's rules name it,
/// not by a bare address: a provider's API under one of the person's
/// sign-ins, a model the person runs, or the open web.
sealed class Destination {
  const Destination();
}

/// [provider]'s API, under the person's sign-in named [signIn]. The driver
/// holds the provider's address and the sign-in's secret.
final class ProviderApi extends Destination {
  const ProviderApi(this.provider, this.signIn);

  final Provider provider;
  final SignIn signIn;

  @override
  bool operator ==(Object other) =>
      other is ProviderApi &&
      other.provider == provider &&
      other.signIn == signIn;

  @override
  int get hashCode => Object.hash(provider, signIn);
}

/// A model the person runs themselves, reached at [address], with no
/// secret.
final class SelfRunModel extends Destination {
  const SelfRunModel._(this.address);

  /// [raw] as an http(s) address with a host, and no credentials, query or
  /// fragment, or null when it is not one.
  static SelfRunModel? parse(String raw) => switch (_http(raw)) {
    final uri? when !uri.hasQuery => SelfRunModel._(uri),
    _ => null,
  };

  final Uri address;

  @override
  bool operator ==(Object other) =>
      other is SelfRunModel && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// Anywhere else, at the site [origin], under no sign-in.
///
/// The site alone: what is asked of it, path and query, is the [Request]'s.
/// So a rule naming a site covers every request to it by plain `==`.
final class Web extends Destination {
  const Web._(this.origin);

  /// [raw] as an http(s) site, such as `https://graph.microsoft.com`, or
  /// null when it is not one or carries credentials, a path, a query or a
  /// fragment.
  static Web? parse(String raw) => switch (_http(raw)) {
    final uri? when (uri.path.isEmpty || uri.path == '/') && !uri.hasQuery =>
      Web._(Uri(scheme: uri.scheme, host: uri.host, port: uri.port)),
    _ => null,
  };

  final Uri origin;

  @override
  bool operator ==(Object other) => other is Web && other.origin == origin;

  @override
  int get hashCode => origin.hashCode;
}

Uri? _http(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}

/// A service whose API a run can send to, such as `anthropic`.
final class Provider {
  const Provider._(this.id);

  /// [raw] as a provider, or null unless it is lowercase letters, digits,
  /// `-` and `_`.
  static Provider? parse(String raw) =>
      _name.hasMatch(raw) ? Provider._(raw) : null;

  final String id;

  @override
  bool operator ==(Object other) => other is Provider && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

/// One of the person's sign-ins, by name, such as `team-claude-code`. Never
/// the secret: the driver holds that, so it reaches neither a tool nor the
/// record.
final class SignIn {
  const SignIn._(this.name);

  /// [raw] as a sign-in's name, or null unless it is lowercase letters,
  /// digits, `-` and `_`.
  static SignIn? parse(String raw) =>
      _name.hasMatch(raw) ? SignIn._(raw) : null;

  final String name;

  @override
  bool operator ==(Object other) => other is SignIn && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

final _name = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

/// What a [Request] asks of its destination.
enum Method { get, post, put, patch, delete }

/// Something sent out of the home, to [to].
///
/// [path] is appended to the destination's address. [headers] never carry
/// a credential: the sign-in's secret is the driver's to add, so a request
/// naming `authorization`, `proxy-authorization`, `cookie` or `x-api-key`
/// is an [ArgumentError].
final class Request {
  Request(
    this.to, {
    this.method = Method.get,
    this.path = '',
    Map<String, String> headers = const {},
    this.body,
  }) : headers = Map.unmodifiable(headers) {
    for (final name in headers.keys) {
      if (_credentialHeaders.contains(name.toLowerCase())) {
        throw ArgumentError.value(
          name,
          'headers',
          "carries a credential, which is the sign-in's",
        );
      }
    }
  }

  final Destination to;
  final Method method;
  final String path;
  final Map<String, String> headers;

  /// What leaves the home, for the record as well as the destination.
  final String? body;
}

const _credentialHeaders = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'x-api-key',
};

/// What came back from a [Request].
final class Response {
  const Response({
    required this.status,
    this.headers = const {},
    required this.body,
  });

  final int status;
  final Map<String, String> headers;
  final String body;
}

/// What a driver reports while a run is underway, before its outcome.
sealed class Progress {
  const Progress();
}

/// A started program printed [text] on [channel].
final class Printed extends Progress {
  const Printed(this.channel, this.text);

  final Channel channel;
  final String text;
}

enum Channel { stdout, stderr }

/// [text] arrived from a [Request]'s destination, such as a streamed model
/// reply.
final class Received extends Progress {
  const Received(this.text);

  final String text;
}

/// Where a driver reports [Progress] for the run it is carrying out.
typedef Report = void Function(Progress progress);

/// What a read found.
sealed class ReadResult {
  const ReadResult();
}

final class ReadText extends ReadResult {
  const ReadText(this.text);

  final String text;
}

/// No file at the path.
final class ReadMissing extends ReadResult {
  const ReadMissing();
}

/// Written; [replaced] when a file was there before.
final class Wrote {
  const Wrote({required this.replaced});

  final bool replaced;
}

/// What a program did once it started.
///
/// One that never started is [Refused], with its own reason, so there is no
/// refused flag here and [forModel] never has to guess why a command did not
/// run.
final class ExecResult {
  const ExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.silentFor,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  /// Set when the command was killed for printing nothing for this long;
  /// null otherwise.
  final Duration? silentFor;

  /// What the model is told.
  ///
  /// stderr is INCLUDED even on success, and the exit code is always stated.
  /// A command that printed a warning and succeeded, and one that printed the
  /// same text and failed, are different events; a transcript that shows only
  /// stdout makes them identical. Exit 0 is not a measurement.
  String get forModel {
    final b = StringBuffer(switch ((timedOut, silentFor)) {
      (_, final quiet?) =>
        'printed nothing for ${quiet.inSeconds}s and was killed; no exit code',
      (true, null) => 'timed out and was killed; no exit code',
      (false, null) => 'exit $exitCode',
    });
    final anyOut = stdout.trim().isNotEmpty;
    final anyErr = stderr.trim().isNotEmpty;
    if (anyOut) b.write('\n--- stdout ---\n${stdout.trimRight()}');
    if (anyErr) b.write('\n--- stderr ---\n${stderr.trimRight()}');
    if (!anyOut && !anyErr) b.write(' (no output)');
    return b.toString();
  }
}
