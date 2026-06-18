// vreader Android app module — feature #106 WI-1.
// Reads versionName/versionCode from `android/version.properties` (rule 40 — the
// Android version source of truth). Compose UI; core-library desugaring is
// mandatory (Readium 3.3.0, consumed from WI-5, links against it). Unit tests run
// on the JVM via Robolectric, driven by `scripts/run-android-tests.sh`.
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.devtools.ksp")                        // feature #106 WI-3 — Room codegen
    id("org.jetbrains.kotlin.plugin.serialization")      // feature #106 WI-6 — @Serializable in :app (ReadiumLocatorDto)
}

// Read via Gradle's provider API so `version.properties` is a TRACKED input
// (configuration-cache-safe — Codex Gate-4: raw file I/O can stale under the
// config cache).
val versionPropsText = providers.fileContents(
    rootProject.layout.projectDirectory.file("version.properties")
).asText.get()
val versionProps = Properties().apply { load(versionPropsText.reader()) }

android {
    namespace = "com.vreader.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.vreader.app"
        minSdk = 26              // >= Readium 3.3.0's floor of 23
        targetSdk = 36
        versionCode = versionProps.getProperty("versionCode").toInt()
        versionName = versionProps.getProperty("versionName")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
        buildConfig = true   // exposes VERSION_NAME/VERSION_CODE for the smoke test
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true   // Robolectric needs resources
        }
    }
}

// feature #106 WI-3 — Room exports the current schema JSON here so schema-versioned
// migrations have a checked-in baseline (the migration round-trip test guards it).
ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        // feature #106 WI-5 — Readium's open/parser API is gated behind
        // @ExperimentalReadiumApi; the single user (BookOpener) opts in at file
        // scope, so no module-wide flag (keeps future experimental use explicit).
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")   // WI-8 — design's nav icons
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.core:core-ktx:1.13.1")
    // feature #106 WI-8 — Library screen: ViewModel + lifecycle-aware Flow collection.
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")

    // feature #106 WI-2 — the shared identity/locator contracts (proves the
    // conformance lane tests the SAME code the app uses). WI-3 keys Room on it.
    implementation(project(":identity"))

    // feature #106 WI-3 — Room persistence (the PersistenceActor analog). room-ktx
    // brings the suspend/Flow DAO support; the compiler runs through KSP.
    val room = "2.8.4"
    implementation("androidx.room:room-runtime:$room")
    implementation("androidx.room:room-ktx:$room")
    ksp("androidx.room:room-compiler:$room")
    // The repository JSON-encodes the VReaderLocator envelope into one column. The
    // @Serializable types are compiled in :identity (which has the serialization
    // plugin); :app only needs the runtime library to call Json.encode/decode.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // feature #106 WI-5 — Readium-Kotlin 3.3.0 EPUB OPEN path (shared + streamer
    // only; the navigator/rendering is the design-blocked reader host #1745). Pin
    // exactly the Spike-B-verified set.
    val readium = "3.3.0"
    implementation("org.readium.kotlin-toolkit:readium-shared:$readium")
    implementation("org.readium.kotlin-toolkit:readium-streamer:$readium")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.13")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("androidx.test.ext:junit:1.2.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")

    // feature #106 WI-5 — instrumented EPUB-open test on the emulator (the open
    // path needs the real Android Readium runtime, not Robolectric).
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}
