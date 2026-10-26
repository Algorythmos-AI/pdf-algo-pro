#if canImport(SwiftUI) && canImport(UIKit)
  import SwiftUI
  import UIKit

  /// Draws a SwiftUI view off screen, for the tests that check a screen draws.
  ///
  /// Each renderer is kept until the tests end, never released. On iOS 27.0 (Xcode 27.0, 27A266a),
  /// releasing an `ImageRenderer` whose view has a container UIKit draws, a `NavigationStack` or a `Form`
  /// say, with `.task`, `.onAppear` or `.onDisappear` inside it, stops the test process: `ImageRenderer`'s
  /// deinit tears its view graph down outside an update, the inner graph's appearance effect queues its
  /// disappear action, and SwiftUI asserts "no current update to enqueue action to"
  /// (`UpdateGroup.enqueueAction`, from `AppearanceEffect.willRemove`, from `ImageRenderer.deinit`; #308).
  /// The app doesn't use `ImageRenderer`: UIKit tears its screens down inside an update. Keeping the
  /// renderer keeps the check, the view is built and drawn and its image checked, without the teardown
  /// only `ImageRenderer` does that way.
  @MainActor
  public enum ViewRendering {
    private static var renderers: [AnyObject] = []

    /// The view drawn as an image, or `nil` when nothing was drawn.
    public static func image(of view: some View) -> UIImage? {
      let renderer = ImageRenderer(content: view)
      renderers.append(renderer)
      return renderer.uiImage
    }

    /// Whether the view draws.
    public static func draws(_ view: some View) -> Bool {
      image(of: view) != nil
    }
  }
#endif
