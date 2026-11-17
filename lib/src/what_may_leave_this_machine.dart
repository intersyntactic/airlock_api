part of 'action.dart';

// A journey path's rules say what may leave this machine, to where, and as
// which sign-in, never whether an action reads or writes
// (https://github.com/enspyrco/intersyntactic/pull/1163). Nick picked the
// names on 17 Nov, 18:42: "WhatMayLeaveThisMachine", "noNetworkOfTheirOwn /
// sharesThisMachinesNetwork", "is_airlock_api beside Suit". Here, beside
// Suit, since all three readers depend on this package: the docking station
// writes it into `admitted`, the airlock decides a web request against it,
// and loop_launcher gives the loop its model sign-ins and the suit its
// network from it.

/// A journey path's rules: every way words can get off this machine, and
/// what each may carry where.
///
/// Files and programs on the machine need no rule: [Reads], [Writes] and
/// [Starts] carry nothing off it by themselves. A program can leave only
/// through its own network, which [programsNetwork] decides. A model call
/// or a web request only reads, yet carries the case's words away, so each
/// is named here.
final class WhatMayLeaveThisMachine {
  WhatMayLeaveThisMachine({
    required Iterable<ModelSignInName> modelSignInsTheLoopIsGiven,
    required Iterable<SiteAndSignIn> sitesTheWebDriverMayReach,
    required this.programsNetwork,
  }) : modelSignInsTheLoopIsGiven = Set.unmodifiable(
         modelSignInsTheLoopIsGiven,
       ),
       sitesTheWebDriverMayReach = Set.unmodifiable(sitesTheWebDriverMayReach);

  /// [json] read back, strictly: a key it does not know, or a part that is
  /// not what it names, throws a [FormatException] naming the part. A key
  /// it does not know is never skipped, since a reader that skipped one
  /// would skip whatever it restricts.
  static WhatMayLeaveThisMachine fromJson(
    JsonObject json, [
    String field = 'whatMayLeaveThisMachine',
  ]) {
    _exactly(field, json, const {
      'modelSignInsTheLoopIsGiven',
      'sitesTheWebDriverMayReach',
      'programsNetwork',
    });
    return WhatMayLeaveThisMachine(
      modelSignInsTheLoopIsGiven: [
        for (final (i, name)
            in json.strings('modelSignInsTheLoopIsGiven').indexed)
          ModelSignInName.parse(name) ??
              (throw FormatException(
                '$field.modelSignInsTheLoopIsGiven[$i]: not a model sign-in',
              )),
      ],
      sitesTheWebDriverMayReach: [
        for (final (i, site)
            in json.objects('sitesTheWebDriverMayReach').indexed)
          SiteAndSignIn.fromJson(site, '$field.sitesTheWebDriverMayReach[$i]'),
      ],
      programsNetwork:
          ProgramsNetwork.values.asNameMap()[json.string('programsNetwork')] ??
          (throw FormatException(
            '$field.programsNetwork: not one of '
            '${ProgramsNetwork.values.map((v) => v.name).join(', ')}',
          )),
    );
  }

  /// The model sign-ins the path's agent loop is built with, by name;
  /// loop_launcher maps each name to the credential it holds.
  final Set<ModelSignInName> modelSignInsTheLoopIsGiven;

  /// Each site the web driver may make a request to for this path, with
  /// the sign-in it goes as.
  final Set<SiteAndSignIn> sitesTheWebDriverMayReach;

  final ProgramsNetwork programsNetwork;

  /// Whether [reach] goes to a site, as a sign-in, that
  /// [sitesTheWebDriverMayReach] names together. A request under no sign-in
  /// matches only a [GoesAsNobody] grant, and one under a sign-in only a
  /// grant of that sign-in, so a grant to fetch a page anonymously never
  /// lets the path make requests there as a bot.
  bool allowsWebRequest(MakesWebRequest reach) =>
      sitesTheWebDriverMayReach.contains(
        SiteAndSignIn(reach.origin, switch (reach.signIn) {
          final signIn? => GoesAsSignIn(signIn),
          null => const GoesAsNobody(),
        }),
      );

  Object? toJson() => {
    'modelSignInsTheLoopIsGiven': [
      for (final name in modelSignInsTheLoopIsGiven) name.value,
    ],
    'sitesTheWebDriverMayReach': [
      for (final site in sitesTheWebDriverMayReach) site.toJson(),
    ],
    'programsNetwork': programsNetwork.name,
  };
}

/// Whether a path's programs can reach a network themselves.
enum ProgramsNetwork {
  /// The suit has no network of its own: a program reaches nothing off
  /// this machine, and only the web driver can.
  noNetworkOfTheirOwn,

  /// The suit shares this machine's network: a program can reach any site
  /// itself. [WhatMayLeaveThisMachine.sitesTheWebDriverMayReach] then limits
  /// only the web driver, not the path.
  sharesThisMachinesNetwork,
}

/// A model sign-in, by name, such as `claude-team`: what a path's rules
/// name, never the credential, which loop_launcher holds.
final class ModelSignInName {
  const ModelSignInName._(this.value);

  /// [raw] as a model sign-in's name, or null unless it is lowercase
  /// letters, digits, `-` and `_`, starting with a letter or digit.
  static ModelSignInName? parse(String raw) =>
      _modelSignInName.hasMatch(raw) ? ModelSignInName._(raw) : null;

  final String value;

  @override
  bool operator ==(Object other) =>
      other is ModelSignInName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final _modelSignInName = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

/// A site the web driver may reach, and the sign-in it goes as there: one
/// grant, never the site alone, since every bot of a kind makes requests to
/// the same sites.
final class SiteAndSignIn {
  const SiteAndSignIn(this.site, this.goesAs);

  /// [json] read back, strictly, as [fromJson] on [WhatMayLeaveThisMachine]
  /// reads its parts.
  static SiteAndSignIn fromJson(JsonObject json, String field) {
    _exactly(field, json, const {'site', 'goesAs'});
    return SiteAndSignIn(
      decodeOrigin(json.raw('site'), '$field.site'),
      GoesAs._fromJson(json.object('goesAs'), '$field.goesAs'),
    );
  }

  final Origin site;
  final GoesAs goesAs;

  @override
  bool operator ==(Object other) =>
      other is SiteAndSignIn && other.site == site && other.goesAs == goesAs;

  @override
  int get hashCode => Object.hash(site, goesAs);

  Object? toJson() => {'site': encodeOrigin(site), 'goesAs': goesAs._toJson()};
}

/// Who a request to a granted site goes as: a [GoesAsSignIn], or
/// [GoesAsNobody]. Never null, so "no sign-in" cannot be read as "any
/// sign-in", here or on the wire.
sealed class GoesAs {
  const GoesAs();

  static GoesAs _fromJson(JsonObject json, String field) {
    switch (json.string('kind')) {
      case 'signIn':
        _exactly(field, json, const {'kind', 'signIn'});
        return GoesAsSignIn(decodeSignIn(json.raw('signIn'), '$field.signIn'));
      case 'nobody':
        _exactly(field, json, const {'kind'});
        return const GoesAsNobody();
      case final kind:
        throw FormatException('$field.kind: not signIn or nobody: $kind');
    }
  }

  Object? _toJson();
}

/// Requests go as [signIn].
final class GoesAsSignIn extends GoesAs {
  const GoesAsSignIn(this.signIn);

  final SignIn signIn;

  @override
  bool operator ==(Object other) =>
      other is GoesAsSignIn && other.signIn == signIn;

  @override
  int get hashCode => signIn.hashCode;

  @override
  Object? _toJson() => {'kind': 'signIn', 'signIn': encodeSignIn(signIn)};
}

/// Requests go under no sign-in.
final class GoesAsNobody extends GoesAs {
  const GoesAsNobody();

  @override
  bool operator ==(Object other) => other is GoesAsNobody;

  @override
  int get hashCode => (GoesAsNobody).hashCode;

  @override
  Object? _toJson() => {'kind': 'nobody'};
}
