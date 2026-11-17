import 'dart:convert';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

void main() {
  final teams = Origin.parse('https://graph.microsoft.com')!;
  final docs = Origin.parse('https://docs.example.com')!;
  final bot = SignIn.parse('teams-bot')!;
  final rules = WhatMayLeaveThisMachine(
    modelSignInsTheLoopIsGiven: [ModelSignInName.parse('claude-team')!],
    sitesTheWebDriverMayReach: [
      SiteAndSignIn(teams, GoesAsSignIn(bot)),
      SiteAndSignIn(docs, const GoesAsNobody()),
    ],
    programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
  );

  MakesWebRequest to(Origin origin, {SignIn? signIn}) => MakesWebRequest(
    WebRequest(
      origin,
      renderer: RendererName.parse('teams-reply')!,
      signIn: signIn,
    ),
    null,
  );

  test('what may leave this machine reads back as it was written', () {
    final back = WhatMayLeaveThisMachine.fromJson(
      JsonObject.decode(jsonEncode(rules.toJson())),
    );
    expect(back.modelSignInsTheLoopIsGiven, rules.modelSignInsTheLoopIsGiven);
    expect(back.sitesTheWebDriverMayReach, rules.sitesTheWebDriverMayReach);
    expect(back.programsNetwork, ProgramsNetwork.noNetworkOfTheirOwn);
  });

  test('a site is granted with its sign-in, never alone', () {
    expect(rules.allowsWebRequest(to(teams, signIn: bot)), isTrue);
    expect(rules.allowsWebRequest(to(docs)), isTrue);
    // No sign-in is not any sign-in, and a sign-in is not no sign-in.
    expect(rules.allowsWebRequest(to(docs, signIn: bot)), isFalse);
    expect(rules.allowsWebRequest(to(teams)), isFalse);
    expect(
      rules.allowsWebRequest(to(teams, signIn: SignIn.parse('other-bot'))),
      isFalse,
    );
    expect(
      rules.allowsWebRequest(to(Origin.parse('https://evil.example')!)),
      isFalse,
    );
  });

  test('a grant under no sign-in is not a grant under a sign-in', () {
    // By ==, not only by hash, so a set that compared grants by site alone
    // would still be caught.
    expect(const GoesAsNobody() == GoesAsSignIn(bot), isFalse);
    expect(GoesAsSignIn(bot) == const GoesAsNobody(), isFalse);
    expect(
      SiteAndSignIn(docs, const GoesAsNobody()) ==
          SiteAndSignIn(docs, GoesAsSignIn(bot)),
      isFalse,
    );
    expect(
      SiteAndSignIn(docs, GoesAsSignIn(bot)) ==
          SiteAndSignIn(docs, GoesAsSignIn(SignIn.parse('other-bot')!)),
      isFalse,
    );
  });

  test('what may leave this machine is read strictly', () {
    final good = jsonDecode(jsonEncode(rules.toJson())) as Map<String, Object?>;
    final site = {
      'site': 'https://docs.example.com',
      'goesAs': {'kind': 'nobody'},
    };
    for (final json in [
      null,
      <String, Object?>{},
      {...good, 'mayWrite': true},
      {...good, 'programsNetwork': 'visorUp'},
      {...good, 'modelSignInsTheLoopIsGiven': 'claude-team'},
      {
        ...good,
        'modelSignInsTheLoopIsGiven': ['Claude Team'],
      },
      for (final bad in <Object?>[
        {...site, 'goesAs': null},
        {...site, 'goesAs': 'nobody'},
        {
          ...site,
          'goesAs': {'kind': 'anyone'},
        },
        {
          ...site,
          'goesAs': {'kind': 'nobody', 'signIn': 'teams-bot'},
        },
        {
          ...site,
          'goesAs': {'kind': 'signIn'},
        },
        {...site, 'site': 'https://docs.example.com/path'},
        {...site, 'path': '/'},
      ])
        {
          ...good,
          'sitesTheWebDriverMayReach': [bad],
        },
    ]) {
      expect(
        () => WhatMayLeaveThisMachine.fromJson(
          JsonObject.decode(jsonEncode(json)),
        ),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
