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
    private func pullRequestWorkflow() throws -> String {
        try #require(CIWorkflow.contents(of: CIWorkflow.pullRequestURL))
    }

    private func regressionWorkflow() throws -> String {
        try #require(CIWorkflow.contents(of: CIWorkflow.regressionURL))
    }

    /// The pull-request budget fits a build, the domain suite and the smoke
    /// journeys, and is far below the full suite's: if it ever has to grow
    /// toward that, the smoke list has stopped being a smoke list.
    @Test("The pull-request job has a budget sized for the smoke journeys")
    func pullRequestBudgetIsSized() throws {
        let budget = try #require(CIWorkflow.jobTimeoutMinutes(in: try pullRequestWorkflow()))
        #expect(budget >= 30)
        #expect(budget <= 120)
    }

    /// The full suite keeps the budget measured for it. 60 is the number that
    /// cancelled run 35553963157 with journeys still executing.
    @Test("The full UI suite keeps a budget it can finish in")
    func regressionBudgetIsRealistic() throws {
        let budget = try #require(CIWorkflow.jobTimeoutMinutes(in: try regressionWorkflow()))
        #expect(budget != 60)
        #expect(budget >= 120)
        #expect(budget <= 360)
    }

    /// Build, the whole domain suite, then the smoke journeys, in one job, in
    /// that order, and the UI journeys one at a time.
    @Test("Pull requests build, run every domain test, then the smoke journeys")
    func pullRequestStagesSurvive() throws {
        let contents = try pullRequestWorkflow()

        let build = try #require(contents.range(of: "xcodebuild build-for-testing"))
        let domain = try #require(contents.range(of: "-only-testing:DashPilotTests"))
        let ui = try #require(contents.range(of: "ui-smoke-journeys.txt\n"))

        #expect(build.lowerBound < domain.lowerBound)
        #expect(domain.lowerBound < ui.lowerBound)
        #expect(CIWorkflow.jobNames(in: contents) == ["build-and-test"])
        #expect(contents.contains("-parallel-testing-enabled NO"))
        // The domain suite is never narrowed to a subset.
        #expect(!contents.contains("-only-testing:DashPilotTests/"))
        // An empty selection would silently run everything or nothing.
        #expect(contents.contains("The smoke list selected no journeys."))
    }

    /// The broad regression still runs every journey, serially, and runs on
    /// the occasions it exists for.
    @Test("The full UI suite runs every journey on main, weekly, on tags and on demand")
    func regressionRunsEverything() throws {
        let contents = try regressionWorkflow()

        let build = try #require(contents.range(of: "xcodebuild build-for-testing"))
        // The whole target, with the line continuing to the next flag.
        let ui = try #require(contents.range(of: "-only-testing:DashPilotUITests \\"))
        #expect(build.lowerBound < ui.lowerBound)
        #expect(!contents.contains("-only-testing:DashPilotUITests/"))
        #expect(contents.contains("-parallel-testing-enabled NO"))
        #expect(CIWorkflow.jobNames(in: contents) == ["ui-regression"])

        #expect(contents.contains("branches: [main]"))
        #expect(contents.contains("schedule:"))
        #expect(contents.contains("workflow_dispatch:"))
        #expect(contents.contains("tags: ['v*']"))
    }

    /// Selection is not weakened, and nothing is excused from failing, in
    /// either workflow.
    @Test("No test is skipped, retried or allowed to fail")
    func selectionIsNotWeakened() throws {
        for contents in [try pullRequestWorkflow(), try regressionWorkflow()] {
            #expect(!contents.contains("-skip-testing"))
            #expect(!contents.contains("continue-on-error"))
            #expect(!contents.contains("-retry-tests-on-failure"))
            #expect(!contents.contains("test-iterations"))
        }
    }

    /// Run 35553963157 proves the upload survives a cancellation.
    @Test("Result bundles are uploaded whatever the run did")
    func resultsAreUploadedOnFailureAndCancellation() throws {
        for contents in [try pullRequestWorkflow(), try regressionWorkflow()] {
            let upload = try #require(contents.range(of: "actions/upload-artifact"))
            let always = try #require(contents.range(of: "if: always()"))
            #expect(always.lowerBound < upload.lowerBound)
            #expect(contents.contains("TestResults-UI.xcresult"))
        }
        #expect(try pullRequestWorkflow().contains("TestResults-Domain.xcresult"))
    }

    /// Every listed journey exists, none is listed twice, and the list stays a
    /// smoke list. A renamed journey left in the list would otherwise make
    /// `-only-testing` select nothing for it and pass without running it.
    @Test("The smoke list names real journeys, once each, and stays short")
    func smokeListIsValid() throws {
        let journeys = try #require(CIWorkflow.smokeJourneys())
        let source = try #require(CIWorkflow.contents(of: CIWorkflow.uiTestSourceURL))

        #expect(journeys.count >= 10)
        #expect(journeys.count <= 45)
        #expect(Set(journeys).count == journeys.count, "A journey is listed twice")
        for journey in journeys {
            #expect(journey.hasPrefix("test"), "\(journey) is not a test name")
            #expect(source.contains("func \(journey)()"), "\(journey) is listed but no journey has that name")
        }
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

    static var pullRequestURL: URL { root.appending(path: ".github/workflows/ci.yml") }
    static var regressionURL: URL { root.appending(path: ".github/workflows/ui-regression.yml") }
    static var smokeListURL: URL { root.appending(path: ".github/ui-smoke-journeys.txt") }
    static var uiTestSourceURL: URL { root.appending(path: "DashPilotUITests/DashPilotUITests.swift") }

    static var isReadable: Bool { contents(of: pullRequestURL) != nil }

    static func contents(of url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// The listed journey names, without comments or blank lines, in file
    /// order: the same reading the workflow's shell loop performs.
    static func smokeJourneys() -> [String]? {
        guard let contents = contents(of: smokeListURL) else { return nil }
        return contents.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            let uncommented = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let name = uncommented.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
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
