import Foundation

extension URLComponents {
    /// Sets `queryItems` with a literal `+` percent-encoded.
    ///
    /// `URLComponents` leaves `+` as is (it is legal in a query), but servers and form decoding
    /// read it as a space: `sort=+pricePerSquareMeter` arrived as ` pricePerSquareMeter` and the
    /// API answered 400, and an E.164 phone (`+5521…`) would lose its sign the same way.
    mutating func setQueryItemsEncodingPlus(_ items: [URLQueryItem]) {
        queryItems = items
        percentEncodedQuery = percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
}
