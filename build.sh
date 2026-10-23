#!/bin/bash
# Builds Stickermine.app into ./build. Used by both install.sh and CI.
#
# xcodebuild compiles the Xcode project unsigned (CODE_SIGNING_ALLOWED=NO);
# everything about the signature happens here, after the product is copied out
# of DerivedData and stripped.
#
# Code-signing: SIGN_IDENTITY picks the identity and must be a certificate's SHA-1
# hash (40 hex digits). It defaults to the Developer ID Application cert for team
# 8UP5SFXY56 (G2 Sub-CA, expires 2031-09-16). Sign by hash, never by name: the
# keychain can hold several identities with the identical name — the older cert
# Apple is retiring was there too — so a name is ambiguous (codesign refuses to
# choose, and the old `grep | head -1` quietly took the first, older one). An
# identity you set explicitly that isn't usable is an error, even if it's the same
# hash as the default; only the *default* missing (a machine that never had this
# cert) falls back to ad-hoc.
#
# The fallback matters for more than distribution. macOS keys Screen Recording
# to the app's designated requirement — with a Developer ID that's the stable
# "identifier + team OU", but an ad-hoc signature has no cert, so it reduces to
# the binary's cdhash. That changes on *every* build, so each rebuild looks like
# a brand-new app and has to be granted Screen Recording again.
set -e

cd "$(dirname "$0")"

APP_NAME="Stickermine"
BUILD_DIR="./build/${APP_NAME}.app"
PRODUCT="./build/DerivedData/Build/Products/Release/${APP_NAME}.app"
# Mirrored by the pinned hash in .github/workflows/release.yml.
DEFAULT_SIGN_IDENTITY="DEA1A3749B06CF3619F72152EFC35A48E380C4E4"
# Remember whether the caller chose the identity (empty counts as unset): one that
# was chosen and can't be used must fail rather than fall back to ad-hoc — CI
# exports exactly the default hash, so comparing against the default can't tell.
SIGN_IDENTITY_EXPLICIT="${SIGN_IDENTITY:+1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
if ! printf '%s' "$SIGN_IDENTITY" | grep -Eq '^[0-9A-Fa-f]{40}$'; then
    echo "error: SIGN_IDENTITY must be a certificate SHA-1 hash (40 hex digits), not a name." >&2
    exit 1
fi
# `find-identity -v` lists only *valid* identities, so a cert that is expired,
# untrusted or missing its private key is absent here too — "not found" below
# means "not usable", not necessarily "not installed".
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qiE "^ *[0-9]+\) ${SIGN_IDENTITY} "; then
    if [ -n "$SIGN_IDENTITY_EXPLICIT" ]; then
        echo "error: SIGN_IDENTITY=${SIGN_IDENTITY} is not among the valid code-signing identities" >&2
        echo "       (missing, expired, untrusted, or no private key)." >&2
        exit 1
    fi
    SIGN_IDENTITY=""
fi
BUILD_ABS="$PWD/${BUILD_DIR#./}"

# xcodebuild needs a full Xcode. When xcode-select points at the Command Line
# Tools (as on Ethan's Mac), use /Applications/Xcode.app, else Xcode-beta.app.
# CI's runner selects its Xcode itself, so this never fires there.
if [ -z "${DEVELOPER_DIR:-}" ] && [ "$(xcode-select -p 2>/dev/null)" = "/Library/Developer/CommandLineTools" ]; then
    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [ -d "${candidate}/Contents/Developer" ]; then
            export DEVELOPER_DIR="${candidate}/Contents/Developer"
            break
        fi
    done
    if [ -z "${DEVELOPER_DIR:-}" ]; then
        echo "error: xcode-select points at the Command Line Tools and no Xcode.app or Xcode-beta.app is installed." >&2
        exit 1
    fi
fi

# Info.plist's LSMinimumSystemVersion is the one place the supported macOS is set:
# the deployment target is read from it here, and release.yml writes the same
# value into the Homebrew cask's `depends_on macos`. The project's own
# MACOSX_DEPLOYMENT_TARGET must say the same, so a build from Xcode itself can't
# quietly target something else.
MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw Info.plist)"
PROJECT_MIN_MACOS="$(xcodebuild -project "${APP_NAME}.xcodeproj" -target "${APP_NAME}" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/^ *MACOSX_DEPLOYMENT_TARGET = / { print $2; exit }')"
if [ "$PROJECT_MIN_MACOS" != "$MIN_MACOS" ]; then
    echo "error: Info.plist LSMinimumSystemVersion is ${MIN_MACOS}, but the project's" >&2
    echo "       MACOSX_DEPLOYMENT_TARGET is '${PROJECT_MIN_MACOS}'. Make them equal." >&2
    exit 1
fi

# Optional fast pre-check against the API ceiling: CI builds with the macOS 26
# SDK, so a macOS 27-only symbol (even behind #available) fails the release.
# Locally Xcode only has the 27 SDK, but the Command Line Tools ship a 26 SDK to
# type-check against. Skipped on CI (it builds with the 26 SDK anyway) and on
# Macs without that SDK.
CLT_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
SDK26="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [ -z "${CI:-}" ] && [ -x "$CLT_SWIFTC" ] && [ -d "$SDK26" ]; then
    echo "Type-checking against $(basename "$(readlink "$SDK26" || echo "$SDK26")")..."
    SOURCES=()
    while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "${APP_NAME}" -name '*.swift' -print0)
    "$CLT_SWIFTC" -typecheck -swift-version 5 -parse-as-library \
        -sdk "$SDK26" -target "arm64-apple-macos${MIN_MACOS}" "${SOURCES[@]}"
fi

echo "Building ${APP_NAME}..."

rm -rf "${BUILD_DIR}"
# Releases are Apple Silicon only, so the architecture is pinned rather than
# taken from whatever Mac builds.
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
    ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET="${MIN_MACOS}" CODE_SIGNING_ALLOWED=NO \
    -quiet build
ditto "${PRODUCT}" "${BUILD_DIR}"

# The built app must carry exactly the root Info.plist's version and minimum
# macOS: a build setting such as MARKETING_VERSION would silently override them,
# every release would ship as 1.0, and the updater would offer it forever.
for key in CFBundleIdentifier CFBundleExecutable CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion; do
    want="$(plutil -extract "$key" raw Info.plist)"
    got="$(plutil -extract "$key" raw "${BUILD_DIR}/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$got" != "$want" ]; then
        echo "error: built ${key} is '${got}', but Info.plist says '${want}'." >&2
        exit 1
    fi
done

# Local symbols are a large share of the binary and nothing reads them at
# runtime — Swift reflection uses its own metadata sections, not the symbol
# table. An `xcodebuild build` Release product isn't stripped (measured about
# -18%). Has to happen before codesign, or it breaks the signature.
# (-x keeps global symbols; a full strip can break Swift binaries.)
strip -x "${BUILD_DIR}/Contents/MacOS/${APP_NAME}"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: ${SIGN_IDENTITY}"
    # --options runtime is the hardened runtime, which notarization requires.
    # --timestamp gets a trusted timestamp, so the signature outlives the cert.
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "${BUILD_DIR}"
    codesign --verify --strict --verbose=1 "${BUILD_DIR}"
    # Prove who signed it. `codesign -dvv` can't: the old and new certs share a
    # name and team and it prints no hash, so a signature from the wrong one reads
    # identically. The signing certificate's own fingerprint is unambiguous.
    CERT_DIR="$(mktemp -d)"
    ( cd "$CERT_DIR" && codesign -d --extract-certificates "$BUILD_ABS" 2>/dev/null )
    SIGNED_BY="$(openssl x509 -inform DER -in "$CERT_DIR/codesign0" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
    rm -rf "${CERT_DIR:?}"
    if [ "$(printf '%s' "$SIGNED_BY" | tr a-f A-F)" != "$(printf '%s' "$SIGN_IDENTITY" | tr a-f A-F)" ]; then
        echo "error: signed by certificate ${SIGNED_BY}, expected ${SIGN_IDENTITY}." >&2
        exit 1
    fi
    echo "Signed by certificate ${SIGNED_BY}"
else
    echo "Signing identity ${DEFAULT_SIGN_IDENTITY} not among the valid identities — signing ad-hoc."
    echo "  (macOS will forget this app's permissions on every rebuild.)"
    # No --deep: Apple deprecated it for signing, and there is nothing nested
    # in this bundle to descend into anyway.
    codesign --force --sign - "${BUILD_DIR}"
fi

echo "Built ${BUILD_DIR}"
