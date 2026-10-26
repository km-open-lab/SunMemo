import SwiftUI

extension View {
    /// All four paper colors stay light in either system appearance. Resolve
    /// semantic ink, controls and materials against that paper, not the desktop.
    func memoPaperAppearance() -> some View {
        environment(\.colorScheme, .light)
    }
}
