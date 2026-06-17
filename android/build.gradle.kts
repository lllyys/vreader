// Root build — feature #106 WI-1. Pins the Spike-B-verified toolchain (the
// rationale is the same as `spikes/android-reader-bench/build.gradle.kts`):
// Readium-Kotlin 3.3.0 (consumed in WI-5) needs Kotlin >= 2.3.20 + compileSdk 36
// + core-library desugaring; AGP 8.13.2 (stable 8.x, supports API 36) on the
// pinned Gradle 8.14.4 wrapper. Kotlin 2.x moves the Compose compiler to its own
// Gradle plugin (`org.jetbrains.kotlin.plugin.compose`), version-locked to Kotlin.
plugins {
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.20" apply false
}
