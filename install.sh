#!/bin/sh
# thrum installer (curl | bash; also runs under sh).
#
# Install the latest release:
#   curl -fsSL <installer-url> | bash
# Pin a version (the env var must be on the bash side of the pipe):
#   curl -fsSL <installer-url> | VERSION=v1.0.0 bash
# Uninstall:
#   curl -fsSL <installer-url> | bash -s -- --uninstall
#
# Environment variables:
#   VERSION                  release to install: latest (default), v1.0.0,
#                            1.0.0 or v1.0.0-rc.1. "latest" skips
#                            prereleases; pin a prerelease explicitly.
#   INSTALL_DIR              install directory (default: $HOME/.local/bin)
#   THRUM_REPO               GitHub repo that holds the releases
#                            (default: thrum-team/thrum-pro)
#   THRUM_RELEASE_BASE_URL   release base URL (default:
#                            https://github.com/$THRUM_REPO/releases). Must be
#                            https; plain http is accepted only for
#                            127.0.0.1 / localhost (used by the tests).
#
# The archive is verified against the release checksums.txt before anything is
# installed; a missing or mismatched checksum is an error. No sudo is used and
# shell rc files are not edited. The licence terms are NOT accepted for you.
#
# Everything is inside main(), called on the last line, so a truncated download
# runs nothing.

set -eu

TMPD=""
INSTTMP=""

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  [ -n "$INSTTMP" ] && rm -f "$INSTTMP"
  [ -n "$TMPD" ] && rm -r "$TMPD"
  return 0
}

usage() {
  cat <<'USAGE'
thrum installer

Usage: curl -fsSL <installer-url> | bash
       curl -fsSL <installer-url> | VERSION=v1.0.0 bash
       curl -fsSL <installer-url> | bash -s -- --uninstall

Options:
  --uninstall   remove the installed thrum binary and the saved licence files
  --help, -h    show this text

Environment:
  VERSION       latest (default), v1.0.0, 1.0.0, v1.0.0-rc.1
  INSTALL_DIR   install directory (default: $HOME/.local/bin)
USAGE
}

hash_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    return 1
  fi
}

# dl URL OUTFILE: download with hardened curl; a failure is a hard error.
dl() {
  log "Downloading $1"
  rc=0
  # shellcheck disable=SC2086
  curl -fsSL --proto "$PROTO" --proto-redir "$PROTO" --tlsv1.2 --retry 3 --connect-timeout 15 \
    -o "$2" "$1" || rc=$?
  [ "$rc" -eq 0 ] || err "download failed (curl exit status $rc): $1"
}

resolve_latest() {
  rc=0
  loc=$(curl -fsSI --proto "$PROTO" --proto-redir "$PROTO" --tlsv1.2 --retry 3 --connect-timeout 15 \
    -o /dev/null -w '%{redirect_url}' "$BASE/latest") || rc=$?
  case "$loc" in
    */tag/?*) TAG=${loc##*/tag/} ;;
    *) TAG="" ;;
  esac
  if [ "$rc" -ne 0 ] || [ -z "$TAG" ]; then
    err "could not resolve the latest release from $BASE/latest (curl exit status $rc). Latest skips prereleases; set VERSION=vX.Y.Z or VERSION=vX.Y.Z-rc.N and run again."
  fi
}

uninstall() {
  XDG="${XDG_DATA_HOME:-$HOME/.local/share}/thrum"
  log "If a thrum daemon is running, stop it first: thrum daemon stop"
  for f in "$INSTALL_DIR/thrum" "$XDG/LICENSE" "$XDG/THIRD_PARTY_LICENSES"; do
    if [ -e "$f" ]; then
      rm -f "$f" || err "could not remove $f"
      log "Removed $f"
    else
      log "Not present: $f"
    fi
  done
  rmdir "$XDG" >/dev/null 2>&1 || true
  log "Your ~/.thrum directory (licence record, config) was not touched."
}

main() {
  UNINSTALL=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --uninstall) UNINSTALL=1 ;;
      --help|-h) usage; exit 0 ;;
      *) usage >&2; err "unknown option: $1" ;;
    esac
    shift
  done

  INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
  if [ "$UNINSTALL" = 1 ]; then
    uninstall
    exit 0
  fi

  VERSION="${VERSION:-latest}"
  THRUM_REPO="${THRUM_REPO:-thrum-team/thrum-pro}"
  BASE="${THRUM_RELEASE_BASE_URL:-https://github.com/$THRUM_REPO/releases}"
  BASE="${BASE%/}"
  case "$BASE" in
    https://*) PROTO="=https" ;;
    http://127.0.0.1:[0-9]*|http://localhost:[0-9]*)
      case "$BASE" in
        *@*) err "release base URL must not carry credentials (got $BASE)" ;;
      esac
      PROTO="=http,https" ;;
    *) err "release base URL must be https (got $BASE)" ;;
  esac

  case "$(uname -s)" in
    Linux) OS=linux ;;
    Darwin) OS=darwin ;;
    *) err "unsupported operating system: $(uname -s) (supported: Linux, macOS)" ;;
  esac
  case "$(uname -m)" in
    x86_64) ARCH=amd64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) err "unsupported architecture: $(uname -m) (supported: x86_64, arm64)" ;;
  esac

  command -v curl >/dev/null 2>&1 || err "required command not found: curl"
  command -v tar >/dev/null 2>&1 || err "required command not found: tar"
  HASH=$(hash_cmd) || err "no sha256sum or shasum found; cannot verify the download, so nothing was installed"

  TMPD=$(mktemp -d) || err "could not create a temporary directory"
  trap cleanup EXIT
  trap 'exit 1' INT TERM HUP

  if [ "$VERSION" = latest ]; then
    resolve_latest
  else
    TAG="v${VERSION#v}"
  fi
  case "$TAG" in
    v[0-9]*) ;;
    *) err "invalid version: $TAG (expected vX.Y.Z or vX.Y.Z-rc.N)" ;;
  esac
  case "$TAG" in
    *[!A-Za-z0-9._+-]*) err "invalid version: $TAG (expected vX.Y.Z or vX.Y.Z-rc.N)" ;;
  esac
  VER="${TAG#v}"
  ARCHIVE="thrum_${VER}_${OS}_${ARCH}.tar.gz"
  log "Installing thrum $TAG ($OS/$ARCH)"

  dl "$BASE/download/$TAG/$ARCHIVE" "$TMPD/$ARCHIVE"
  dl "$BASE/download/$TAG/checksums.txt" "$TMPD/checksums.txt"

  # Exactly one line whose filename field equals the archive name.
  n=$(awk -v f="$ARCHIVE" '$2 == f { c++ } END { print c + 0 }' "$TMPD/checksums.txt")
  [ "$n" -eq 1 ] || err "checksums.txt has $n entries for $ARCHIVE (need exactly 1); nothing was installed"
  want=$(awk -v f="$ARCHIVE" '$2 == f { print $1 }' "$TMPD/checksums.txt")
  # shellcheck disable=SC2086
  got=$($HASH "$TMPD/$ARCHIVE" | awk '{ print $1 }')
  [ -n "$got" ] || err "could not compute the sha256 of $ARCHIVE"
  [ "$got" = "$want" ] || err "checksum mismatch for $ARCHIVE (expected $want, got $got); nothing was installed"
  log "Checksum OK"

  mkdir "$TMPD/x"
  tar -xzf "$TMPD/$ARCHIVE" -C "$TMPD/x" || err "could not extract $ARCHIVE"
  if [ ! -f "$TMPD/x/thrum" ] || [ -L "$TMPD/x/thrum" ]; then
    err "$ARCHIVE has no regular file 'thrum' at its root"
  fi
  [ -f "$TMPD/x/LICENSE" ] || err "$ARCHIVE has no LICENSE at its root"

  DEST="$INSTALL_DIR/thrum"
  UPGRADE=0
  [ -e "$DEST" ] && UPGRADE=1

  # Same-dir temp + atomic mv: safe to overwrite a binary that is running.
  if mkdir -p "$INSTALL_DIR" 2>/dev/null \
     && INSTTMP=$(mktemp "$INSTALL_DIR/.thrum-install.XXXXXX" 2>/dev/null) \
     && cp "$TMPD/x/thrum" "$INSTTMP" && chmod 755 "$INSTTMP" \
     && mv -f "$INSTTMP" "$DEST"; then
    INSTTMP=""
  else
    log "Could not write to $INSTALL_DIR. Install manually, e.g.:"
    log "  tar -xzf <downloaded $ARCHIVE> thrum && sudo cp thrum /usr/local/bin/thrum"
    err "thrum was NOT installed"
  fi

  if [ "$OS" = darwin ] && command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$DEST" >/dev/null 2>&1 || true
  fi
  log "Installed thrum -> $DEST"

  XDG="${XDG_DATA_HOME:-$HOME/.local/share}/thrum"
  LICDIR=""
  if mkdir -p "$XDG" 2>/dev/null && cp "$TMPD/x/LICENSE" "$XDG/LICENSE" 2>/dev/null; then
    LICDIR="$XDG"
    [ ! -f "$TMPD/x/THIRD_PARTY_LICENSES" ] || cp "$TMPD/x/THIRD_PARTY_LICENSES" "$XDG/THIRD_PARTY_LICENSES" 2>/dev/null || true
  fi

  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      log ""
      log "NOTE: $INSTALL_DIR is not on your PATH. Add it (e.g. to your shell rc file):"
      log "  export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
  other=$(command -v thrum 2>/dev/null || true)
  if [ -n "$other" ] && [ "$other" != "$DEST" ]; then
    log ""
    log "WARNING: another thrum is earlier on your PATH: $other"
    log "That one runs instead of $DEST until you remove it or reorder PATH."
  fi

  log ""
  "$DEST" --version || log "WARNING: could not run $DEST --version"

  log ""
  if [ -n "$LICDIR" ]; then
    log "Licence: the terms are saved in $LICDIR/LICENSE (third-party notices in"
    log "$LICDIR/THIRD_PARTY_LICENSES). This installer does not accept them for you."
  else
    log "Licence: the terms are the LICENSE file inside the release archive. This"
    log "installer does not accept them for you."
  fi
  log "The first thrum command prompts you to accept. The only non-interactive"
  log "route is to set THRUM_ACCEPT_EULA=<the exact EULA version the prompt shows>."
  if [ "$UPGRADE" = 1 ]; then
    log ""
    log "Upgrade: restart a running daemon so it uses the new binary: thrum daemon restart"
  fi
  log ""
  log "Next step: run 'thrum init' inside a git repository."
}

main "$@"
