#if DEBUG
import Foundation
import SwiftData

/// Synthetic data for SwiftUI previews. Never contains real driver history.
enum PreviewSupport {
    static func emptyContainer() -> ModelContainer {
        // Previews cannot meaningfully recover from a container failure.
        try! ModelContainerFactory.makeInMemoryContainer()
    }

    static func populatedContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000),
        includingActiveShift: Bool = true
    ) -> ModelContainer {
        let container = emptyContainer()
        let context = ModelContext(container)

        let completed = Shift(startedAt: referenceDate.addingTimeInterval(-4 * 3600))
        try? completed.end(at: referenceDate.addingTimeInterval(-3600))

        let earlier = Shift(startedAt: referenceDate.addingTimeInterval(-30 * 3600))
        try? earlier.end(at: referenceDate.addingTimeInterval(-25 * 3600))

        var shifts = [completed, earlier]
        if includingActiveShift {
            shifts.append(Shift(startedAt: referenceDate.addingTimeInterval(-1800)))
        }

        for shift in shifts {
            context.insert(shift)
        }
        try? context.save()

        return container
    }
}
#endif
