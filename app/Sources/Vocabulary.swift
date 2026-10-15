import AppKit

// Your words: names, brands, jargon that the model spells its own way.
// After each dictation, a word one letter away from one of yours (accents
// aside), or two or three words that run together into one of yours, become
// yours. Short words (three letters or less) are never touched: one letter
// off a three-letter word turned "toe" into "Koe". Ported from Koe 0.1
// (dictionary.rs), which only spared two letters.
enum Vocabulary {
    static var words: [String] {
        get { UserDefaults.standard.stringArray(forKey: "dictionary") ?? [] }
        set {
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            UserDefaults.standard.set(Array(NSOrderedSet(array: cleaned)) as? [String] ?? cleaned, forKey: "dictionary")
        }
    }

    static func correct(_ text: String, with words: [String] = Vocabulary.words) -> String {
        guard !words.isEmpty else { return text }
        let normalized = words.map { plain($0) }
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            var merged = false
            for window in [3, 2] where i + window <= tokens.count {
                let slice = Array(tokens[i..<(i + window)])
                let (lastBase, punctuation) = splitPunctuation(slice.last!)
                let parts = slice.dropLast().map { plain($0) } + [plain(lastBase)]
                // Only words run together: no stray mark, and no word that
                // is one of yours on its own ("à Gwendall" stays two words).
                guard parts.allSatisfy({ $0.contains(where: \.isLetter) && !$0.contains(where: \.isPunctuation) }) else { continue }
                let joined = parts.joined()
                let rest = [parts.dropFirst().joined(), parts.dropLast().joined()]
                if let index = normalized.firstIndex(where: { word in
                    word == joined || (joined.count >= 4 && distance(word, joined) <= 1 && !rest.contains { distance(word, $0) <= 1 })
                }) {
                    out.append(words[index] + punctuation)
                    i += window
                    merged = true
                    break
                }
            }
            if merged { continue }
            let (base, punctuation) = splitPunctuation(tokens[i])
            if let match = fuzzy(base, words, normalized) {
                out.append(match + punctuation)
            } else {
                out.append(tokens[i])
            }
            i += 1
        }
        return out.joined(separator: " ")
    }

    private static func fuzzy(_ word: String, _ words: [String], _ normalized: [String]) -> String? {
        let input = plain(word)
        guard input.count > 3 else { return nil }
        // A word of the language is what was said, not a near miss: with
        // "wham" in the dictionary, "what" stays "what".
        if isWord(word) { return nil }
        var best: (String, Int)?
        for (index, candidate) in normalized.enumerated() {
            if candidate == input { return nil } // already right
            guard abs(candidate.count - input.count) <= 1 else { continue }
            let d = distance(input, candidate)
            if d <= 1, best == nil || d < best!.1 { best = (words[index], d) }
        }
        return best?.0
    }

    // Whether macOS's spell checker knows the word in any language Koe hears.
    private static var known: [String: Bool] = [:]
    private static let languages: [String] = {
        let available = Set(NSSpellChecker.shared.availableLanguages)
        return ["en", "fr", "de", "es", "it", "pt", "nl"].filter { available.contains($0) }
    }()

    static func isWord(_ word: String) -> Bool {
        let key = word.lowercased()
        if let answer = known[key] { return answer }
        let answer = languages.contains { language in
            NSSpellChecker.shared.checkSpelling(of: key, startingAt: 0, language: language, wrap: false,
                                                inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
        known[key] = answer
        return answer
    }

    // Lowercased, Latin accents removed.
    private static func plain(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
    }

    private static func splitPunctuation(_ word: String) -> (String, String) {
        let trailing = word.reversed().prefix { $0.isPunctuation }
        return (String(word.dropLast(trailing.count)), String(trailing.reversed()))
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count), current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
