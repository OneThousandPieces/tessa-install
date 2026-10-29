#!/usr/bin/env bash
# Tessa on a Mac, step one: the public part of the installer. A new teammate pastes one line in Terminal:
#   /bin/bash -c "$(curl -fsSL <where this file is published>)"
# (bash -c, not curl | bash: the sign-ins below need the keyboard). It needs nothing but a Mac and the GitHub invite
# to OneThousandPieces. It gets Apple's developer tools (git), the GitHub CLI, signs in to GitHub in the browser,
# copies otp-os to ~/GitHub/otp-os, then hands over to scripts/install-tessa.sh in that copy, which does the rest.
# This file is published as it is, so it holds no secrets and nothing about clients. Safe to run again: whatever is
# already done is skipped, and an existing copy is only updated when it's on main with nothing changed.
#   TESSA_DIR=<folder>   put the copy somewhere else
#   TESSA_INSTALL_CI=1   a test run: stops after the copy, before anything is installed in it (or before the GitHub
#                        sign-in when nobody is signed in, as on GitHub's own Macs)
#   TESSA_GH_FORCE=1     downloads the GitHub CLI even when one is there (the Mac check)
set -euo pipefail
ORG=OneThousandPieces
REPO=otp-os
DIR="${TESSA_DIR:-$HOME/GitHub/otp-os}"
BIN="$HOME/.local/bin"
export PATH="$BIN:/opt/homebrew/bin:$PATH"

step() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
ok() { printf '   \033[32m✓\033[0m %s\n' "$*"; }
stop() { printf '\n\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || stop "This installer is for a Mac. On Windows, paste the PowerShell line instead."
printf '\033[1mSetting up Tessa on this Mac.\033[0m It takes about ten minutes; it stops when you need to click or sign in.\n'

step "1/4  Apple's developer tools (git)"
if xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
  ok "already installed"
else
  xcode-select --install >/dev/null 2>&1 || true
  echo "   A window opened: click Install (not Get Xcode) and wait for it to finish. This continues by itself."
  until xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; do sleep 5; done
  ok "installed"
fi

step "2/4  The GitHub CLI (Tessa saves your work to GitHub with it)"
GH=""
if [ -z "${TESSA_GH_FORCE:-}" ]; then
  GH="$(command -v gh 2>/dev/null || true)"
  [ -n "$GH" ] || { [ -x "$BIN/gh" ] && GH="$BIN/gh"; } || true
fi
if [ -n "$GH" ]; then
  ok "already installed"
else
  # GitHub's own macOS zip for this chip, checked against the release's checksums; no Homebrew or admin password.
  case "$(uname -m)" in arm64) ARCH=arm64 ;; *) ARCH=amd64 ;; esac
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  REL="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest)"
  URL="$(printf '%s' "$REL" | grep -o "https://[^\"]*macOS_${ARCH}\.zip" | head -1)"
  SUMS="$(printf '%s' "$REL" | grep -o 'https://[^"]*_checksums\.txt' | head -1)"
  [ -n "$URL" ] && [ -n "$SUMS" ] || stop "Couldn't find the GitHub CLI download. Check the internet connection and run the line again."
  curl -fsSL "$URL" -o "$TMP/${URL##*/}"
  curl -fsSL "$SUMS" -o "$TMP/sums.txt"
  WANT="$(grep " ${URL##*/}\$" "$TMP/sums.txt" | cut -d' ' -f1)"
  HAVE="$(shasum -a 256 "$TMP/${URL##*/}" | cut -d' ' -f1)"
  [ -n "$WANT" ] && [ "$WANT" = "$HAVE" ] || stop "The GitHub CLI download didn't match its checksum, so it wasn't installed. Run the line again."
  unzip -q "$TMP/${URL##*/}" -d "$TMP"
  mkdir -p "$BIN" "$HOME/.local/share"
  rm -rf "$HOME/.local/share/gh-cli"
  mv "$TMP"/gh_*_macOS_"$ARCH" "$HOME/.local/share/gh-cli"
  ln -sf "$HOME/.local/share/gh-cli/bin/gh" "$BIN/gh"
  GH="$BIN/gh"
  ok "installed"
fi

step "3/4  Sign in to GitHub"
if [ -n "${TESSA_INSTALL_CI:-}" ] && ! "$GH" auth status >/dev/null 2>&1; then
  echo "   Test run with nobody to sign in: stopping here."
  exit 0
fi
if "$GH" auth status >/dev/null 2>&1; then
  ok "signed in as $("$GH" api user --jq .login)"
else
  echo "   Press Enter, a browser tab opens: type the code shown below and click Authorize."
  "$GH" auth login --hostname github.com --git-protocol https --web
fi
"$GH" auth setup-git >/dev/null 2>&1 || true
LOGIN="$("$GH" api user --jq .login)"
state() { "$GH" api "user/memberships/orgs/$ORG" --jq .state 2>/dev/null || true; }
case "$(state)" in
  active) ok "member of $ORG" ;;
  pending)
    echo "   Your invite to $ORG is waiting: click Join in the tab that opens. This continues by itself."
    open "https://github.com/orgs/$ORG/invitation" || true
    until [ "$(state)" = active ]; do sleep 5; done
    ok "joined $ORG"
    ;;
  *) stop "GitHub account $LOGIN isn't in $ORG yet. Ask Iulian to invite $LOGIN, then run the line again." ;;
esac

step "4/4  Your copy of otp-os"
case "$DIR" in *OneDrive*|*"Mobile Documents"*) stop "$DIR is inside a synced folder, which corrupts git. Run the line again with TESSA_DIR set to a plain folder." ;; esac
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" remote get-url origin | grep -Eq "github\.com[:/]$ORG/$REPO(\.git)?/?\$" || stop "$DIR holds another repository. Move it away, or run the line again with TESSA_DIR set to another folder."
  if [ "$(git -C "$DIR" branch --show-current)" = main ] && [ -z "$(git -C "$DIR" status --porcelain)" ]; then
    git -C "$DIR" pull -q --ff-only && ok "updated $DIR"
  else
    ok "$DIR is there (left as it is: it's on another branch or has changes)"
  fi
elif [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
  stop "$DIR already exists and isn't a copy of otp-os. Move it away, or run the line again with TESSA_DIR set to another folder."
else
  mkdir -p "$(dirname "$DIR")"
  "$GH" repo clone "$ORG/$REPO" "$DIR" -- -q
  ok "copied to $DIR"
fi

[ -z "${TESSA_INSTALL_CI:-}" ] || { echo; echo "Stopping after the copy (TESSA_INSTALL_CI)."; exit 0; }
exec /bin/bash "$DIR/scripts/install-tessa.sh"
