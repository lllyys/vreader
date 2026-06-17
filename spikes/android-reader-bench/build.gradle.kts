// WI-2 bumps the toolchain to consume Readium-Kotlin 3.3.0: that AAR is built
// with Kotlin 2.3.20 (binary metadata a 2.0.x compiler can't read) and targets
// compileSdk 36, so the harness needs Kotlin >= 2.3.20 and an AGP that supports
// API 36. We stay on the stable AGP 8.x line (8.13.2 — AGP >= 8.10 supports
// compileSdk 36) rather than Readium's pinned AGP 9.0.0: AAR *consumption* only
// requires the Kotlin-metadata + compileSdk + core-library-desugaring match, not
// the producer's exact AGP. Gradle 8.14.4 (the pinned wrapper) supports AGP 8.13.
plugins {
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
