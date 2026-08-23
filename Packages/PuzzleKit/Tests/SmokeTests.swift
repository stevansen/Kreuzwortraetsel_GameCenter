import Testing
@testable import PuzzleKit

@Test func alphabetRoundTrip() {
    #expect(Alphabet.normalize("STRASSE") == Alphabet.normalize("Straße"))
    #expect(Alphabet.normalize("MÜNCHEN")?.count == 7)
    #expect(Alphabet.normalize("Bad Ems") == nil)
}

@Test func sha256KnownVectors() {
    #expect(SHA256.hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA256.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
