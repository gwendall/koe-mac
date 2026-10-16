import AppKit
import CoreText

// The words in each language: every <language>.lproj in
// the app says what the English one does, with the same blanks (%@ and %d, in
// order or numbered), nothing the house style refuses, and pill titles every
// letter of which the pixel font (or the language's face) can draw.
extension SelfTest {
    static func languages() {
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        func table(_ language: String, _ name: String = "Localizable") -> [String: String] {
            let url = resources.appendingPathComponent("\(language).lproj/\(name).strings")
            guard let data = try? Data(contentsOf: url) else { return [:] }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String] ?? [:]
        }
        let languages = ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? [])
            .filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(".lproj".count)) }.sorted()
        let english = table("en")
        let listed = Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String] ?? []
        check(languages.count == 10 && Set(listed) == Set(languages), "languages: Info.plist lists the ones Koe speaks (\(languages.joined(separator: " ")))")
        check(!english.isEmpty && english.allSatisfy { $0.key == $0.value }, "languages: English says its keys (\(english.count) lines)")

        // What Words.say gets from a variable, out of reach of scripts/strings-check.sh.
        let variable = Shortcut.modifierKeys.values.map(\.label) + ["Space"]
        let unknown = variable.filter { english[$0] == nil }.sorted()
        check(unknown.isEmpty, "languages: the shortcut's key names are in English \(unknown)")

        for language in languages {
            let words = table(language)
            let missing = Set(english.keys).subtracting(words.keys), extra = Set(words.keys).subtracting(english.keys)
            check(missing.isEmpty && extra.isEmpty, "\(language) says what English does, no more: missing \(missing.sorted()), extra \(extra.sorted())")
            let blanked = words.filter { blanks($0.key) != blanks($0.value) }.keys.sorted()
            check(blanked.isEmpty, "\(language) keeps the blanks: \(blanked)")
            let microphone = table(language, "InfoPlist")["NSMicrophoneUsageDescription"] ?? ""
            check(!microphone.isEmpty && microphone.contains("fn"), "\(language) says why Koe asks for the microphone")
            let refused = (Array(words.values) + [microphone]).filter { $0.contains { "\"\\\u{2014}\u{2013}".contains($0) } }.sorted()
            check(refused.isEmpty, "\(language) has no straight double quote, backslash or long dash: \(refused)")
            if language == "fr" {
                // A no-break space before : and a narrow one before ; ? !, never a plain one.
                let plain = (Array(words.values) + [microphone]).filter { $0.range(of: #" [:;?!]"#, options: .regularExpression) != nil }.sorted()
                check(plain.isEmpty, "fr: no plain space before : ; ? ! \(plain)")
            }
        }

        // The pills' titles: Silkscreen's capitals in the Latin languages (it
        // has no ẞ, so German titles write SS), the language's face for the rest.
        check((CTFontCopyPostScriptName(TitleFont.silkscreen) as String).contains("Silkscreen"), "languages: the pixel font loads")
        let titles = english.keys.filter { $0 == $0.uppercased() && $0.contains(where: \.isLetter) }.sorted()
        for language in languages {
            let words = table(language)
            let unfit = titles.map { (words[$0] ?? $0).replacingOccurrences(of: "%@", with: "2.0.0") }.filter { title in
                title != title.uppercased() || TitleFont.letters(title, language: language).contains { letter in
                    !letter.text.allSatisfy(\.isWhitespace)
                        && (TitleFont.faces[language] == nil ? !letter.silkscreen : !TitleFont.has(letter.font, letter.text))
                }
            }
            check(unfit.isEmpty, "\(language): the \(titles.count) pill titles have their letters \(unfit)")
        }
        let installed = Set(CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? [])
        for (language, face) in TitleFont.faces.sorted(by: { $0.key < $1.key }) {
            check(installed.contains(face), "\(language): the title face \(face) is on the Mac")
        }
    }

    // A line's blanks, numbered as String(format:) reads them: "1@", "2d".
    private static func blanks(_ text: String) -> [String] {
        let blank = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGcCsSp%])"#)
        var next = 0
        return blank.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let kind = (text as NSString).substring(with: match.range(at: 2))
            guard kind != "%" else { return nil }
            next += 1
            let number = match.range(at: 1).location == NSNotFound ? next : Int((text as NSString).substring(with: match.range(at: 1))) ?? 0
            return "\(number)\(kind)"
        }.sorted()
    }
}
