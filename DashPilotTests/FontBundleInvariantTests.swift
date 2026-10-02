import Foundation
import Testing
@testable import DashPilot

/// That no typeface is shipped, and that removing the one that was disturbed
/// nothing else.
///
/// DashPilot is set in the system face and bundles no font. Each of these pins
/// a defect a real font commit has carried: fonts added to the widget extension
/// as well as the app, `NSSupportsLiveActivities` dropped from a hand-edited
/// `Info.plist`, and the extension's embed phase emptied so the app shipped with
/// no Live Activity at all. None of those fails a build. They are read here off
/// the bundle the app actually launches with, which is the only place the result
/// is visible.
@Suite("Font bundle invariants")
struct FontBundleInvariantTests {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    /// The embedded widget extension, which is also what proves it is still
    /// embedded.
    private var widgetExtension: Bundle? {
        Bundle.main.builtInPlugInsURL
            .map { $0.appendingPathComponent("DashPilotWidgets.appex") }
            .flatMap(Bundle.init(url:))
    }

    @Test("The app declares no UIAppFonts, because it bundles no font")
    func noDeclaredFonts() {
        #expect(info["UIAppFonts"] == nil)
    }

    @Test("The app bundle ships no font file and no font license")
    func noFontFiles() {
        for fileExtension in ["ttf", "otf", "ttc"] {
            let urls = Bundle.main.urls(forResourcesWithExtension: fileExtension, subdirectory: nil) ?? []
            #expect(urls.isEmpty, "Bundled fonts: \(urls.map(\.lastPathComponent))")
        }
        #expect(Bundle.main.url(forResource: "OFL", withExtension: "txt") == nil)
    }

    @Test("The widget extension is still embedded, and carries no font")
    func widgetCarriesNoFont() throws {
        let widget = try #require(widgetExtension, "DashPilotWidgets.appex is not embedded in the app")
        let fonts = widget.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        #expect(fonts.isEmpty, "The extension bundles \(fonts.map(\.lastPathComponent))")
        #expect(widget.object(forInfoDictionaryKey: "UIAppFonts") == nil)
    }

    @Test("The plist keys the app exists for are all still declared")
    func appKeysSurvive() {
        #expect(info["NSSupportsLiveActivities"] as? Bool == true)
        #expect(info["UIBackgroundModes"] as? [String] == ["location"])
        #expect((info["NSLocationWhenInUseUsageDescription"] as? String)?.isEmpty == false)
        // When In Use is the whole authorization story; Always is never asked.
        #expect(info["NSLocationAlwaysAndWhenInUseUsageDescription"] == nil)
        #expect(info["NSLocationAlwaysUsageDescription"] == nil)
    }
}

/// The project file itself, for the two properties a built bundle cannot show.
///
/// Read through ``#filePath`` like ``ContinuousIntegrationWorkflowTests``, and
/// disabled rather than failed where the checkout is not readable.
@Suite("Project file invariants", .enabled(if: ProjectFile.isReadable))
struct ProjectFileInvariantTests {
    @Test("No file reference points at an absolute path on one machine")
    func noAbsolutePaths() throws {
        let contents = try #require(ProjectFile.contents())
        #expect(!contents.contains("sourceTree = \"<absolute>\""))
        #expect(!contents.contains("/Users/"))
    }

    @Test("The widget extension compiles only its own sources and the shared activity folder")
    func widgetTargetFolders() throws {
        let contents = try #require(ProjectFile.contents())
        let target = try #require(contents.range(of: "/* DashPilotWidgets */ = {\n\t\t\tisa = PBXNativeTarget;"))
        let rest = contents[target.upperBound...]
        let groupsStart = try #require(rest.range(of: "fileSystemSynchronizedGroups = ("))
        let groupsEnd = try #require(rest[groupsStart.upperBound...].range(of: ");"))
        let groups = rest[groupsStart.upperBound..<groupsEnd.lowerBound]
        #expect(groups.contains("DashPilotActivity"))
        #expect(groups.contains("DashPilotWidgets"))
        #expect(!groups.contains("Fonts"), "A font folder is a member of the widget target")
        #expect(!groups.contains("/* DashPilot */"), "The app's own folder is a member of the widget target")
    }
}

enum ProjectFile {
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DashPilot.xcodeproj/project.pbxproj")
    }

    static var isReadable: Bool { FileManager.default.isReadableFile(atPath: url.path) }

    static func contents() -> String? { try? String(contentsOf: url, encoding: .utf8) }
}
