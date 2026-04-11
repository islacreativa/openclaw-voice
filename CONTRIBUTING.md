# Contributing to OpenClaw Voice

Thank you for your interest in contributing! This guide will help you get started.

## Getting Started

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/openclaw-voice.git`
3. **Create a branch** for your work: `git checkout -b feature/your-feature-name`
4. **Make your changes** following the conventions below
5. **Push** to your fork and **open a Pull Request**

## Development Setup

### Relay Server (Node.js)

```bash
cd server/openclaw-relay-server
npm install
node src/index.js
```

Requires Node.js 20+.

### iOS App

1. Open `ios/OpenClawVoice/OpenClawVoice.xcodeproj` in Xcode 15+
2. Set your signing team
3. Build and run on a device or simulator (iOS 17+)

## Code Conventions

### Swift

- Use `@Observable` (iOS 17+), not `ObservableObject`
- Use `async/await` structured concurrency, not completion handlers
- Use `guard` for early returns
- Naming: `camelCase` for variables/functions, `PascalCase` for types
- Document public APIs with `///` doc comments

### Node.js

- Use ESM imports (`import`, not `require`)
- Use `async/await` with `try/catch`
- Use `const` by default, `let` when reassignment is needed

### General

- No cross-platform frameworks — native Swift/SwiftUI only for iOS
- Streaming-first — design for chunked/partial data
- Minimal dependencies — prefer Apple-native APIs

## Pull Request Guidelines

- **One feature per PR** — keep PRs focused and reviewable
- **Describe what and why** — explain the motivation, not just the code changes
- **Reference related issues** — use `Closes #123` or `Relates to #456`
- **Include screenshots** for UI changes
- **Test your changes** — describe how you tested, especially for audio/voice features
- **Keep commits clean** — squash fixup commits before requesting review

## Issue Guidelines

- **Search first** — check if a similar issue already exists
- **Use templates** — select the appropriate issue template (bug, feature, task)
- **Be specific** — include steps to reproduce for bugs, use cases for features

## Areas of Contribution

### Good First Issues

Look for issues labeled [`good first issue`](../../labels/good%20first%20issue) — these are scoped tasks suitable for newcomers.

### Help Wanted

Issues labeled [`help wanted`](../../labels/help%20wanted) are areas where we actively need community support.

### Sprint Tasks

Check the [project board](../../projects) for the current sprint. Unassigned tasks are open for contribution — comment on the issue to claim it.

## Communication

- **Issues** — for bugs, features, and technical discussion
- **Pull Requests** — for code review and collaboration
- **Discussions** — for questions, ideas, and general conversation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
