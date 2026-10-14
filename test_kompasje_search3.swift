import Foundation

let semaphore = DispatchSemaphore(value: 0)
let query = "Barka"
let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
let url = URL(string: "https://kompasje.pl/?s=\(encoded)")!
var req = URLRequest(url: url)
req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

URLSession.shared.dataTask(with: req) { data, res, err in
    if let data = data, let html = String(data: data, encoding: .utf8) {
        if let idx = html.range(of: "https://kompasje.pl/piosenki-religijne") {
            let start = idx.lowerBound
            let end = html.index(start, offsetBy: 300, limitedBy: html.endIndex) ?? html.endIndex
            print("Found url:\n\(html[start..<end])")
        } else {
            print("Not found, let's search for just 'barka':")
            let ranges = html.ranges(of: "barka", options: .caseInsensitive)
            print("Occurrences of barka: \(ranges.count)")
            for r in ranges.prefix(3) {
                let s = html.index(r.lowerBound, offsetBy: -50, limitedBy: html.startIndex) ?? html.startIndex
                let e = html.index(r.upperBound, offsetBy: 100, limitedBy: html.endIndex) ?? html.endIndex
                print("Context: \(html[s..<e])")
            }
        }
    }
    semaphore.signal()
}.resume()
semaphore.wait()
