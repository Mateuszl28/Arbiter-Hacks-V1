import Foundation
import SwiftData

// Cuts a fixture store in the PRE-take-back shape, so the migration check exercises a
// real old-schema -> new-schema upgrade. Writing the fixture with today's model, as a
// first attempt did, tests nothing: the schemas match by construction.

let output = ProcessInfo.processInfo.environment["BINMATE_FIXTURE"]
    ?? "Tools/Fixtures/history-legacy.store"

let outputURL = URL(fileURLWithPath: output)
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
)
for suffix in ["", "-shm", "-wal"] {
    try? FileManager.default.removeItem(atPath: output + suffix)
}

let container = try ModelContainer(
    for: ScanRecord.self,
    configurations: ModelConfiguration(url: outputURL)
)
let context = ModelContext(container)

// Components encoded exactly as the real app writes them.
let bottleJSON = """
[{"material":"en:pet-1-polyethylene-terephthalate","shape":"en:bottle","numberOfUnits":1},
 {"material":"en:pp-5-polypropylene","shape":"en:lid-or-cap","numberOfUnits":1},
 {"material":"en:paper","shape":"en:label","numberOfUnits":1}]
""".data(using: .utf8)!
let boxJSON = """
[{"material":"en:cardboard","shape":"en:box","numberOfUnits":1}]
""".data(using: .utf8)!

context.insert(ScanRecord(
    scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
    barcode: "5449000000996", productName: "Cola, 500 ml bottle", brand: "Sample",
    cityID: "de-berlin", cityName: "Berlin",
    componentsJSON: bottleJSON, originRaw: "offlineSample"
))
context.insert(ScanRecord(
    scannedAt: Date(timeIntervalSince1970: 1_700_086_400),
    barcode: nil, productName: "Cardboard box", brand: nil,
    cityID: "pl-krakow", cityName: "Kraków",
    componentsJSON: boxJSON, originRaw: "manual"
))
try context.save()

print("Wrote \(try context.fetchCount(FetchDescriptor<ScanRecord>())) legacy record(s) to \(output)")
