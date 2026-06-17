// Purpose: feature #106 WI-2 — the shared `:identity` module. A PURE Kotlin/JVM
// module (NO Android/Readium deps) holding vreader's canonical identity/locator
// contracts (`Identity`, `CanonicalLocator`). BOTH `:app` and the `contracts/`
// conformance lane depend on this ONE module, so the golden-vector conformance
// test proves the SAME code the app uses — not a separate reference (Gate-2 H1).
//
// Pinned to the SAME Kotlin/JDK toolchain as `:app` (Kotlin 2.3.20 / JDK 17).
// The conformance test reads `contracts/vectors/` (vreader.vectors.dir sysprop).
plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.serialization")
}

dependencies {
    // feature #106 WI-3 — the VReaderLocator/Locator envelope value types
    // (`@Serializable`) live in main now, so serialization-json is an
    // `implementation` dep, not test-only.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    testImplementation(kotlin("test"))
}

kotlin { jvmToolchain(17) }

tasks.test {
    useJUnitPlatform()
    // Point the conformance test at the repo's shared golden vectors. Relative to
    // android/identity, the repo root is ../.. ; contracts/vectors lives there.
    systemProperty(
        "vreader.vectors.dir",
        rootProject.projectDir.resolve("../contracts/vectors").canonicalFile.absolutePath,
    )
    // Force re-run so the cross-diff .out/*.txt is always re-emitted (the standalone
    // lane's `cleanTest test` rationale — bug #355).
    outputs.upToDateWhen { false }
}
