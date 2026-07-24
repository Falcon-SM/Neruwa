import Foundation

struct LearningCardImportRow: Sendable {
    let prompt: String
    let answer: String
    let speechText: String
    let languageCode: String
    let folderName: String
    let brailleCells: [[Int]]?
}

struct LearningCardImportResult: Sendable {
    let rows: [LearningCardImportRow]
    let skippedRows: Int
}

enum LearningCSVImportError: LocalizedError {
    case unreadableText
    case missingColumns
    case noValidCards

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            "CSVをUTF-8またはShift_JISの文字列として読み込めませんでした。"
        case .missingColumns:
            "CSVには問題と答えの2列が必要です。"
        case .noValidCards:
            "追加できる学習カードがCSVにありませんでした。"
        }
    }
}

enum LearningCSVImporter {
    static func parse(
        data: Data,
        defaultFolderName: String
    ) throws -> LearningCardImportResult {
        guard let decodedText = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .shiftJIS) else {
            throw LearningCSVImportError.unreadableText
        }
        let text = decodedText.replacingOccurrences(of: "\u{FEFF}", with: "")

        let delimiter = detectedDelimiter(in: text)
        let table = csvRows(from: text, delimiter: delimiter)
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard let first = table.first, first.count >= 2 else {
            throw LearningCSVImportError.missingColumns
        }

        let headers = first.map(normalizedHeader)
        let hasHeader = headers.contains(where: promptHeaders.contains)
            && headers.contains(where: answerHeaders.contains)
        let dataRows = hasHeader ? Array(table.dropFirst()) : table

        let promptIndex = hasHeader ? firstIndex(in: headers, matching: promptHeaders) ?? 0 : 0
        let answerIndex = hasHeader ? firstIndex(in: headers, matching: answerHeaders) ?? 1 : 1
        let speechIndex = hasHeader ? firstIndex(in: headers, matching: speechHeaders) : 2
        let languageIndex = hasHeader ? firstIndex(in: headers, matching: languageHeaders) : 3
        let folderIndex = hasHeader ? firstIndex(in: headers, matching: folderHeaders) : 4
        let brailleIndex = hasHeader ? firstIndex(in: headers, matching: brailleHeaders) : 5

        var rows: [LearningCardImportRow] = []
        var skippedRows = 0
        for row in dataRows {
            let prompt = value(at: promptIndex, in: row)
            let answer = value(at: answerIndex, in: row)
            guard !prompt.isEmpty, !answer.isEmpty else {
                skippedRows += 1
                continue
            }

            let spoken = speechIndex.map { value(at: $0, in: row) } ?? ""
            let language = languageIndex.map { value(at: $0, in: row) } ?? ""
            let folder = folderIndex.map { value(at: $0, in: row) } ?? ""
            let resolvedSpeech = spoken.isEmpty ? answer : spoken
            let braille = brailleIndex
                .map { value(at: $0, in: row) }
                .flatMap(parseBrailleCells)
            rows.append(
                LearningCardImportRow(
                    prompt: prompt,
                    answer: answer,
                    speechText: resolvedSpeech,
                    languageCode: normalizedLanguageCode(
                        language,
                        speechText: resolvedSpeech
                    ),
                    folderName: normalizedFolder(folder, fallback: defaultFolderName),
                    brailleCells: braille
                )
            )
        }

        guard !rows.isEmpty else { throw LearningCSVImportError.noValidCards }
        return LearningCardImportResult(rows: rows, skippedRows: skippedRows)
    }

    private static let promptHeaders: Set<String> = [
        "prompt", "question", "word", "term", "front", "問題", "単語", "表", "表面", "おもて"
    ]
    private static let answerHeaders: Set<String> = [
        "answer", "meaning", "definition", "back", "答え", "意味", "裏", "裏面", "うら"
    ]
    private static let speechHeaders: Set<String> = [
        "speech", "speechtext", "pronunciation", "reading", "読み上げ", "音声", "発音", "読み"
    ]
    private static let languageHeaders: Set<String> = ["language", "languagecode", "lang", "言語"]
    private static let folderHeaders: Set<String> = [
        "folder", "foldername", "deck", "category", "フォルダ", "デッキ", "分類"
    ]
    private static let brailleHeaders: Set<String> = [
        "braille", "braillecells", "dots", "dotnumbers", "点字", "点番号"
    ]

    nonisolated private static func normalizedHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func firstIndex(in headers: [String], matching candidates: Set<String>) -> Int? {
        headers.firstIndex(where: candidates.contains)
    }

    private static func value(at index: Int, in row: [String]) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLanguageCode(
        _ value: String,
        speechText: String
    ) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return switch normalized {
        case "en", "english", "英語", "en-us", "enus": "en-US"
        case "en-gb", "engb": "en-GB"
        case "ja", "japanese", "日本語", "ja-jp", "jajp": "ja-JP"
        case "":
            inferredLanguageCode(for: speechText)
        default:
            String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        }
    }

    private static func inferredLanguageCode(for speechText: String) -> String {
        let scalars = speechText.unicodeScalars
        let hasJapanese = scalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value)
        }
        let hasLatinLetter = scalars.contains { scalar in
            (0x0041...0x005A).contains(scalar.value)
                || (0x0061...0x007A).contains(scalar.value)
        }
        return hasLatinLetter && !hasJapanese ? "en-US" : "ja-JP"
    }

    private static func normalizedFolder(_ value: String, fallback: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((normalized.isEmpty ? (fallback.isEmpty ? "CSVインポート" : fallback) : normalized).prefix(40))
    }

    private static func parseBrailleCells(_ value: String) -> [[Int]]? {
        let unicodeCells = value.unicodeScalars.compactMap { scalar -> [Int]? in
            guard (0x2800...0x283F).contains(scalar.value) else { return nil }
            let bitMask = scalar.value - 0x2800
            let dots = (1...6).filter { dot in
                bitMask & (1 << (dot - 1)) != 0
            }
            return dots.isEmpty ? nil : dots
        }
        if !unicodeCells.isEmpty {
            return unicodeCells
        }

        let cells = value
            .split(whereSeparator: { $0 == "|" || $0 == "/" || $0 == ";" })
            .compactMap { component -> [Int]? in
                let dots = Array(
                    Set(component.compactMap { character in
                        character.wholeNumberValue.flatMap {
                            (1...6).contains($0) ? $0 : nil
                        }
                    })
                )
                .sorted()
                return dots.isEmpty ? nil : dots
            }
        return cells.isEmpty ? nil : cells
    }

    private static func detectedDelimiter(in text: String) -> Character {
        let candidates: [Character] = [",", "\t", ";"]
        var counts = Dictionary(uniqueKeysWithValues: candidates.map { ($0, 0) })
        var isQuoted = false

        for character in text {
            if character == "\"" {
                isQuoted.toggle()
            } else if character.isNewline, !isQuoted {
                break
            } else if !isQuoted, counts[character] != nil {
                counts[character, default: 0] += 1
            }
        }

        var selected: Character = ","
        var selectedCount = 0
        for candidate in candidates {
            let count = counts[candidate, default: 0]
            if count > selectedCount {
                selected = candidate
                selectedCount = count
            }
        }
        return selected
    }

    private static func csvRows(
        from text: String,
        delimiter: Character
    ) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = text.startIndex

        func finishField() {
            row.append(field)
            field = ""
        }
        func finishRow() {
            finishField()
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\"" {
                if isQuoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                isQuoted.toggle()
            } else if character == delimiter, !isQuoted {
                finishField()
            } else if character.isNewline, !isQuoted {
                finishRow()
            } else {
                field.append(character)
            }
            index = next
        }
        if !field.isEmpty || !row.isEmpty {
            finishRow()
        }
        return rows
    }
}
