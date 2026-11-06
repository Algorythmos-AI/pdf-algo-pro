import Testing

@testable import PDFAlgoPro

/// The storefront row in the internal tools says where StoreKit's prices come from, so a TestFlight
/// run can tell a storefront mismatch in StoreKit from one in the app.
@Suite("The storefront row's words")
struct StorefrontSummaryTests {
  @Test("names the storefront and the currency of the plans")
  func storefrontAndCurrency() {
    let summary = StorefrontSummary(storefront: "AUS", currencies: ["USD"], expectedProducts: 2, loadedProducts: 2)
    #expect(summary.text == "AUS, prices in USD")
  }

  @Test("lists every currency when the plans disagree")
  func mixedCurrencies() {
    let summary = StorefrontSummary(
      storefront: "AUS", currencies: ["AUD", "USD"], expectedProducts: 2, loadedProducts: 2)
    #expect(summary.text == "AUS, prices in AUD, USD")
  }

  @Test("says when only some plans loaded")
  func partialLoad() {
    let summary = StorefrontSummary(storefront: "USA", currencies: ["USD"], expectedProducts: 2, loadedProducts: 1)
    #expect(summary.text == "USA, prices in USD, 1 of 2 plans")
  }

  @Test("says when no plans loaded and the storefront is unknown")
  func nothingLoaded() {
    let summary = StorefrontSummary(storefront: nil, currencies: [], expectedProducts: 2, loadedProducts: 0)
    #expect(summary.text == "unknown, no plans loaded")
  }
}
