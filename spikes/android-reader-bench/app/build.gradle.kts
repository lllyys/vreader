plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "vreader.spike"
    // compileSdk 36: Readium 3.3.0's AARs reference API-36 symbols (the toolkit
    // builds against compileSdk 36). 35 fails to resolve them.
    compileSdk = 36
    defaultConfig {
        applicationId = "vreader.spike"
        minSdk = 26          // >= Readium 3.3.0's floor of 23
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // MANDATORY for Readium 3.3.0 — it enables core library desugaring in its
        // own convention plugin; a consumer that doesn't will fail at link time.
        isCoreLibraryDesugaringEnabled = true
    }
}
kotlin {
    // Kotlin 2.3.20 removed the legacy `kotlinOptions` DSL (hard error) — use
    // the compilerOptions DSL.
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        // Readium's preferences/navigator API (EpubPreferences, etc.) is gated
        // behind @ExperimentalReadiumApi; opt in module-wide for the spike.
        freeCompilerArgs.add("-opt-in=org.readium.r2.shared.ExperimentalReadiumApi")
    }
}
dependencies {
    val readium = "3.3.0"
    implementation("org.readium.kotlin-toolkit:readium-shared:$readium")
    implementation("org.readium.kotlin-toolkit:readium-streamer:$readium")
    implementation("org.readium.kotlin-toolkit:readium-navigator:$readium")

    // Readium's own pinned transitive versions (pin them in the consumer too).
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    // FragmentScenario for hosting the navigator fragment in-process (no UI automation).
    androidTestImplementation("androidx.fragment:fragment-testing:1.8.9")
    // Contributes EmptyFragmentActivity to the app-under-test's DEBUG manifest —
    // launchFragmentInContainer launches it, so it must be declared in the app
    // (not just the test) manifest, or ActivityScenario can't resolve it.
    debugImplementation("androidx.fragment:fragment-testing-manifest:1.8.9")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
}
