// Port of the startup part of src/Program.cs: the log comes first so that everything after it,
// including a crash, leaves a trace in alive.log.
import Foundation
import AliveCore

enum Startup {
    /// Truncates alive.log and installs the uncaught-exception logger. Call once, before any model
    /// is created.
    static func begin() {
        Diag.start()
        Diag.info("Alive for Mac starting, data folder \(AppHome.path)")
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(24).joined(separator: "\n    ")
            Diag.info("UNCAUGHT EXCEPTION \(exception.name.rawValue): \(exception.reason ?? "?")\n    \(stack)")
        }
    }
}
