import java.util.Properties

plugins {
    id("com.android.application")
    // Google Services / Crashlytics Gradle plugins are deliberately NOT applied
    // (spec 050, [L6]). `flutterfire configure` re-adds them on every run —
    // strip the "FlutterFire Configuration" block again when it does.
    // Consequence: google-services.json is never read at build time, so the
    // package_name <-> applicationId check lives only in the R11 test.
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties is gitignored ([L3]); keys are prefixed `client.` /
// `business.`. See android/key.properties.example.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) keyPropertiesFile.inputStream().use { load(it) }
}
val uploadFlavors = listOf("client", "business")
val uploadKeyEntries = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")

/** True when android/key.properties carries all four upload-key entries for [flavor]. */
fun hasUploadKey(flavor: String) =
    uploadKeyEntries.all { !keyProperties.getProperty("$flavor.$it").isNullOrBlank() }

android {
    namespace = "kz.qorzhyn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // No applicationId here on purpose: each product flavor sets its own,
        // so an unflagged build fails instead of silently producing one of the
        // two apps. See ai_specs/archive/050-android-app-flavors-spec.md (R1, R13).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Flavor names mirror the members of PushAudience
    // (lib/src/features/notifications/domain/push_audience.dart): adding a
    // third build changes both lists together.
    flavorDimensions += "app"

    // Upload-key signing (spec 051). Each flavor signs its release with its own
    // upload key from android/key.properties ([L2]); a flavor missing any of
    // its four entries falls back to the debug key with a warning ([L6]).
    // Selection stays out of the create("…") blocks below: flavor_config_test
    // parses them up to the first `}`.
    signingConfigs {
        for (flavor in uploadFlavors) {
            if (!hasUploadKey(flavor)) continue
            create("${flavor}Upload") {
                storeFile = file(keyProperties.getProperty("$flavor.storeFile"))
                storePassword = keyProperties.getProperty("$flavor.storePassword")
                keyAlias = keyProperties.getProperty("$flavor.keyAlias")
                keyPassword = keyProperties.getProperty("$flavor.keyPassword")
            }
        }
    }

    fun uploadSigning(flavor: String) =
        signingConfigs.getByName(if (hasUploadKey(flavor)) "${flavor}Upload" else "debug")

    productFlavors {
        create("client") {
            dimension = "app"
            applicationId = "kz.qorzhyn.app"
            signingConfig = uploadSigning("client")
            // Resolved into android:label; a second AndroidManifest.xml per
            // flavor would drift on every permission added to only one of them.
            manifestPlaceholders["appLabel"] = "Qorzhyn"
        }
        create("business") {
            dimension = "app"
            applicationId = "kz.qorzhyn.business"
            signingConfig = uploadSigning("business")
            manifestPlaceholders["appLabel"] = "Qorzhyn Business"
        }
    }

    // No buildTypes.release block on purpose: a buildType's signingConfig
    // overrides the flavor's ([L5]), so one line there would put both apps
    // under a single key. The debug buildType keeps AGP's debug signing.
}

flutter {
    source = "../.."
}

// Printed only when this flavor's release is actually being signed, so debug
// builds and `flutter run` without keys stay quiet. Keyed on
// validateSigning<Variant> (present for both APK and AAB): the Flutter plugin
// pulls the OTHER flavor's *Release Dart tasks into the graph too, so a
// name-suffix match would warn about both apps. logger.quiet, not
// logger.warn: without -v Flutter runs Gradle with -q, which hides WARN.
gradle.taskGraph.whenReady {
    for (flavor in uploadFlavors) {
        if (hasUploadKey(flavor)) continue
        val task = "validateSigning" + flavor.replaceFirstChar { it.uppercase() } + "Release"
        if (allTasks.none { it.project == project && it.name == task }) continue
        logger.quiet(
            "WARNING: no upload key for flavor '$flavor' in android/key.properties — " +
                "its release is signed with the DEBUG key, which Google Play rejects.",
        )
    }
}
