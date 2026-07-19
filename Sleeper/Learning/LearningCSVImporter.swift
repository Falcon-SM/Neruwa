import Foundation

struct LearningCardImportRow: Sendable {
    let prompt: String
    let answer: String
    let speechText: String
    let languageCode: String
    let folderName: String
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
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .shiftJIS) else {
            throw LearningCSVImportError.unreadableText
        }

        let table = csvRows(from: text)
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
            rows.append(
                LearningCardImportRow(
                    prompt: prompt,
                    answer: answer,
                    speechText: spoken.isEmpty ? answer : spoken,
                    languageCode: normalizedLanguageCode(language),
                    folderName: normalizedFolder(folder, fallback: defaultFolderName)
                )
            )
        }

        guard !rows.isEmpty else { throw LearningCSVImportError.noValidCards }
        return LearningCardImportResult(rows: rows, skippedRows: skippedRows)
    }

    private static let promptHeaders: Set<String> = ["prompt", "question", "word", "問題", "単語"]
    private static let answerHeaders: Set<String> = ["answer", "meaning", "答え", "意味"]
    private static let speechHeaders: Set<String> = ["speech", "speechtext", "読み上げ", "音声"]
    private static let languageHeaders: Set<String> = ["language", "languagecode", "lang", "言語"]
    private static let folderHeaders: Set<String> = ["folder", "foldername", "deck", "フォルダ", "デッキ"]

    nonisolated private static func normalizedHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func firstIndex(in headers: [String], matching candidates: Set<String>) -> Int? {
        headers.firstIndex(where: candidates.contains)
    }

    private static func value(at index: Int, in row: [String]) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLanguageCode(_ value: String) -> String {
        switch value.lowercased() {
        case "en", "english", "英語", "en-us": "en-US"
        case "ja", "japanese", "日本語", "ja-jp", "": "ja-JP"
        default: String(value.prefix(20))
        }
    }

    private static func normalizedFolder(_ value: String, fallback: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((normalized.isEmpty ? (fallback.isEmpty ? "CSVインポート" : fallback) : normalized).prefix(40))
    }

    private static func csvRows(from text: String) -> [[String]] {
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
            } else if character == ",", !isQuoted {
                finishField()
            } else if character == "\n", !isQuoted {
                finishRow()
            } else if character != "\r" || isQuoted {
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
