<div align="center">
  <img src="Resources/AppIcon-1024.png" width="128" height="128" alt="Ayrvo app icon">
  <h1>Ayrvo</h1>
  <p><strong>Your meetings, ready for the work that follows.</strong></p>
  <p>A native macOS app for recording conversations, transcribing on your Mac,<br>and turning explicit requests into development tasks you can review.</p>

[![CI](https://github.com/d4rk413x21/Ayrvo/actions/workflows/ci.yml/badge.svg)](https://github.com/d4rk413x21/Ayrvo/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/d4rk413x21/Ayrvo)](https://github.com/d4rk413x21/Ayrvo/releases)
[![macOS](https://img.shields.io/badge/macOS-26%2B-blue)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Download](https://github.com/d4rk413x21/Ayrvo/releases/latest) · [Getting started](#getting-started) · [Changelog](CHANGELOG.md) · [Report an issue](https://github.com/d4rk413x21/Ayrvo/issues)
</div>

---

## Why Ayrvo?

A conversation rarely ends with a perfect task list. Ayrvo keeps the recording,
transcript, notes, and proposed work together, so you can check what was actually
said before deciding what happens next.

Capture microphone and system audio from your menu bar, follow the live transcript,
and review the final notes in a native SwiftUI interface. Extract development task
drafts with a supported AI CLI, check their quoted evidence, and send selected
issues to Linear.

**Recording and transcription happen on your Mac.** Summaries, chat, and task
extraction use your chosen provider, which may send text to a remote model.
See [Data and privacy](#data-and-privacy).

## Features

| | What you can do |
| --- | --- |
| **Record conversations** | Capture microphone and system audio, resume an existing meeting, and use optional meeting detection and calendar matching. |
| **Transcribe on your Mac** | Follow an Apple Speech live preview and choose Apple Speech, Parakeet Redux, or Parakeet Ultra for final transcription. |
| **Review speakers and context** | Edit transcripts and speaker names; use supported meeting-client integrations to supplement speaker attribution. |
| **Organize your library** | Edit notes, use summary templates, search meetings, organize folders, and review daily digests. |
| **Draft development tasks** | Extract proposed work with transcript quotations and owner context, then review or copy the selected drafts. |
| **Connect Linear** | Create selected issues, keep their links, and recover interrupted exports using saved checkpoints. |
| **Work with an assistant** | Read meetings through the bundled CLI, or connect an MCP client to the library. |
| **Export and share** | Produce local HTML, Markdown, PDF, CSV, and subtitle exports without an online publishing service. |

Ideas, tentative suggestions, and open questions should remain distinguishable
from explicit requests. Review model output before treating it as agreed work.

## Requirements

- **Apple Silicon Mac running macOS 26 or later.**
- Microphone and system audio permissions for recording.
- A configured **Claude Code, Codex, OpenCode, or Mistral Vibe** CLI for CLI-based AI
  features. Provider accounts and model availability depend on your configuration.
- Optional Calendar access for event matching and upcoming meetings.
- Optional Accessibility access for supported meeting-client speaker attribution.
- Optional Linear personal API key for publishing issues.

Apple Intelligence is an optional summary provider. It is not required when using
a supported AI CLI; development task extraction uses a supported CLI.

## Installation

1. Download **Ayrvo.zip** from [GitHub Releases](https://github.com/d4rk413x21/Ayrvo/releases/latest).
2. Extract the archive and move **Ayrvo.app** to **Applications**.
3. Open Ayrvo and follow the permissions walkthrough.

Current builds use ad-hoc signing and are not notarized. If macOS blocks opening
Ayrvo, review the notice in **System Settings → Privacy & Security** and approve
opening the app if you trust the download.

<details>
<summary>Try a development preview without installing Xcode</summary>

Open [Actions → CI](https://github.com/d4rk413x21/Ayrvo/actions/workflows/ci.yml),
select **Run workflow**, and choose a branch. After the run succeeds, download the
**Ayrvo-preview** artifact, extract `Ayrvo.zip`, and move the app to Applications.
Running the workflow requires repository access; downloading artifacts requires a
GitHub account. Preview artifacts expire after seven days.

</details>

<details>
<summary>Upgrade from Nutola</summary>

Quit Nutola before opening Ayrvo. The apps share the same macOS application
identity and replace each other rather than running side by side.

Ayrvo preserves `io.github.d4rk413x21.Nutola`, the preference domain, Linear Keychain
service, and `~/Library/Application Support/Nutola/` library. The rename does not
move recordings or intentionally reset preferences, credentials, or downloaded
models. macOS may still ask you to confirm permissions after replacing an
ad-hoc-signed build.

Update scripts pointing at `Nutola.app` to the Ayrvo executable. Reconfigure MCP
in **Settings → Intelligence** using the connector name `ayrvo`.

</details>

## Getting started

1. **Choose your provider.** Configure your AI CLI outside the app, then select it
   in **Settings → Intelligence**. Claude and Codex installations bundled with VS
   Code and VS Code Insiders are also detected.
2. **Record a meeting.** Start from the menu bar or accept a meeting-detection
   prompt. You can also import an existing audio file.
3. **Review the result.** Check the final transcript, speaker names, and generated
   notes. Apply a template or edit the notes to suit the meeting.
4. **Decide what becomes work.** Open **Development tasks**, extract drafts, and
   review their titles, descriptions, owners, and quoted evidence.
5. **Keep or publish.** Save the drafts, copy selected drafts as Markdown, or
   publish selected issues to Linear.

### From a meeting to Linear

Connect a personal API key in **Settings → Integrations**, choose a **Team** and an
optional **Project**, then use **Create / retry issues** on selected drafts. The
key needs access to teams, projects, and issues, with permission to create issues.
Owner names remain in descriptions; Ayrvo does not infer Linear assignees.

Exports retain stable issue IDs and checkpoints. Retry checks for existing issues
before creating another one. After an export starts, task removal and
re-extraction are disabled to preserve recovery information. Edit published issues
in Linear: retry recovers links without applying later draft edits. Disconnecting
Linear keeps existing issues and saved links.

### Speaker names in Google Meet

Use **Chrome**, grant Ayrvo **Accessibility** access, and enable **Meet captions**.
Keep the meeting selected in its Chrome window; Chrome can remain behind Ayrvo.
Italian and English Meet layouts are supported. Opening the **People** panel also
makes participant names available.

Caption speaker labels supplement local transcription and diarization. Stale
captions, another meeting tab, or overlapping speakers can limit name attribution.
Caption text does not replace the recorded transcript. Other browsers can still
be recorded without this integration.

**Muting your microphone in Meet does not pause Ayrvo's microphone recording.**

## Data and privacy

| Data or feature | Where it goes |
| --- | --- |
| Audio and transcription | Processed on your Mac; required models may be downloaded. |
| Recordings, transcripts, notes, and drafts | Stored in your local meeting library. |
| Summaries, chat, and task extraction | Handled by your selected provider; a CLI may send meeting text through its configured account and model. |
| Linear export | Sends selected task content and supporting transcript passages; connecting also loads workspace, team, and project metadata. |
| Linear credentials | Stored in the macOS login Keychain. |
| Sharing | Uses local export files or the clipboard. |

The library remains at `~/Library/Application Support/Nutola/` for compatibility
with existing installations. Back up this directory to preserve your meetings.
If saving fails, keep Ayrvo open and use **Retry saving**: unsaved contents remain
in memory and can be lost if you quit before saving succeeds.

## CLI and MCP

The app includes a read-only meeting CLI:

```sh
/Applications/Ayrvo.app/Contents/MacOS/Ayrvo meetings help
/Applications/Ayrvo.app/Contents/MacOS/Ayrvo meetings list --limit 10
```

For MCP, follow **Settings → Intelligence**. The same executable starts the server
with `--mcp`. MCP also exposes editing and deletion tools; configure access to match
the operations you want an assistant to perform.

## Development

The full build requires **Xcode 27.1 with Swift 6.4**. The supported app runtime
starts at macOS 26. GitHub Actions provides the build toolchain if you do not have
Xcode locally.

```sh
git clone https://github.com/d4rk413x21/Ayrvo.git
cd Ayrvo
make test   # Build and run Swift Testing tests
make app    # Build and verify dist/Ayrvo.app
```

`make install` also installs the app in `/Applications/Ayrvo.app`. Sources live in
`Sources/Ayrvo/`, tests in `Tests/AyrvoTests/`; `zoom-info` is a separate utility.
Tests use Swift Testing from the toolchain. Tests requiring Apple Intelligence are
skipped when the provider is unavailable.

Publishing a versioned GitHub release builds and attaches `Ayrvo.zip`. CI also
packages a preview when build metadata changes or the workflow is run manually.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the PR and release workflow.

## Contributing and support

[Open an issue](https://github.com/d4rk413x21/Ayrvo/issues) with the app version,
macOS version, reproduction steps, and expected behavior. Remove personal meeting
content and credentials from diagnostics. Contributions are welcome through
focused pull requests; see [the contribution guide](CONTRIBUTING.md).

## Acknowledgements

Ayrvo is an independent continuation of the Nutola codebase. Its Git history and
original attribution notices are retained.

- [Nutola/Nutola](https://github.com/Nutola/Nutola), previously hosted at
  `maatheusgois-dd/Nutola`, and the
  [Nutola adaptation](https://github.com/d4rk413x21/Nutola) from which Ayrvo was created.
- [conrad-vanl/parfait](https://github.com/conrad-vanl/parfait), for the original
  architecture and audio/transcription workflow.
- [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0), for speaker
  diarization. Associated model weights derive from
  [pyannote](https://github.com/pyannote/pyannote-audio) and
  [WeSpeaker](https://github.com/wenet-e2e/wespeaker) (CC-BY-4.0).
- [Granola](https://granola.ai), for inspiration for the meeting-notes experience.
- [anarlog](https://github.com/fastrepl/anarlog), which also uses the Soniqo model weights.

## License

[MIT](LICENSE). Original copyright and license notices are preserved.
