import Foundation

public extension String {
    /// How well a typed filter matches (the palette, D48): its letters in order, spaces ignored, case and accent
    /// blind. Lower is better: a match that does not start a word costs 1, each break between matched letters 1, and
    /// a break that does not land on a word start 1 more. nil when the letters are not all there in order.
    func fuzzyScore(_ filter: String) -> Int? {
        let fold = { (text: String) in Array(text.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                          locale: nil)) }
        let text = fold(self), letters = fold(filter).filter { $0 != " " }
        guard let first = letters.first else { return 0 }
        let wordStart = { (index: Int) in index == 0 || !(text[index - 1].isLetter || text[index - 1].isNumber) }
        // Greedy from each place the first letter appears; the best of them.
        return text.indices.filter { text[$0] == first }.compactMap { start -> Int? in
            var score = wordStart(start) ? 0 : 1, last = start
            for letter in letters.dropFirst() {
                guard let next = text[(last + 1)...].firstIndex(of: letter) else { return nil }
                if next != last + 1 {
                    score += wordStart(next) ? 1 : 2
                }
                last = next
            }
            return score
        }.min()
    }
}
