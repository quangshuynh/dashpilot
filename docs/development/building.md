# Building

DashPilot is a plain Xcode project with no package manager, no code generation step and no
bootstrap script. Cloning it and opening it is the whole setup.

## Requirements

| Requirement | Version |
| --- | --- |
| Xcode | 26.6 or later |
| iOS deployment target | 26.5 |
| Swift | Swift 5 language mode, with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` |
| Dependencies | None |

Xcode 26.6 is required because the project's deployment target is iOS 26.5, and an Xcode without the
iOS 26.5 SDK refuses to build it.

## In Xcode

Open `DashPilot.xcodeproj`, choose the `DashPilot` scheme and an iOS simulator, then build and run.
The scheme covers the app, the `DashPilotTests` domain suite and the `DashPilotUITests` journeys.

## From the command line

```bash
xcodebuild build \
  -project DashPilot.xcodeproj \
  -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

```bash
xcodebuild test \
  -project DashPilot.xcodeproj \
  -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Substitute any installed iPhone simulator for `iPhone 17`. To see what is installed:

```bash
xcrun simctl list devices available
```

Adding `clean` before the action (`xcodebuild clean test ...`) is what the project treats as the
release-gate build, because it catches the integration failures an incremental build hides.

## Signing

The app target carries a development team for local device runs. Simulator builds do not need it,
and CI passes `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` so that no Apple Developer account
is required to build or test the project. Nothing in the repository signs or archives for
distribution.

## Building the documentation site

The documentation is MkDocs Material. It is entirely separate from the app: **Python is never
required to build or run DashPilot itself.**

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-docs.txt
mkdocs serve
```

`mkdocs serve` publishes a live-reloading copy on <http://127.0.0.1:8000/>.

To reproduce exactly what CI checks:

```bash
mkdocs build --strict
```

`strict` is on in `mkdocs.yml` as well, so a broken internal link, a missing anchor or a page left
out of the navigation fails the build rather than shipping. The generated `site/` directory is
ignored by Git and must never be committed.

## Continuous integration

Two workflows cover the app and the documentation:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `ci.yml` | Pull requests, pushes to `main` | Builds the app and both test bundles for an iOS simulator on a GitHub-hosted macOS runner, then runs the domain suite and the UI journeys as separate steps |
| `docs-check.yml` | Pull requests touching `docs/`, `mkdocs.yml`, `requirements-docs.txt`, the README or itself | Runs `mkdocs build --strict` on Ubuntu. It validates only and never deploys |
| `docs.yml` | Pushes to `main` touching documentation, and manual dispatch | Builds the site and deploys it to GitHub Pages through the Actions artifact |

The runner details, including how the Xcode version and the simulator destination are chosen, are
under [Testing](testing.md#continuous-integration).
