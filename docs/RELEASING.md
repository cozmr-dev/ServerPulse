# Releasing ServerPulse

1. Update `CFBundleShortVersionString` in `Resources/Info.plist` (e.g. `1.1.0`) and commit.
2. Tag and push:
   ```bash
   git tag v1.1.0
   git push origin main v1.1.0
   ```
3. The **Release** workflow builds the universal DMG, publishes a GitHub release with the DMG, its SHA-256 checksum and a generated Homebrew cask (`serverpulse.rb`).

## Homebrew tap (one-time setup)

1. Create a public repository named **`homebrew-tap`** under the same GitHub account.
2. Add the `serverpulse.rb` file from a release as `Casks/serverpulse.rb` and push.
3. Users can now install with:
   ```bash
   brew install --cask <owner>/tap/serverpulse
   ```

For every new release, replace `Casks/serverpulse.rb` with the file attached to that release
(or generate it locally with `scripts/make-cask.sh <version> <owner>/<repo>`).

## App icon

The icon is generated from SF Symbols:

```bash
swift scripts/make-icon.swift    # writes Resources/AppIcon.icns and docs/icon.png
```
