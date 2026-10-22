import HerdrKit
import Testing

@Test func `typed letters match in order, spaces ignored`() {
    #expect("Split Right".fuzzyScore("split r") == 1)
    #expect("Split Right".fuzzyScore("sr") == 1)
    #expect("Split Right".fuzzyScore("rs") == nil)
    #expect("Split Right".fuzzyScore("") == 0)
}

@Test func `case and accents do not count`() {
    #expect("Café".fuzzyScore("CAFE") == 0)
}

@Test func `word starts beat letters inside words`() {
    // "sd" lands on "Split Down"'s word starts; inside "Inside" it does not.
    #expect("Split Down".fuzzyScore("sd") == 1)
    #expect("Inside".fuzzyScore("sd") == 3)
    #expect("light dark".fuzzyScore("dark") == 0)
    #expect("Bigger".fuzzyScore("igg") == 1)
}

@Test func `the best start wins`() {
    // Greedy from the first "a" breaks; from the second it does not.
    #expect("a xab".fuzzyScore("ab") == 1)
}
