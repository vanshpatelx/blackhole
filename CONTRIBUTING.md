# Contributing to Black Hole

Thanks for helping out! Black Hole is a small native macOS app written in Swift and SwiftUI.

## Getting set up

```bash
brew install xcodegen
make run        # build and launch
make demo       # launch with throwaway sample data
make test       # unit tests
```

`BlackHole.xcodeproj` is generated from `project.yml` and isn't committed. Run `make project` after pulling changes that touch `project.yml` or add files.

### Handy launch arguments

Pass these after `--args` when opening the app, or set them in the Xcode scheme:

| Argument | Effect |
|---|---|
| `-demoData YES` | Use an in-memory store with sample tasks, notes and a week of focus history |
| `-openWorkspace YES` | Open the workspace on launch |
| `-openTab insights` | Pick the tab to open (`workspace`, `insights`, `settings`) |
| `-openFloating YES` | Open the workspace from the floating button instead of the notch |

## Making changes

- Keep changes focused: one feature or fix per pull request.
- Match the surrounding code style. Views live next to their feature, and shared UI lives in `DesignSystem/`.
- UI changes: include a before/after screenshot in the PR (`make demo` gives clean data).
- Logic changes: add or update tests in `BlackHoleTests/`.
- All data stays local unless the user explicitly opts in to something else. Please don't add analytics or network calls.

## Reporting bugs

Open an issue with your macOS version, your Mac model (notch or not, external displays), and steps to reproduce.

## Releasing (maintainers)

1. Bump `MARKETING_VERSION` in `project.yml`.
2. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.
3. The **Release** workflow builds the DMG and publishes a GitHub release with it.
