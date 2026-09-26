import Foundation
import Testing
@testable import DashPilot

/// Where the typeface is shipped, and what adding it must not have disturbed.
///
/// Each of these pins a defect a real font commit has carried: fonts added to
/// the widget extension as well as the app, `UIAppFonts` entries spelled
/// `.tff`, `NSSupportsLiveActivities` dropped from a hand-edited `Info.plist`,
/// a second and third family declared beside the one the roles use, and the
/// extension's embed phase emptied so the app shipped with no Live Activity at
/// all. None of those fails a build. They are read here off the bundle the app
/// actually launches with, which is the only place the result is visible.
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

    @Test("Every UIAppFonts entry ends in .ttf, never the .tff a typo produces")
    func noMisspelledExtensions() throws {
        let fonts = try #require(info["UIAppFonts"] as? [String])
        #expect(!fonts.isEmpty)
        for file in fonts {
            #expect(!file.lowercased().hasSuffix(".tff"), "Misspelled entry \(file)")
            #expect((file as NSString).pathExtension == "ttf", "Unexpected entry \(file)")
        }
    }

    @Test("The app bundle ships one custom family, and no other font file")
    func oneFamilyOnly() throws {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        let files = urls.map(\.lastPathComponent).sorted()
        #expect(
            files == ["Manrope-Bold.ttf", "Manrope-Medium.ttf", "Manrope-Regular.ttf", "Manrope-SemiBold.ttf"],
            "Bundled fonts: \(files)"
        )
        for family in ["SpaceGrotesk", "DMSans", "IBMPlexSans"] {
            #expect(!files.contains { $0.hasPrefix(family) }, "\(family) is bundled")
        }
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
