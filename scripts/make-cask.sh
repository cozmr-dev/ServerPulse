#!/bin/zsh
# Erzeugt den Homebrew-Cask für ein Release.
# Aufruf: scripts/make-cask.sh <Version> <owner/repo> [Pfad zur .sha256-Datei]
# Beispiel: scripts/make-cask.sh 1.0.0 octocat/ServerPulse > serverpulse.rb
set -euo pipefail

VERSION="${1:?Version fehlt, z. B. 1.0.0}"
VERSION="${VERSION#v}"
REPOSITORY="${2:?Repository fehlt, z. B. octocat/ServerPulse}"
SHA_FILE="${3:-build/ServerPulse-${VERSION}.dmg.sha256}"
SHA256="$(cut -d' ' -f1 "$SHA_FILE")"

cat <<CASK
cask "serverpulse" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${REPOSITORY}/releases/download/v#{version}/ServerPulse-#{version}.dmg"
  name "ServerPulse"
  desc "Menu bar app to monitor Linux/NAS servers and their Docker containers over SSH"
  homepage "https://github.com/${REPOSITORY}"

  depends_on macos: ">= :sonoma"

  app "ServerPulse.app"

  zap trash: "~/Library/Preferences/com.serverpulse.ServerPulse.plist"

  caveats <<~EOS
    ServerPulse is not notarized by Apple, so macOS blocks the first launch.
    Open System Settings → Privacy & Security and click "Open Anyway".
  EOS
end
CASK
