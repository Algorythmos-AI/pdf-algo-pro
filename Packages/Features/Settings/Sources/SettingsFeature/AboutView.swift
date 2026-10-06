import DesignSystem
import SwiftUI

/// About: the app's mark and version, its public pages, a way to share it, and who makes it.
///
/// App Review expects the privacy policy to be reachable in the app; it is here, one row from
/// Settings. Every link hands an address to the system, which opens it in the browser; the app itself
/// makes no request.
public struct AboutView: View {
  @Environment(\.locale) private var locale
  private let version: String

  /// Creates About; `version` is the app's version and build.
  public init(version: String) {
    self.version = version
  }

  /// The screen.
  public var body: some View {
    Form {
      Section {
        VStack(spacing: Spacing.s100) {
          AppMark(side: 88)
          Text(verbatim: "PDF Algo Pro")
            .font(.title2.bold())
            .foregroundStyle(Color.ds.labelPrimary)
            .accessibilityAddTraits(.isHeader)
          Text("Version \(version)", bundle: .module)
            .font(.subheadline)
            .foregroundStyle(Color.ds.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("about.version")
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }
      Section {
        Link(destination: link(.privacyPolicy)) {
          TileLabel(Text("Privacy Policy", bundle: .module), systemImage: "hand.raised")
        }
        .accessibilityIdentifier("settings.privacyPolicy")
        Link(destination: link(.termsOfUse)) {
          TileLabel(Text("Terms of Use", bundle: .module), systemImage: "doc.plaintext")
        }
        .accessibilityIdentifier("settings.termsOfUse")
        Link(destination: link(.support)) {
          TileLabel(Text("Support", bundle: .module), systemImage: "questionmark.circle")
        }
        .accessibilityIdentifier("settings.support")
      } footer: {
        Text("These open in your browser.", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
      }
      Section {
        ShareLink(item: AppLinks.product(languageCode: languageCode)) {
          TileLabel(Text("Share PDF Algo Pro", bundle: .module), systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("settings.share")
      }
      Section {
        Link(destination: AppLinks.company) {
          HStack(spacing: Spacing.s150) {
            CompanyMark(side: 40)
            VStack(alignment: .leading, spacing: Spacing.s0) {
              Text("Built by Algorythmos", bundle: .module).foregroundStyle(Color.ds.labelPrimary)
              Text(verbatim: "algorythmos.com").font(.footnote).foregroundStyle(Color.ds.labelSecondary)
            }
          }
          .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("settings.company")
      } footer: {
        Text("PDF Algo Pro is published by Algorythmos Pty Ltd.", bundle: .module)
          .foregroundStyle(Color.ds.labelSecondary)
      }
    }
    .navigationTitle(Text("About", bundle: .module))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var languageCode: String? { locale.language.languageCode?.identifier }

  /// A public page's address in the language the app is shown in.
  private func link(_ page: AppLinks) -> URL {
    page.url(languageCode: languageCode)
  }
}
