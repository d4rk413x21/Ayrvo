# Contributing to Ayrvo

Keep changes focused on reliable meeting capture, faithful transcription, and
reviewable development tasks. Preserve the distinction between explicit requests,
ideas, and open questions; avoid introducing unsupported commitments or assignees.

## Development setup

Use Xcode 27.1 with Swift 6.4, or the repository's GitHub Actions workflows.
The supported runtime is macOS 26 or later on Apple Silicon.

```sh
make test
make app
```

The application product and Swift source module are `Ayrvo`; tests use
`AyrvoTests`. Sources live in `Sources/Ayrvo/`, tests in `Tests/AyrvoTests/`.

## Changes and pull requests

1. Create a branch from `main`.
2. Follow the surrounding Swift and SwiftUI patterns, and reuse existing services
   and components.
3. Add a focused test when changing behavior. Use temporary archives and isolated
   UserDefaults suites; do not change the developer's real meeting library.
4. Use Conventional Commits for commit messages and pull request titles.
5. Run the relevant checks and open a ready-for-review pull request before merging.

Describe the user-visible problem, the resulting behavior, and how the change was
validated. State which checks could not be run. UI changes should include a
screenshot or a brief description of the tested layouts.

Retain existing license and attribution notices.

## Compatibility

Ayrvo preserves Nutola's bundle identifier, storage locations, and Keychain service
so existing installations keep their data and settings. Treat changes to these
values, persisted formats, or MCP tools as compatibility changes and document the
migration before changing them.

## Reporting a problem

Open an issue with the app and macOS versions, reproduction steps, and expected
behavior. Use synthetic examples where possible and remove recordings, transcript
content, credentials, and other personal information before sharing diagnostics.

## Preparing a release

1. Create a release preparation branch from `main`. Update `VERSION`, add a dated
   section to `CHANGELOG.md`, and write notes under `docs/releases/`.
2. Open a pull request. Version changes trigger CI tests and an app preview build;
   inspect the bundle version and download the `Ayrvo-preview` artifact to check
   the packaged app. Record any unavailable device or OS checks in the release notes.
3. After the PR is merged and `main` is green, prepare a draft GitHub release with
   a tag matching `VERSION`, such as `v0.1.0`, targeting that merge commit. Use the
   corresponding release notes file as its description.
4. Review the draft, then publish it. The release workflow validates the tag,
   builds the app, verifies its signature, and attaches `Ayrvo.zip`. Verify that
   the workflow succeeds and that the asset is available before announcing it.

The release workflow currently uses ad-hoc signing; it does not notarize the app.
Do not describe these packages as Developer ID signed or notarized.
