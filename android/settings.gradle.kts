// vreader Android app — feature #106 WI-1 (the first real app shell).
// Self-contained Gradle root under android/ (the iOS app uses xcodegen/project.yml
// at the repo root; the two builds never overlap). Toolchain pinned to the
// Spike-B-verified set (AGP 8.13.2 / Kotlin 2.3.20 / Gradle 8.14.4 / compileSdk 36).
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}
rootProject.name = "vreader-android"
include(":app")
