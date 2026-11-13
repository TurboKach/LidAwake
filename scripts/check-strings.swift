// Checks that Localization/Localizable.xcstrings and the L("…") calls in
// LidAwake.swift agree. Run from the repository root through check-strings.sh.
import Foundation

let sourcePath = "LidAwake.swift"
let catalogPath = "Localization/Localizable.xcstrings"

var violations: [String] = []

func fail(_ file: String, _ line: Int?, _ message: String) {
    violations.append(line.map { "\(file):\($0): \(message)" } ?? "\(file): \(message)")
}

func shown(_ key: String) -> String {
    let text = key.count > 60 ? String(key.prefix(60)) + "…" : key
    return text.debugDescription
}

// "%@" count of a text, and every other "%" sequence in it.
func specifiers(_ text: String) -> (objects: Int, foreign: [String]) {
    let scalars = Array(text.unicodeScalars)
    var objects = 0
    var foreign: [String] = []
    var i = 0
    while i < scalars.count {
        if scalars[i] == "%" {
            if i + 1 < scalars.count, scalars[i + 1] == "@" {
                objects += 1
            } else {
                foreign.append(i + 1 < scalars.count ? "%" + String(scalars[i + 1]) : "%")
            }
            i += 1
        }
        i += 1
    }
    return (objects, foreign)
}

// MARK: catalog

guard let catalogData = FileManager.default.contents(atPath: catalogPath),
      let catalogRoot = (try? JSONSerialization.jsonObject(with: catalogData)) as? [String: Any],
      let catalog = catalogRoot["strings"] as? [String: Any] else {
    print("check-strings: cannot read \(catalogPath)")
    exit(2)
}

func unit(_ key: String, _ language: String) -> (value: String?, state: String?) {
    let entry = catalog[key] as? [String: Any]
    let localizations = entry?["localizations"] as? [String: Any]
    let languageEntry = localizations?[language] as? [String: Any]
    let stringUnit = languageEntry?["stringUnit"] as? [String: Any]
    return (stringUnit?["value"] as? String, stringUnit?["state"] as? String)
}

var objectCount: [String: Int] = [:]
for key in catalog.keys.sorted() {
    let name = shown(key)
    var values: [String: String] = [:]
    for language in ["en", "ru"] {
        let found = unit(key, language)
        guard let value = found.value, !value.isEmpty else {
            fail(catalogPath, nil, "key \(name): missing or empty \(language) value")
            continue
        }
        values[language] = value
        if found.state != "translated" {
            fail(catalogPath, nil, "key \(name): \(language) state is \(found.state ?? "missing"), expected translated")
        }
    }
    if let en = values["en"], en != key {
        fail(catalogPath, nil, "key \(name): en value differs from the key")
    }
    let inKey = specifiers(key)
    objectCount[key] = inKey.objects
    if let foreign = inKey.foreign.first {
        fail(catalogPath, nil, "key \(name): format specifier \(foreign) is not allowed (only %@)")
    }
    if let ru = values["ru"] {
        let inRu = specifiers(ru)
        if inRu.objects != inKey.objects {
            fail(catalogPath, nil, "key \(name): ru has \(inRu.objects) %@, the key has \(inKey.objects)")
        }
        if let foreign = inRu.foreign.first {
            fail(catalogPath, nil, "key \(name): ru uses format specifier \(foreign) (only %@ is allowed)")
        }
    }
}

// MARK: source

guard let sourceText = try? String(contentsOfFile: sourcePath, encoding: .utf8) else {
    print("check-strings: cannot read \(sourcePath)")
    exit(2)
}
let src = Array(sourceText.unicodeScalars)

struct Call {
    let line: Int
    let key: String?
    let arguments: Int
}
var calls: [Call] = []
var callCount = 0

func line(_ i: Int) -> Int { src[..<i].filter { $0 == "\n" }.count + 1 }

func startsWith(_ text: String, at i: Int) -> Bool {
    let scalars = Array(text.unicodeScalars)
    return i + scalars.count <= src.count && Array(src[i..<i + scalars.count]) == scalars
}

func isIdentifier(_ c: Unicode.Scalar) -> Bool { c == "_" || CharacterSet.alphanumerics.contains(c) }

func isWhitespace(_ c: Unicode.Scalar) -> Bool { CharacterSet.whitespacesAndNewlines.contains(c) }

func nextNonWhitespace(_ from: Int) -> Int {
    var i = from
    while i < src.count, isWhitespace(src[i]) { i += 1 }
    return i
}

// True when src[i] starts a string literal: optional #s, then ".
func startsString(_ i: Int) -> Bool {
    var j = i
    while j < src.count, src[j] == "#" { j += 1 }
    return j < src.count && src[j] == "\""
}

// Returns the index after the string literal that starts at `start`.
func skipString(_ start: Int) -> Int {
    var i = start
    var hashes = 0
    while src[i] == "#" { hashes += 1; i += 1 }
    let multiline = startsWith("\"\"\"", at: i)
    i += multiline ? 3 : 1
    let hashText = String(repeating: "#", count: hashes)
    let close = (multiline ? "\"\"\"" : "\"") + hashText
    let escape = "\\" + hashText
    while i < src.count {
        if startsWith(close, at: i) { return i + close.unicodeScalars.count }
        if startsWith(escape, at: i) {
            i += escape.unicodeScalars.count
            if i < src.count, src[i] == "(" {
                i = scan(i + 1, nested: true).end
            }
            i += 1
            continue
        }
        i += 1
    }
    return i
}

// Scans code from `from`, skipping comments and strings and recording every L( call.
// With `nested`, stops at the unmatched ")" and returns its index and the number of
// top-level commas that are followed by something other than ")".
func scan(_ from: Int, nested: Bool) -> (end: Int, commas: Int) {
    var i = from
    var depth = 0
    var commas = 0
    while i < src.count {
        let c = src[i]
        if startsWith("//", at: i) {
            while i < src.count, src[i] != "\n" { i += 1 }
            continue
        }
        if startsWith("/*", at: i) {
            i += 2
            while i < src.count, !startsWith("*/", at: i) { i += 1 }
            i += 2
            continue
        }
        if startsString(i) {
            i = skipString(i)
            continue
        }
        if c == "L", i + 1 < src.count, src[i + 1] == "(", i == 0 || !isIdentifier(src[i - 1]) {
            i = call(at: i)
            continue
        }
        switch c {
        case "(", "[", "{":
            depth += 1
        case ")", "]", "}":
            if depth == 0, nested, c == ")" { return (i, commas) }
            depth -= 1
        case ",":
            if depth == 0, nested, nextNonWhitespace(i + 1) < src.count, src[nextNonWhitespace(i + 1)] != ")" { commas += 1 }
        default:
            break
        }
        i += 1
    }
    return (i, commas)
}

// Handles the L( at `i`; returns where scanning continues.
func call(at i: Int) -> Int {
    // The definition "func L(" is not a call.
    var back = i - 1
    while back >= 0, src[back] == " " { back -= 1 }
    if back >= 3, String(String.UnicodeScalarView(src[back - 3...back])) == "func" { return i + 2 }

    callCount += 1
    let ln = line(i)
    func reject(_ message: String) -> Int {
        fail(sourcePath, ln, message)
        calls.append(Call(line: ln, key: nil, arguments: 0))
        return i + 2
    }

    var j = i + 2
    var newlines = 0
    while j < src.count, isWhitespace(src[j]) {
        if src[j] == "\n" { newlines += 1 }
        j += 1
    }
    if newlines > 1 { return reject("the key literal must be on the same line as L( or the next line") }
    guard j < src.count, src[j] == "\"" else { return reject("the first argument of L( must be a plain \"…\" string literal") }
    if startsWith("\"\"\"", at: j) { return reject("a \"\"\" literal is not allowed as a key") }

    var key = String.UnicodeScalarView()
    j += 1
    while true {
        guard j < src.count, src[j] != "\n" else { return reject("unterminated key literal") }
        let c = src[j]
        if c == "\"" { break }
        if c == "\\" {
            guard j + 1 < src.count else { return reject("unterminated key literal") }
            switch src[j + 1] {
            case "n": key.append("\n")
            case "\"": key.append("\"")
            case "\\": key.append("\\")
            case "(": return reject("interpolation \\( is not allowed in a key literal")
            default: return reject("escape \\\(src[j + 1]) is not allowed in a key literal (only \\n, \\\" and \\\\)")
            }
            j += 2
        } else {
            key.append(c)
            j += 1
        }
    }
    j = nextNonWhitespace(j + 1)
    guard j < src.count else { return reject("unterminated L( call") }
    var arguments = 0
    var end = j + 1
    if src[j] == "," {
        let rest = scan(j + 1, nested: true)
        end = rest.end + 1
        if nextNonWhitespace(j + 1) < rest.end { arguments = 1 + rest.commas }
    } else if src[j] != ")" {
        return reject("the key literal must be the whole first argument")
    }
    calls.append(Call(line: ln, key: String(key), arguments: arguments))
    return end
}

_ = scan(0, nested: false)

var used = Set<String>()
for entry in calls {
    guard let key = entry.key else { continue }
    guard let expected = objectCount[key] else {
        fail(sourcePath, entry.line, "key \(shown(key)) is not in the catalog")
        continue
    }
    used.insert(key)
    if entry.arguments != expected {
        fail(sourcePath, entry.line, "key \(shown(key)) has \(expected) %@ but the call passes \(entry.arguments) value(s)")
    }
}
for key in catalog.keys.sorted() where !used.contains(key) {
    fail(catalogPath, nil, "key \(shown(key)) is not used by any L( call")
}

if violations.isEmpty {
    print("check-strings: OK, \(catalog.count) keys, \(callCount) call sites")
} else {
    for violation in violations { print(violation) }
    print("check-strings: \(violations.count) violation(s)")
    exit(1)
}
