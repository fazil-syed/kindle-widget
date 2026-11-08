#!/usr/bin/swift

// kindle-progress — reads Amazon Kindle's local reading-state file and prints
// either human-readable text (default) or JSON (--json).
//
// Data source: ~/Library/Group Containers/group.com.amazon.Lassen/KindleToday_v1.dat
// (updated live by the Kindle 7.x Mac app).

import Foundation

// MARK: - Archive reading

// Strategy: plutil converts the keyed archive to XML, we rename CF$UID →
// CFXUID so PropertyListSerialization hands back plain Swift dictionaries
// instead of opaque CF types, then walk the $objects graph ourselves.

let json = CommandLine.arguments.contains("--json")

let dataPath = NSString(string: "~/Library/Group Containers/group.com.amazon.Lassen/KindleToday_v1.dat").expandingTildeInPath

struct Book: Codable {
    var title: String
    var author: String      // recovered from the "Title by Author" string
    var bookId: String
    var currentLocation: Int
    var maxLocation: Int
    var percent: Double
    var coverPNGbytes: Int
}

guard FileManager.default.fileExists(atPath: dataPath) else {
    print(json ? "{\"error\":\"no data file\"}" : "No Kindle data file. Is the Kindle app installed and launched?")
    exit(1)
}

do {
    // Write to a temp file, not a pipe: reading a pipe only after
    // waitUntilExit deadlocks when output exceeds the 64 KB buffer.
    let tmpPath = NSTemporaryDirectory() + "kindle-widget-archive-\(getuid()).xml"
    try? FileManager.default.removeItem(atPath: tmpPath)
    let plutil = Process()
    plutil.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
    plutil.arguments = ["-convert", "xml1", "-o", tmpPath, dataPath]
    let errPipe = Pipe()
    plutil.standardError = errPipe

    try plutil.run()
    plutil.waitUntilExit()
    guard plutil.terminationStatus == 0 else {
        print("plutil failed (status \(plutil.terminationStatus))")
        exit(1)
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: tmpPath))
    try? FileManager.default.removeItem(atPath: tmpPath)

    var xmlString = String(decoding: data, as: UTF8.self)
    if xmlString.contains("CF$UID") { xmlString = xmlString.replacingOccurrences(of: "CF$UID", with: "CFXUID") }

    let parsed = try PropertyListSerialization.propertyList(
        from: Data(xmlString.utf8), options: [], format: nil)
    guard let root = parsed as? [String: Any],
          let objects = root["$objects"] as? [Any],
          let top = root["$top"] as? [String: Any],
          let rootRef = top["root"] as? [String: Any],
          let _ = rootRef["CFXUID"] as? Int ?? (rootRef["CFXUID"] as? NSNumber)?.intValue else {
        print("Unexpected archive shape")
        exit(1)
    }

    func resolve(_ node: Any) -> Any {
        if let ref = node as? [String: Any], let uid = (ref["CFXUID"] as? NSNumber)?.intValue, uid < objects.count {
            return resolve(objects[uid])
        }
        if let dict = node as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict where k != "$class" { out[k] = resolve(v) }
            return out
        }
        if let arr = node as? [Any] { return arr.map(resolve) }
        return node
    }

    func unwrapArray(_ node: Any) -> Any {
        if let dict = node as? [String: Any], let objs = dict["NS.objects"] {
            return unwrapArray(objs)
        }
        if let arr = node as? [Any] { return arr.map(unwrapArray) }
        return node
    }

    let tree = resolve(rootRef)
    guard let rawItems = (tree as? [String: Any])?["KindleTodayItemListKey"],
          let items = unwrapArray(rawItems) as? [[String: Any]] else {
        print(json ? "[]" : "")
        exit(0)
    }

    var books: [Book] = []
    for item in items {
        let rawTitle = item["KindleTodayItemTitle"] as? String ?? "?"
        let bookId = item["KindleTodayItemBookId"] as? String ?? "?"
        let current = (item["KindleTodayItemCurrentLocation"] as? NSNumber)?.intValue ?? 0
        let max = (item["KindleTodayItemMaxLocation"] as? NSNumber)?.intValue ?? 0

        // Kindle stores "Book Title by Author Name" as the title; split it.
        var title = rawTitle, author = ""
        if let marker = rawTitle.range(of: " by ") {
            title = String(rawTitle[rawTitle.startIndex..<marker.lowerBound])
            author = String(rawTitle[marker.upperBound...])
        }
        // Personal docs: the author field is the import filename
        // ("Mark Manson (z-lib.org).epub") — strip extensions and trailing
        // parentheticals repeatedly until stable.
        if author.range(of: "\\.(epub|pdf|mobi|azw3?)$", options: [.regularExpression, .caseInsensitive]) != nil {
            var cleaned = author
            repeat {
                let prev = cleaned
                cleaned = cleaned.replacingOccurrences(
                    of: "\\.(epub|pdf|mobi|azw3?)$", with: "",
                    options: [.regularExpression, .caseInsensitive])
                cleaned = cleaned.replacingOccurrences(
                    of: "\\s*\\([^)]*\\)\\s*$", with: "",
                    options: [.regularExpression, .caseInsensitive])
                if cleaned == prev { break }
            } while true
            author = cleaned
        }

        let pct = max > 0 ? Double(current) / Double(max) * 100 : 0
        books.append(Book(
            title: title,
            author: author,
            bookId: bookId,
            currentLocation: current,
            maxLocation: max,
            percent: (pct * 10).rounded() / 10,
            coverPNGbytes: ((item["KindleTodayItemCover"] as? [String: Any])
                .flatMap { $0["NS.data"] as? Data })?.count ?? 0
        ))
    }

    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(books), encoding: .utf8) ?? "[]")
    } else {
        let fmt = NumberFormatter()
        fmt.maximumFractionDigits = 1
        for b in books {
            print(b.title)
            print("  author: \(b.author)")
            print("  percent: \(fmt.string(from: NSNumber(value: b.percent)) ?? "0")%")
            print("  location: \(b.currentLocation) / \(b.maxLocation)")
        }
    }
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
