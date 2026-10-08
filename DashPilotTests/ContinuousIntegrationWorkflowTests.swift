import Foundation
import Testing

/// What the CI workflow must keep doing, read off the workflow file itself.
///
/// This suite is unusual in two ways and both are deliberate.
///
/// It tests a **file in the repository** rather than a type in the app, because
/// the properties worth pinning here are properties of the run: that the job has
/// a budget large enough to finish the suite it starts, that neither test stage
/// has quietly been dropped or narrowed, and that the result bundles are still
/// uploaded when a run ends badly. A cancelled run leaves no assertion to read,
/// so the only place those can be stated is beside the tests themselves.
/// `main` run 35553963157 is the one that established it: a 60-minute budget
/// expired with the UI journeys still executing, 87 of 151 passed and none
/// failed, which is a budget problem wearing a test failure's clothes.
///
/// It reads the file through ``#filePath``, which is this source file's location
/// baked in at compile time, so it finds the checkout the bundle was built from.
/// Where that checkout is not readable at run time the suite is **disabled**
/// rather than failed: a bundle running somewhere else has nothing to say about
/// a workflow that is not there.
///
/// The parsing is deliberately textual. Adding a YAML dependency to check a
/// handful of lines would be a third-party runtime dependency for a test, and
/// the workflow's syntax is validated by GitHub on every push anyway. What is
/// checked here is meaning, not shape.
@Suite("Continuous integration workflow", .enabled(if: CIWorkflow.isReadable))
struct ContinuousIntegrationWorkflowTests {
    private func workflow() throws -> String {
        try #require(CIWorkflow.contents(of: CIWorkflow.workflowURL))
    }

    /// The budget fits a build, the domain suite and the essential journeys.
    /// 60 is the number that cancelled run 35553963157 with journeys still
    /// executing, and the ceiling stops the suite growing back toward the
    /// two-hour run it replaced without anyone deciding to.
    @Test("The job has a budget sized for the essential suite")
    func budgetIsSized() throws {
        let budget = try #require(CIWorkflow.jobTimeoutMinutes(in: try workflow()))
        #expect(budget > 60)
        #expect(budget <= 120)
    }

    /// Build, the whole domain suite, then the whole UI suite, in one job, in
    /// that order, and the UI journeys one at a time.
    @Test("Every run builds, runs every domain test, then every UI journey")
    func stagesSurvive() throws {
        let contents = try workflow()

        let build = try #require(contents.range(of: "xcodebuild build-for-testing"))
        let domain = try #require(contents.range(of: "-only-testing:DashPilotTests \\"))
        let ui = try #require(contents.range(of: "-only-testing:DashPilotUITests \\"))

        #expect(build.lowerBound < domain.lowerBound)
        #expect(domain.lowerBound < ui.lowerBound)
        #expect(CIWorkflow.jobNames(in: contents) == ["build-and-test"])
        #expect(contents.contains("-parallel-testing-enabled NO"))
        // Neither suite is ever narrowed to a subset.
        #expect(!contents.contains("-only-testing:DashPilotTests/"))
        #expect(!contents.contains("-only-testing:DashPilotUITests/"))
    }

    /// One tier: the workflow that gates a pull request is the one that runs
    /// on main, weekly, on a release tag and on demand, and no second UI
    /// workflow exists beside it.
    @Test("The one workflow runs on pull requests, main, weekly, tags and on demand")
    func triggersSurvive() throws {
        let contents = try workflow()
        #expect(contents.contains("pull_request:"))
        #expect(contents.contains("branches: [main]"))
        #expect(contents.contains("schedule:"))
        #expect(contents.contains("workflow_dispatch:"))
        #expect(contents.contains("tags: ['v*']"))
        #expect(CIWorkflow.contents(of: CIWorkflow.root.appending(path: ".github/workflows/ui-regression.yml")) == nil)
    }

    /// Selection is not weakened, and nothing is excused from failing.
    @Test("No test is skipped, retried or allowed to fail")
    func selectionIsNotWeakened() throws {
        let contents = try workflow()
        #expect(!contents.contains("-skip-testing"))
        #expect(!contents.contains("continue-on-error"))
        #expect(!contents.contains("-retry-tests-on-failure"))
        #expect(!contents.contains("test-iterations"))
    }

    /// Run 35553963157 proves the upload survives a cancellation.
    @Test("Result bundles are uploaded whatever the run did")
    func resultsAreUploadedOnFailureAndCancellation() throws {
        let contents = try workflow()
        let upload = try #require(contents.range(of: "actions/upload-artifact"))
        let always = try #require(contents.range(of: "if: always()"))
        #expect(always.lowerBound < upload.lowerBound)
        #expect(contents.contains("TestResults-UI.xcresult"))
        #expect(contents.contains("TestResults-Domain.xcresult"))
    }

    /// The UI suite stays the essential journeys: a behaviour the domain suite
    /// can pin belongs there. The audit that brought the suite to this size,
    /// the risk each journey covers and the rules for adding one are in
    /// docs/development/ui-suite-audit.md. Raise the ceiling deliberately, not
    /// to make room.
    @Test("The UI suite stays below its ceiling")
    func uiSuiteStaysSmall() throws {
        let source = try #require(CIWorkflow.contents(of: CIWorkflow.uiTestSourceURL))
        let suite = source.components(separatedBy: "    func test").count - 1
        #expect(suite > 0)
        #expect(suite <= 40, "\(suite) UI journeys")
    }

    /// Every journey is named in the traceability table, and the table names
    /// no journey that is gone, so the record of which risk each one covers
    /// cannot drift from the suite it describes.
    @Test("Every journey is in the traceability table, and the table names no other")
    func traceabilityNamesTheSuite() throws {
        let source = try #require(CIWorkflow.contents(of: CIWorkflow.uiTestSourceURL))
        let audit = try #require(CIWorkflow.contents(of: CIWorkflow.auditURL))
        let journeys = Set(CIWorkflow.names(matching: "    func (test[A-Za-z0-9]+)\\(\\)", in: source))
        let section = try #require(audit.components(separatedBy: "## Traceability").dropFirst().first)
        let table = section.components(separatedBy: "\n## ").first ?? section
        let listed = Set(CIWorkflow.names(matching: "`(test[A-Za-z0-9]+)`", in: table))
        #expect(!journeys.isEmpty)
        #expect(journeys.subtracting(listed).isEmpty, "Missing from the table: \(journeys.subtracting(listed).sorted())")
        #expect(listed.subtracting(journeys).isEmpty, "No such journey: \(listed.subtracting(journeys).sorted())")
    }
}

/// Reaching the workflow file from a test bundle.
///
/// Kept beside the suite rather than in the app: nothing the app ships knows
/// this file exists.
enum CIWorkflow {
    /// The checkout this bundle was compiled from, derived from this source
    /// file's own path. `DashPilotTests/ContinuousIntegrationWorkflowTests.swift`
    /// is two components below the repository root.
    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    static var workflowURL: URL { root.appending(path: ".github/workflows/ci.yml") }
    static var uiTestSourceURL: URL { root.appending(path: "DashPilotUITests/DashPilotUITests.swift") }
    static var auditURL: URL { root.appending(path: "docs/development/ui-suite-audit.md") }

    static var isReadable: Bool { contents(of: workflowURL) != nil }

    static func contents(of url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// Every first capture group of `pattern` in `contents`, in order.
    static func names(matching pattern: String, in contents: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(contents.startIndex..., in: contents)
        return regex.matches(in: contents, range: range).compactMap { match in
            Range(match.range(at: 1), in: contents).map { String(contents[$0]) }
        }
    }

    /// The job-level `timeout-minutes`, which is the only one the workflow sets.
    /// A step-level one would be indented further and is not what this reads.
    static func jobTimeoutMinutes(in contents: String) -> Int? {
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("    timeout-minutes:") else { continue }
            let value = line.dropFirst("    timeout-minutes:".count)
            return Int(value.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// The keys directly under `jobs:`, in file order.
    static func jobNames(in contents: String) -> [String] {
        var names: [String] = []
        var insideJobs = false
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("jobs:") {
                insideJobs = true
                continue
            }
            guard insideJobs else { continue }
            // A line at column zero ends the mapping.
            if let first = line.first, !first.isWhitespace { break }
            guard line.hasPrefix("  "), !line.hasPrefix("   "), line.hasSuffix(":") else { continue }
            names.append(String(line.dropFirst(2).dropLast()))
        }
        return names
    }
}
