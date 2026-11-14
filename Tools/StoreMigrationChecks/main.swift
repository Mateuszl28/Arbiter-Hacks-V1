import Foundation
import SwiftData

// Opens a history store written by an earlier build and checks the records are still
// there, still readable, and still mean what they meant.
//
// This exists because development history vanished during a schema change and nothing
// noticed: every suite stayed green, and an empty history screen is indistinguishable
// from a fresh install. The cause was never pinned down — the obvious candidate, adding
// a non-optional `UUID`, migrates cleanly when tested here — so this guards the property
// that actually matters rather than one suspected mechanism: a build must be able to
// read history written by an earlier build.
//
// The fixture is cut from the pre-change schema by Tools/LegacyFixtureBuilder, not by
// today's model. A fixture written by the same code that reads it proves nothing.

let fixture = ProcessInfo.processInfo.environment["BINMATE_FIXTURE"]
    ?? "Tools/Fixtures/history.store"

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("  FAIL: \(message)")
    }
}

guard FileManager.default.fileExists(atPath: fixture) else {
    print("FAIL: no fixture store at \(fixture). Rebuild it with Tools/rebuild-store-fixture.sh")
    exit(1)
}

// Work on a copy: opening a store can migrate it in place, and the fixture must stay as
// it was committed or the next run would be testing its own output.
let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("binmate-store-check-\(getpid())")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

let working = scratch.appendingPathComponent("history.store")
try FileManager.default.copyItem(at: URL(fileURLWithPath: fixture), to: working)
for suffix in ["-shm", "-wal"] {
    let sidecar = fixture + suffix
    if FileManager.default.fileExists(atPath: sidecar) {
        try? FileManager.default.copyItem(
            at: URL(fileURLWithPath: sidecar),
            to: scratch.appendingPathComponent("history.store" + suffix)
        )
    }
}

print("Opening fixture store with today's model…")

let container = try ModelContainer(
    for: ScanRecord.self,
    configurations: ModelConfiguration(url: working)
)
let context = ModelContext(container)

let records = try context.fetch(
    FetchDescriptor<ScanRecord>(sortBy: [SortDescriptor(\.scannedAt)])
)

print("Records read back: \(records.count)")
for record in records {
    print("  \(record.displayTitle) — \(record.cityName), \(record.components.count) part(s)")
}

// The headline check: an existing user's history survives.
check(records.count == 2, "expected 2 records from the fixture, got \(records.count)")

guard records.count == 2 else {
    print("\n\(failures) check(s) FAILED — a schema change has dropped existing history.")
    exit(1)
}

// Every field has to come back intact, not merely the row count. A migration that
// preserved rows but blanked a column would be just as bad.
let bottle = records[0]
check(bottle.productName == "Cola, 500 ml bottle", "product name should survive, got '\(bottle.productName)'")
check(bottle.brand == "Sample", "brand should survive")
check(bottle.barcode == "5449000000996", "barcode should survive")
check(bottle.cityID == "de-berlin", "city id should survive")
check(bottle.cityName == "Berlin", "city name should survive")
check(bottle.origin == .offlineSample, "origin should survive")
check(bottle.components.count == 3, "all three components should survive, got \(bottle.components.count)")
check(
    bottle.components.first?.material == "en:pet-polyethylene-terephthalate",
    "component materials should survive"
)
check(
    bottle.scannedAt == Date(timeIntervalSince1970: 1_700_000_000),
    "the timestamp should survive exactly"
)

let box = records[1]
check(box.productName == "Cardboard box", "the second record should survive too")
check(box.barcode == nil, "a nil barcode should stay nil rather than becoming empty")
check(box.cityID == "pl-krakow", "the second record's city should survive")

// Attributes added since the fixture was cut must read as their default rather than
// breaking the open — that is exactly what a safe lightweight migration looks like.
check(bottle.returnedAt == nil, "returnedAt was added after the fixture and should default to nil")

// The store must still be writable afterwards, not left read-only or wedged.
box.returnedAt = Date(timeIntervalSince1970: 1_700_100_000)
try context.save()
let reread = try context.fetch(FetchDescriptor<ScanRecord>())
check(
    reread.contains { $0.returnedAt != nil },
    "the migrated store should still accept writes"
)

print(failures == 0
      ? "\nAll store checks passed — existing history survives today's schema."
      : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
