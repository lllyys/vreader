import Testing

@Test func smokeTest() {
    #expect(true, "Test infrastructure is working")
}

@Test func bundleIdentifierIsCorrect() {
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    #expect(bundleId.contains("vreader"), "Bundle identifier should contain vreader")
}
