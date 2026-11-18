import CoreKitMixpanel
import Testing

/// How a screen reaches Mixpanel, read without Mixpanel set up. The twin of CoreKit-Android's
/// `MixpanelScreenEventTest`.
struct MixpanelScreenEventTests {
    /// By default a screen reads the same in Mixpanel and in Firebase.
    @Test func theStandardShapeIsFirebases() {
        #expect(MixpanelScreenEvent.standard.event == "screen_view")
        #expect(MixpanelScreenEvent.standard.properties(for: "settings") == ["screen_name": "settings"])
    }

    /// An app with reports of its own keeps them: its event name and its key, and nothing else.
    @Test func anAppKeepsTheShapeItsReportsRead() {
        let legacy = MixpanelScreenEvent(event: "page_viewed", nameKey: "name_of_the_page_viewed")

        #expect(legacy.event == "page_viewed")
        #expect(legacy.properties(for: "profile") == ["name_of_the_page_viewed": "profile"])
    }
}
