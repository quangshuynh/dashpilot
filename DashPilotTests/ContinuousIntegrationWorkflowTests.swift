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
        try #require(CIWorkflow.contents())
    }

    /// The budget is the thing the cancelled run was short of, and 60 is the
    /// number it was short at.
    @Test("The job budget is no longer the 60 minutes that cancelled a run")
    func jobBudgetIsRealistic() throws {
        let contents = try workflow()
        let budget = try #require(CIWorkflow.jobTimeoutMinutes(in: contents))

        #expect(budget != 60)
        // Enough to finish the projected ~100-minute run with headroom, and
        // inside the 6 hours a GitHub-hosted job is capped at, so the value is
        // one the runner will actually honour.
        #expect(budget >= 120)
        #expect(budget <= 360)
    }

    /// Three stages, in one job, in this order. A test suite that moves into a
    /// second job is no longer serial, which is what the simulator cannot take.
    @Test("The build, the domain suite and the UI journeys are all still there, in order")
    func everyStageSurvives() throws {
        let contents = try workflow()

        let build = try #require(contents.range(of: "xcodebuild build-for-testing"))
        let domain = try #require(contents.range(of: "-only-testing:DashPilotTests"))
        let ui = try #require(contents.range(of: "-only-testing:DashPilotUITests"))

        #expect(build.lowerBound < domain.lowerBound)
        #expect(domain.lowerBound < ui.lowerBound)

        // One job, so the three stages cannot overlap on one simulator.
        #expect(CIWorkflow.jobNames(in: contents) == ["build-and-test"])

        // The UI journeys run one at a time. Cloned simulators running in
        // parallel is the load this project has measured failures under.
        #expect(contents.contains("-parallel-testing-enabled NO"))
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

    /// The upload has to survive the run it is reporting on. Run 35553963157
    /// proves it does: the job was cancelled at its budget and the upload step
    /// still ran and succeeded.
    @Test("Result bundles are uploaded whatever the run did")
    func resultsAreUploadedOnFailureAndCancellation() throws {
        let contents = try workflow()

        let upload = try #require(contents.range(of: "actions/upload-artifact"))
        let always = try #require(contents.range(of: "if: always()"))
        #expect(always.lowerBound < upload.lowerBound)

        #expect(contents.contains("TestResults-Domain.xcresult"))
        #expect(contents.contains("TestResults-UI.xcresult"))
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
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".github/workflows/ci.yml")
    }

    static var isReadable: Bool { contents() != nil }

    static func contents() -> String? {
        try? String(contentsOf: url, encoding: .utf8)
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
