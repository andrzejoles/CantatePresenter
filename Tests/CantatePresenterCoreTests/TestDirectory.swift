import Foundation

/// Tymczasowy katalog danych dla testów; nigdy nie dotyka prawdziwego `data/`.
struct TestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CantatePresenterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }

    func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: file(name))
    }

    func contents(of name: String) throws -> Data {
        try Data(contentsOf: file(name))
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
