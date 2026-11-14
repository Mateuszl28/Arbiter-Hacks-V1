import Foundation

extension Decimal {
    /// Formats a deposit in its own currency.
    ///
    /// Lives in the model layer rather than alongside the views because Siri speaks these
    /// amounts too, and the spoken answer must match what the screen shows exactly.
    func formattedCurrency(code: String?) -> String {
        guard let code else { return "\(self)" }
        return formatted(.currency(code: code).precision(.fractionLength(2)))
    }
}
