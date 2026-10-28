# Changelog

All notable changes to Ayrvo are documented here, including its history as Nutola. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`VERSION` is the source of truth for the app version. See
[Preparing a release](CONTRIBUTING.md#preparing-a-release) for the release workflow.

## [Unreleased]

## [0.1.0] - 2026-10-28

The first Ayrvo release brings a new identity and a meeting-to-development workflow
built on the inherited Nutola codebase. This section covers changes since 0.0.2;
older entries retain their original release history.

### Added
- Reviewable development task drafts extracted from meeting transcripts through a
  supported AI CLI, with source quotations and explicit owner information.
- Linear integration for selected task drafts, with saved issue links, export
  checkpoints, and recovery from interrupted requests.
- Read-only meeting CLI and MCP integration for working with the meeting library
  from an assistant; MCP also supports editing and deletion.
- Google Meet speaker-name attribution in Chrome using Accessibility and captions,
  including Italian and English layouts and participant names from the People panel.
- Parakeet Redux and Ultra for on-device final transcription, with download progress,
  installed model sizes, and model removal controls.
- Support for editor-bundled Claude Code and Codex binaries, OpenCode, and Mistral Vibe.

### Changed
- Rename the application, executable, source module, and assistant connector to
  Ayrvo; introduce the blue-and-purple app icon and shared branding.
- Refresh the macOS interface with native controls, Liquid Glass floating surfaces,
  and clearer settings navigation while keeping document readers opaque.
- Split large meeting, settings, digest, recording, and assistant views into focused
  components; simplify audio capture, transcription, and processing responsibilities.
- Migrate to Swift 6 and Swift Testing; align FluidAudio with version 0.17.7.
- Rewrite project documentation around installation, recording, reviewed tasks,
  privacy, and contribution workflows.
- Preserve the existing bundle identifier, Keychain service, preferences, and
  library directory so upgrading from Nutola does not require a data migration.

### Fixed
- Serialize recording startup, resume, and stop so a late startup cannot reactivate
  a stopped session and another recording cannot start before teardown completes.
- Keep elapsed duration and transcript timestamps consistent across resumed
  recordings; avoid duplicated live segments during processing retries.
- Restore previous capture files when a resumed recording fails or is cancelled,
  and prevent stale processing runs from overwriting a newly resumed meeting.
- Prevent automatic meeting detection from immediately restarting a manually stopped
  recording while the same meeting remains active.
- Finalize audio before transcription; recover empty microphone results, skip empty
  system tracks, and replace live drafts with the completed transcript.
- Improve microphone route-change recovery and speaker attribution when loudspeaker
  playback bleeds into the microphone; retain acoustic evidence after decode errors.
- Keep meeting titles, notes, and summary edits through store updates and failed
  saves; expose retry notices and retain pending changes without stale rewrites.
- Keep summary snapshots ordered and unique, and decision rows stable when
  transcripts or speaker names change.
- Preserve task-to-meeting provenance in daily digests instead of inferring it from
  array positions, and include pending template saves in template lists.
- Keep calendar month names on one line and recording controls available in meeting
  layouts without a footer Resume button.

### Removed
- Inherited online note publishing, including `notes.nutola.to`, Gist publishing,
  Cloudflare deployment code, and unused integration code.
- Dead code and weak or unsafe tests, replaced where appropriate with deterministic
  coverage for recording lifecycle, persistence, provider selection, and audio health.

## [0.0.2]` section below
   that moves the `[Unreleased]` entries into the new version.
2. Commit on `develop`.
3. Merge `develop` → `main`.
4. Tag `main` as `v0.0.2` and push the tag: `git tag v0.0.2 && git push origin v0.0.2`.

## [Unreleased]

### Changed
- Separate meeting headers, note presentation/editing, sharing, exports, and transcript/decision sections
  into focused SwiftUI views; organize settings sections in dedicated files.

### Fixed
- Save personal notes only while local changes are pending; retain failed saves for retry
  and avoid overwriting newer external edits during a later flush.
- Keep decision row identity stable when a transcript is re-evaluated or a speaker is renamed.
- Display meeting/preview notices in the document and keep Resume recording available
  when no resume button is present in the footer.

## [0.0.2] - 2026-07-29

### Fixed
- Menu bar freeze on recording start — the Zoom AX-tree scan
  (`ZoomActiveSpeakerReader.scan`) ran synchronously on the main thread,
  blocking the menu bar for 20–30s. The scan and tracker creation now run
  on a background `Task.detached`; the main thread is touched only to wire
  callbacks and start polling. `ensureZoomTracker` no longer re-scans or
  blocks on the tracker's serial queue; the initial roster is fetched
  asynchronously. `startupNotice` uses a cached decision instead of a sync
  scan. The dead synchronous `shouldTrackZoomSpeakers` was removed.
- Status-bar item re-rendered every second (shared the 1s elapsed ticker
  with the in-menu RecordingCard clock). Added a coarse `menuBarElapsed`
  driven by a 30s timer; the system status bar now redraws every 30s while
  the in-menu clock stays smooth at 1s.


## [0.0.1] - 2026-07-20

Initial versioned release. Establishes the `VERSION` + `CHANGELOG.md`
release structure and ships the recording reliability and per-meeting
control improvements that accumulated on `develop`.

### Added
- Per-meeting transcription language picker — pin a call to one locale
  (English, Portuguese, Spanish, French, …) or leave on Auto for
  code-switching. Sticky for the whole call and across resumes.
  Lives in the live recording card and the live transcript header.
- Per-calendar-event template assignment — assign a template to a
  specific upcoming meeting so a one-off interview doesn't inherit the
  series' default template. Resolved after the smart/default template,
  so the override always wins.
- System-audio tap watchdog — polls the tap callback count and rebuilds
  the tap + aggregate if callbacks stall for 10s, so the far side of
  the call no longer goes silent mid-recording.
- Mic built-in fallback on restart — when a route change kills the mic
  engine and the Bluetooth headset mic is contended (Zoom/Chrome holding
  it), the engine now switches the system default input to the built-in
  mic and retries with a fresh AVAudioEngine, keeping the same open file.
- `VERSION` file (single source of truth) + `CHANGELOG.md`.
- Makefile stamps `VERSION` into `packaging/Info.plist` on every build.

### Fixed
- Headphone bleed no longer misattributes the local speaker's turns to
  "Others". Mic segments stay "me" and only drop as bleed echoes when
  their transcript text overlaps a concurrent "them" segment — talking
  over remote audio no longer disappears your side of the call.
- Mic engine restart after a default-input route change now rebuilds a
  fresh AVAudioEngine bound to the new device instead of reusing a stale
  one whose input format no longer matches the live route.
- Live transcript no longer auto-scrolls on every new segment — opens at
  the latest turn but lets you scroll up to read earlier turns without
  being yanked back down.
- Menu bar panel dismiss after opening Nutola or Settings.
- Archived calendar events UI + removed Gist publish from Share Notes.
- AI-generated template names sanitized (no `/` or `:`) and de-duplicated.
- Crash on launch from `MenuBarExtra(isInserted:)` toggle reverted.
