import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `applicationId` per product flavor, read out of the Gradle script.
///
/// `[^}]` keeps a match inside one flavor block: without it a flavor that lost
/// its `applicationId` would silently pair with the next flavor's id.
Map<String, String> _applicationIdsByFlavor() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final block = RegExp(
    r'create\("(\w+)"\)\s*\{[^}]*?applicationId\s*=\s*"([^"]+)"',
  );
  return {for (final m in block.allMatches(gradle)) m.group(1)!: m.group(2)!};
}

/// Right-hand side of `signingConfig = …` per product flavor.
///
/// Same `[^}]` bound as [_applicationIdsByFlavor]: a flavor without its own
/// assignment must not borrow the next block's.
Map<String, String> _signingConfigsByFlavor() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final block = RegExp(
    r'create\("(\w+)"\)\s*\{[^}]*?signingConfig\s*=\s*([^\n]+)',
  );
  return {
    for (final m in block.allMatches(gradle)) m.group(1)!: m.group(2)!.trim(),
  };
}

/// Body of `buildTypes { release { … } }`, or `null` when there is no such
/// block — an absent block sets no signing config either.
String? _releaseBuildTypeBody() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final buildTypes = gradle.indexOf(RegExp(r'buildTypes\s*\{'));
  if (buildTypes < 0) return null;
  return RegExp(
    r'\brelease\s*\{([^}]*)\}',
  ).firstMatch(gradle.substring(buildTypes))?.group(1);
}

void main() {
  group('Build flavor configuration', () {
    test('no default entry point is left behind', () {
      // Deliberate tripwire, not a tautology: while `lib/main.dart` existed,
      // `flutter build` without `-t` silently produced the business app —
      // blocker 4 in ai_docs/RELEASE_READINESS.md. Its absence is the only
      // thing forcing every build command to name its target out loud.
      expect(
        File('lib/main.dart').existsSync(),
        isFalse,
        reason:
            'lib/main.dart is the default target: recreating it makes an '
            'unflagged `flutter build` silently pick one of the two apps. '
            'Use lib/main_business.dart or lib/main_client.dart instead.',
      );
    });

    test('each entry point declares its own push audience', () {
      // The two builds share one Firebase user, so PushAudience is what keeps
      // them from overwriting each other's FCM token on `users/{uid}`.
      // Swapping these two values compiles and ships: the failure only
      // surfaces later, as pushes arriving in the wrong app.
      const entryPoints = {
        'lib/main_business.dart': 'PushAudience.business',
        'lib/main_client.dart': 'PushAudience.client',
      };

      for (final MapEntry(key: path, value: audience) in entryPoints.entries) {
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: '$path is a build target named by CI and .vscode/launch.json',
        );
        expect(
          file.readAsStringSync(),
          contains(audience),
          reason: '$path must bootstrap its container with $audience',
        );
      }
    });

    test('no file imports both firebase_options variants', () {
      // Both generated files declare a class named DefaultFirebaseOptions, so
      // importing the pair into one library is a compile error. Catching it
      // here names the cause; the compiler only names the symbol clash.
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = entity.readAsStringSync();
        if (code.contains('firebase_options_client.dart') &&
            code.contains('firebase_options_business.dart')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Each entry point imports exactly one firebase_options variant; '
            'both declare DefaultFirebaseOptions and cannot coexist.',
      );
    });

    test('build.gradle.kts declares both flavors with their applicationIds', () {
      // Guards the loop below, which is generated from this same parse: if the
      // regex ever stops matching, that loop registers ZERO tests and the
      // suite still reports green. An unconditional assertion is the only
      // thing that turns a vanished check into a red one. Doubles as the
      // assertion for R1's two identifiers.
      expect(_applicationIdsByFlavor(), {
        'client': 'kz.qorzhyn.app',
        'business': 'kz.qorzhyn.business',
      });
    });

    test('buildTypes.release sets no signingConfig', () {
      // A buildType's signingConfig overrides the flavor's (spec 051, [L5]):
      // one line here would put both apps back under a single key, silently.
      expect(
        _releaseBuildTypeBody() ?? '',
        isNot(contains('signingConfig')),
        reason:
            'buildTypes.release must not set signingConfig — it overrides '
            'the per-flavor upload keys from android/key.properties.',
      );
    });

    test('each flavor assigns its own signingConfig', () {
      // Key set first: a flavor that lost its assignment would otherwise make
      // the inequality below compare against null and pass.
      final configs = _signingConfigsByFlavor();
      expect(
        configs.keys,
        unorderedEquals(['client', 'business']),
        reason:
            'Each create("…") flavor block needs one '
            '`signingConfig = …` line; selection logic stays outside it.',
      );
      // [L2]: two apps, two upload keys. Same expression = same key.
      expect(
        configs['client'],
        isNot(configs['business']),
        reason: 'client and business must not share a signingConfig ([L2]).',
      );
    });

    for (final MapEntry(key: flavor, value: applicationId)
        in _applicationIdsByFlavor().entries) {
      final config = File('android/app/src/$flavor/google-services.json');

      test(
        '$flavor google-services.json covers $applicationId',
        () {
          // The ONLY place in this project where google-services.json is checked
          // against the flavor it belongs to. The Google Services Gradle plugin
          // is deliberately not applied (spec 050, [L6]), so no build step ever
          // reads these files — a mismatch would otherwise surface as pushes
          // silently going nowhere.
          //
          // Membership, not equality: the file carries an entry for every app
          // registered in the project at generation time, not just this
          // flavor's. That bounds what this proves — it catches a mutated or
          // stale package_name, but NOT the two files swapped between
          // directories, since the business file also lists the client id.
          // The file format offers nothing stronger.
          final packageNames =
              (jsonDecode(config.readAsStringSync())
                      as Map<String, dynamic>)['client']
                  as List<dynamic>;
          final ids = packageNames
              .map(
                (c) =>
                    ((c as Map<String, dynamic>)['client_info']
                            as Map<String, dynamic>)['android_client_info']
                        as Map<String, dynamic>,
              )
              .map((info) => info['package_name'] as String)
              .toList();

          expect(
            ids,
            contains(applicationId),
            reason:
                'android/app/src/$flavor/google-services.json has no entry for '
                '$applicationId — re-run `flutterfire configure` for this flavor.',
          );
        },
        // Never red merely for being absent: [L7] keeps these files out of
        // git, so CI and every clean checkout legitimately lack them.
        skip: config.existsSync()
            ? null
            : 'android/app/src/$flavor/google-services.json is not on disk '
                  '(gitignored by [L7]); re-run `flutterfire configure` with '
                  '--android-out=android/app/src/$flavor/google-services.json '
                  'to enable this check locally.',
      );
    }
  });
}
