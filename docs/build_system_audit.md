# Android Build System Audit

Investigation date: 2026-05-31

Scope: investigate the Flutter/Android Kotlin Gradle Plugin warning without applying fixes, upgrading dependencies, or changing build configuration.
## 1. Executive Summary

The Android build warning is real and has two separate origins:

1. The app module still applies the legacy Kotlin Gradle Plugin through `id("kotlin-android")` and still uses the legacy `kotlinOptions` block.
2. Two resolved Android plugins, `pdfx` and `shared_preferences_android`, also apply the Kotlin Gradle Plugin in their Android build files.

Flutter 3.44.0 currently keeps this project buildable by adding compatibility flags in `android/gradle.properties`:

```properties
android.builtInKotlin=false
android.newDsl=false
```

Those flags are a compatibility bridge, not the target end state. Flutter's Built-in Kotlin migration guide says plugins that continue to apply KGP will fail in a future Flutter/AGP 9+ path when temporary KGP compatibility support is removed.

Current impact:

- Can the app still build today? Yes, under current Flutter tooling and compatibility mode. A recent `flutter run --dart-define-from-file=env/dev.json` completed successfully in this environment. Direct `gradlew.bat --version` failed only because this shell has no `JAVA_HOME` and no `java` on `PATH`, which is a local Java environment issue, not the same as the KGP warning.
- Can the app still release today? Technically yes if CI/local release machines have Java, Android cmdline-tools, and Android licenses configured. The warning should still be treated as medium risk now and high risk before future Flutter/AGP upgrades.
- Main root cause: owned app Gradle file plus third-party plugin Gradle files are still on legacy KGP application.
- Do not fix this by rewriting backend, Supabase, extraction, realtime, storage, auth, or tenant isolation code. The safe remediation surface is Android build configuration and package selection only.

## 2. Root Cause Analysis

Methodology used:

- Observe: checked the Android build files, dependency lockfile, Flutter tool versions, resolved plugin sources, and upstream migration documentation.
- Reproduce: ran read-only tooling commands. `flutter --version`, `dart --version`, `flutter doctor -v`, and `flutter pub outdated --no-dev-dependencies` completed. Direct Gradle wrapper execution did not start because Java is not configured in this shell.
- Localize: compared app-level Gradle usage with cached plugin Gradle usage and upstream package build files.
- Validate: scanned all resolved cached Android plugins for KGP markers.
- Conclude: the warning is caused by app-level legacy KGP plus two plugin-level KGP usages.

Observed local causes:

- `android/app/build.gradle.kts` applies `id("kotlin-android")`.
- `android/app/build.gradle.kts` configures Kotlin via `kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }`.
- `android/gradle.properties` contains `android.builtInKotlin=false` and `android.newDsl=false`, matching Flutter's compatibility-mode migration flags.
- Cached `pdfx-2.9.2/android/build.gradle` applies `kotlin-android`, declares `org.jetbrains.kotlin:kotlin-gradle-plugin`, and uses `kotlinOptions`.
- Cached `shared_preferences_android-2.4.21/android/build.gradle` applies `kotlin-android` and declares `org.jetbrains.kotlin:kotlin-gradle-plugin`.

The plugin scan found these resolved Android plugins:

| Package | Applies KGP? | Notes |
| --- | --- | --- |
| app_links | No | Android plugin present; no KGP marker found. |
| file_picker | No | Android plugin present; no KGP marker found. |
| flutter_plugin_android_lifecycle | No | Android plugin present; Kotlin DSL file but no KGP marker found. |
| flutter_secure_storage | No | Android plugin present; no KGP marker found. |
| image_picker_android | No | Android plugin present; Kotlin DSL file but no KGP marker found. |
| local_auth_android | No | Android plugin present; no KGP marker found. |
| path_provider_android | No | Android plugin present; no KGP marker found. |
| pdfx | Yes | Applies `kotlin-android`; adds KGP classpath. |
| permission_handler_android | No | Android plugin present; no KGP marker found. |
| shared_preferences_android | Yes | Applies `kotlin-android`; adds KGP classpath. |
| sqflite_android | No | Android plugin present; no KGP marker found. |
| url_launcher_android | No | Android plugin present; no KGP marker found. |

## 3. Current Build Architecture

Current versions and configuration:

| Component | Current Value | Evidence |
| --- | --- | --- |
| Flutter | 3.44.0 stable | `flutter --version` |
| Dart | 3.12.0 | `dart --version` / Flutter tool |
| Android Gradle Plugin | 8.11.1 | `android/settings.gradle.kts` |
| Kotlin plugin declaration | 2.2.20 | `android/settings.gradle.kts` |
| Gradle wrapper | 8.14 | `android/gradle/wrapper/gradle-wrapper.properties` |
| compileSdk | 36 | Flutter Gradle default `flutter.compileSdkVersion` |
| targetSdk | 36 | Flutter Gradle default `flutter.targetSdkVersion` |
| minSdk | 24 | Flutter Gradle default `flutter.minSdkVersion` |
| NDK | 28.2.13676358 | Flutter Gradle default `flutter.ndkVersion` |

Owned Android files inspected:

- `android/settings.gradle.kts`
- `android/app/build.gradle.kts`
- `android/build.gradle.kts`
- `android/gradle.properties`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/local.properties`

Current app module shape:

- Uses Flutter's plugin loader and Gradle plugin include build.
- Applies Android application plugin.
- Applies legacy Kotlin Gradle Plugin via `kotlin-android`.
- Applies Flutter Gradle plugin.
- Defers SDK values to Flutter Gradle defaults.
- Uses Java 17.
- Uses legacy `kotlinOptions` instead of the newer `kotlin { compilerOptions { ... } }` DSL.

Environment note:

- `flutter doctor -v` reports Android cmdline-tools missing and Android license status unknown.
- Direct Gradle wrapper execution in the current shell fails before project evaluation because Java is not configured. CI/release machines must have Java available even if Flutter tooling currently succeeds locally.

## 4. Plugin Compatibility Analysis

Dependency risk matrix:

| Package | Current Version | Latest Version | Risk | Migration Required | Recommended Action |
| --- | --- | --- | --- | --- | --- |
| pdfx | 2.9.2 | 2.9.2 | High | Yes, plugin still applies KGP and uses legacy Groovy Android build file. | Do not switch immediately. Open/track upstream Built-in Kotlin issue and run a short PDF-rendering replacement spike before future Flutter/AGP upgrades. |
| shared_preferences_android | 2.4.21 | 2.4.23 | Medium | Yes, latest upstream still applies `kotlin-android`; 2.4.22 only moved build files from Groovy to Kotlin. | Upgrade only after normal dependency validation; do not expect this alone to remove the Built-in Kotlin warning. Track Flutter package migration. |
| app module | N/A | N/A | Medium | Yes, remove app-level KGP and migrate compiler options. | Migrate owned Gradle files first in a dedicated build-system PR after this audit. |
| app_links | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |
| file_picker | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |
| flutter_secure_storage | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |
| image_picker_android | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |
| local_auth_android | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |
| path_provider_android | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |
| permission_handler_android | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |
| sqflite_android | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |
| url_launcher_android | resolved | resolved | Low | No current KGP marker found. | Leave untouched. |

`pdfx` details:

- Project lockfile resolves `pdfx` to `2.9.2`.
- Pub.dev reports `2.9.2` as the latest visible release and published 11 months ago.
- The current upstream `pdfx/android/build.gradle` still uses:
  - `ext.kotlin_version = '1.9.23'`
  - `classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"`
  - `apply plugin: 'kotlin-android'`
  - `kotlinOptions { jvmTarget = '11' }`
- This is the highest-risk plugin because there is no newer `pdfx` release to try.

`shared_preferences_android` details:

- Project lockfile resolves `shared_preferences_android` to `2.4.21`.
- `flutter pub outdated --no-dev-dependencies` reports latest/upgradable `2.4.23`.
- Changelog evidence:
  - `2.4.22`: updates build files from Groovy to Kotlin.
  - `2.4.23`: dartdoc comment fix.
- Upstream `main` currently has `android/build.gradle.kts`, but still declares a KGP classpath and applies `id("kotlin-android")`.
- Therefore upgrading from `2.4.21` to `2.4.23` may modernize the build script style but should not be assumed to eliminate the Built-in Kotlin warning.

PDF alternatives reviewed:

- `pdf_render` latest `1.4.12` is marked in its changelog as maintenance mode; its author recommends `pdfrx` as a better replacement. It is not the first-choice replacement without deeper validation.
- `native_pdf_view` latest `6.0.0+1` is published 4 years ago and depends on `pdfx`, so it does not remove the `pdfx` risk.
- `syncfusion_flutter_pdfviewer` latest `33.2.8` is actively maintained, has frequent 2026 releases, and includes Android performance and memory fixes. It may carry licensing and dependency implications and should be evaluated in a controlled spike before adoption.
- Native Android/PDFium integration would remove third-party viewer coupling but increases platform maintenance burden and must be isolated from document extraction flows.

Conclusion: keep `pdfx` for now unless the migration timeline forces replacement. The safe near-term action is to migrate owned Gradle files and track/report plugin incompatibility. The safe medium-term action is a PDF viewer spike, not an immediate production package swap.

## 5. Kotlin Migration Analysis

Flutter's Built-in Kotlin app migration guide says app developers should:

- Verify the compatibility flags in `gradle.properties`.
- Remove `kotlin-android` / `org.jetbrains.kotlin.android` from the app Gradle file.
- Remove legacy `kotlinOptions`.
- Add a `kotlin { compilerOptions { jvmTarget = ... } }` block.
- Validate with `flutter run` or `flutter build apk`.
- If a plugin fails because it is unmigrated, report the incompatible plugin to the plugin authors.

Current app status against that checklist:

| Migration Item | Current Status |
| --- | --- |
| Compatibility flags present | Yes: `android.builtInKotlin=false`, `android.newDsl=false`. |
| App-level `kotlin-android` removed | No. |
| Legacy `kotlinOptions` removed | No. |
| `kotlin.compilerOptions` added | No. |
| Plugin KGP usage removed | No, blocked by `pdfx` and `shared_preferences_android`. |
| Full validation completed | No. Flutter run previously succeeded, but direct Gradle validation is blocked by local Java setup. |

The owned migration is mechanically small, but it should be done as a dedicated build-system change because it affects Android build behavior across debug, release, and CI.

## 6. Flutter Future Compatibility Analysis

Flutter 3.44 behavior:

- Warning/compatibility mode, not immediate failure.
- Flutter tooling can add `android.builtInKotlin=false` and `android.newDsl=false` to keep older projects working.
- The current project already has both flags.

Android Studio behavior:

- Flutter's migration docs say Android Studio tooling can also add the compatibility flags.
- Developers should expect the same warning class until app and plugin KGP usage is removed.

Future Flutter / AGP 9+ behavior:

- Flutter documentation states that starting with AGP 9.0, support for applying KGP has been removed.
- Flutter temporarily allows KGP while apps and plugins migrate to AGP 9.0+.
- That temporary support will be removed in a future Flutter version.
- If this project upgrades into that future state while `pdfx`, `shared_preferences_android`, or the app module still applies KGP, Android builds can fail.

CI/CD risk:

- Medium today if CI pins Flutter 3.44.x, AGP 8.11.1, Gradle 8.14, and has Java/Android SDK configured.
- High if CI auto-upgrades Flutter, Android Studio, AGP, Gradle, or Android plugin dependencies without a build-system migration plan.
- Separate but immediate CI risk: Java and Android cmdline-tools/licenses must be installed and pinned in CI. The current shell could not run `gradlew.bat` because Java is unavailable.

## 7. Risk Matrix

| Risk | Severity | Likelihood | Evidence | Mitigation |
| --- | --- | --- | --- | --- |
| Future Android build failure after Flutter/AGP upgrade | High | Medium | App and two plugins still apply KGP; Flutter docs warn support is temporary. | Pin toolchain until migration is complete; migrate owned Gradle; track plugin migration. |
| `pdfx` blocks Built-in Kotlin readiness | High | Medium | Latest `2.9.2` upstream still applies KGP; no newer release available. | Open upstream issue; evaluate replacement in spike; keep extraction flow untouched. |
| `shared_preferences_android` warning remains after minor upgrade | Medium | High | Latest upstream KTS file still applies KGP. | Do not assume `2.4.23` fixes warning; track Flutter package migration. |
| Release/CI fails due local Java/Android SDK setup | Medium | Medium | Direct Gradle wrapper failed because Java is not configured; doctor reports cmdline-tools/licenses issue. | Configure Java, Android cmdline-tools, and licenses in local/CI before release validation. |
| Breaking document preview/extraction by replacing PDF library too quickly | High | Medium | PDF rendering is tied to document workflows; `pdfx` is currently production dependency. | Run isolated PoC and regression tests before any package swap. |
| Backend/security regression from unrelated changes | Critical | Low if scoped | Supabase, storage cleanup, realtime, extraction, and tenant isolation are unrelated to this warning. | Leave backend, RLS, OpenRouter, extraction, realtime, and `company_id` data access untouched. |

## 8. Recommended Fixes

Do not apply these fixes during this audit. These are recommended follow-up actions only.

Recommended sequence:

1. Stabilize the build environment.
   - Install/configure Java for Gradle execution.
   - Install Android cmdline-tools.
   - Accept Android licenses in CI/local release machines.
   - Confirm `flutter build apk` and `flutter build appbundle` can run before changing Gradle files.

2. Migrate owned app Gradle configuration.
   - Remove `id("kotlin-android")` from `android/app/build.gradle.kts`.
   - Remove legacy `kotlinOptions` from `android/app/build.gradle.kts`.
   - Add the new `kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }` block.
   - Re-test debug and release Android builds.

3. Re-check warning output.
   - If the app-level warning disappears but plugin warnings remain, the remaining blockers are third-party packages.
   - If the app fails due plugin KGP usage, do not patch Pub cache as a permanent solution.

4. Track plugin migration.
   - `shared_preferences_android`: test `2.4.23` only as a normal dependency update; expect that it may still warn.
   - `pdfx`: open or track an upstream Built-in Kotlin migration issue.

5. Run a PDF replacement spike only if needed.
   - Evaluate `syncfusion_flutter_pdfviewer` and `pdfrx`/current best alternative against current document preview behavior.
   - Include large PDFs, scanned PDFs, password/error behavior if applicable, memory usage, Android low-end devices, and current extraction/document flows.
   - Do not touch Supabase, OpenRouter, realtime, storage cleanup, or tenant isolation during the spike.

## 9. Migration Roadmap

Phase 0: Audit complete

- Produce this report.
- No build files changed.
- No dependencies upgraded.

Phase 1: Environment readiness

- Configure Java and Android SDK command-line tools.
- Verify Gradle wrapper can run.
- Verify Flutter Android debug and release builds from a clean shell.

Phase 2: Owned Gradle migration

- Apply Flutter's app-level Built-in Kotlin migration to `android/app/build.gradle.kts`.
- Validate `flutter run`, `flutter build apk`, and `flutter build appbundle`.
- Record exact warning/failure output after owned migration.

Phase 3: Plugin containment

- Upgrade `shared_preferences_android` only if normal dependency validation passes.
- Track whether Flutter's package team migrates the plugin away from KGP.
- For `pdfx`, open/track migration issue and decide whether to wait or replace.

Phase 4: PDF replacement decision

- Run a small branch/PoC with candidate PDF viewer.
- Compare API fit, rendering quality, memory, license, Android build compatibility, and document workflow impact.
- Only proceed if it reduces build risk without damaging document extraction/preview UX.

Phase 5: Toolchain upgrade

- Upgrade Flutter/AGP/Gradle only after app and plugin migration risks are cleared or consciously accepted.
- Keep CI pinned during transition.

## 10. Safe Implementation Order

1. Pin CI Flutter/Gradle/AGP versions before any migration work.
2. Fix Java/Android SDK environment so Gradle validation is reliable.
3. Create a dedicated build-system branch.
4. Migrate only `android/app/build.gradle.kts` first.
5. Run Android debug and release builds.
6. Inspect remaining warnings.
7. Update `shared_preferences_android` in a separate dependency PR if desired.
8. Open/track `pdfx` Built-in Kotlin migration issue.
9. Run PDF viewer replacement spike only if `pdfx` remains blocking.
10. Upgrade Flutter/AGP only after the above is green.

This order intentionally avoids touching business logic, Supabase, extraction, realtime, document storage cleanup, and tenant-scoped data access.

## 11. Files To Modify

Potential future modifications, not performed in this audit:

- `android/app/build.gradle.kts`
  - Remove app-level KGP application.
  - Replace legacy Kotlin options with compiler options DSL.

- `android/gradle.properties`
  - Eventually remove or update compatibility flags only after the app and plugin ecosystem are ready.
  - Do not remove these flags early.

- `pubspec.yaml` / `pubspec.lock`
  - Only if choosing to update `shared_preferences_android` through normal dependency resolution or replacing `pdfx` after a validated spike.

- CI configuration files, if present outside the inspected files
  - Pin Flutter/Java/Android SDK versions.
  - Install cmdline-tools and accept Android licenses.

- Optional future tracking documentation
  - Record exact warning output and plugin issue links after migration testing.

## 12. Files To Leave Untouched

These should not be modified for the Kotlin build warning:

- Supabase SQL, migrations, RLS policies, and setup scripts.
- Any `company_id` tenant isolation logic.
- OpenRouter, NVIDIA Nemotron, or document extraction services.
- Realtime subscriptions and providers.
- Storage cleanup/delete flows.
- Auth, local auth, or security gates.
- Dashboard, FAB, document detail, and UI presentation files.
- Cached Pub package files under the global Pub cache. They can be inspected for evidence, but permanent fixes must come from dependency updates, overrides/forks with explicit ownership, or upstream changes.

## 13. Rollback Plan

For future implementation work:

1. Before changes, capture a clean baseline:
   - `flutter --version`
   - `dart --version`
   - `flutter doctor -v`
   - `flutter build apk` or `flutter build appbundle` output
   - Current warning text

2. For owned Gradle migration:
   - Keep changes limited to `android/app/build.gradle.kts` first.
   - If builds fail, revert only that file to the previous state and keep dependency files untouched.
   - Re-run the same build command to confirm rollback restored the previous behavior.

3. For dependency updates:
   - Update one package at a time.
   - If a dependency update fails, revert `pubspec.yaml` and `pubspec.lock` only for that package update.
   - Run `flutter pub get`, analyzer, and Android build validation again.

4. For PDF viewer replacement:
   - Keep it on a separate branch/spike.
   - Preserve existing `pdfx` code path until candidate behavior is verified.
   - Roll back by restoring the previous `pdfx` dependency and preview implementation.

5. For CI/toolchain changes:
   - Pin versions explicitly.
   - Roll back by restoring the previous CI image/toolchain version.

Rollback should never require changes to Supabase, RLS, extraction, realtime, storage cleanup, auth, or tenant isolation. If rollback appears to require those surfaces, the migration scope has expanded too far and should be stopped.