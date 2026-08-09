#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_ASSET_BYTES=$((2 * 1024 * 1024 * 1024))
XZ_LEVEL=6
TAG=""
TITLE=""
NOTES_FILE=""
REPOSITORY=""
TARGET=""
DRAFT=no
PRERELEASE=no
PREPARE_ONLY=no
FORCE=no
IMAGES=()

usage() {
    cat <<'EOF'
usage: image-tools/publish-release.sh --tag TAG [options] IMAGE.img [IMAGE.img ...]

Compress one or more images with XZ, create SHA-256 files, enforce GitHub's
2 GiB per-asset limit, and create a GitHub release containing those assets.
The original images are preserved.

Required:
  --tag TAG             Release tag to create

Options:
  --title TITLE         Release title (default: TAG)
  --notes-file FILE     Markdown release notes; otherwise generate notes
  --repo OWNER/REPO     GitHub repository; otherwise use the current git remote
  --target COMMIT       Commit or branch for a new tag (default: current commit)
  --level 0-9           XZ compression level (default: 6)
  --draft               Create a draft release
  --prerelease          Mark the release as a prerelease
  --prepare-only        Compress and checksum without contacting GitHub
  --force               Replace existing .xz and .sha256 files
  --help, -h            Show this help

Examples:
  image-tools/publish-release.sh --tag v1.0.0 output/factory/*.img
  image-tools/publish-release.sh --tag v1.0.0 --prepare-only image.img
EOF
}

die() {
    echo "${SCRIPT_NAME}: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

human_size() {
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$1"
    else
        printf '%s bytes\n' "$1"
    fi
}

while (($#)); do
    case "$1" in
        --tag)
            (($# >= 2)) || die "--tag requires a value"
            TAG="$2"
            shift 2
            ;;
        --title)
            (($# >= 2)) || die "--title requires a value"
            TITLE="$2"
            shift 2
            ;;
        --notes-file)
            (($# >= 2)) || die "--notes-file requires a value"
            NOTES_FILE="$2"
            shift 2
            ;;
        --repo)
            (($# >= 2)) || die "--repo requires OWNER/REPO"
            REPOSITORY="$2"
            shift 2
            ;;
        --target)
            (($# >= 2)) || die "--target requires a value"
            TARGET="$2"
            shift 2
            ;;
        --level)
            (($# >= 2)) || die "--level requires a value"
            XZ_LEVEL="$2"
            shift 2
            ;;
        --draft)
            DRAFT=yes
            shift
            ;;
        --prerelease)
            PRERELEASE=yes
            shift
            ;;
        --prepare-only)
            PREPARE_ONLY=yes
            shift
            ;;
        --force)
            FORCE=yes
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            while (($#)); do
                IMAGES+=("$1")
                shift
            done
            ;;
        -* )
            die "unknown option: $1"
            ;;
        *)
            IMAGES+=("$1")
            shift
            ;;
    esac
done

[[ -n "$TAG" ]] || die "--tag is required"
[[ "$TAG" != -* ]] || die "release tag cannot begin with '-': $TAG"
[[ "$XZ_LEVEL" =~ ^[0-9]$ ]] || die "--level must be a number from 0 through 9"
((${#IMAGES[@]} > 0)) || die "at least one .img file is required"

if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" && -r "$NOTES_FILE" ]] || die "release notes are not readable: $NOTES_FILE"
    NOTES_FILE="$(realpath "$NOTES_FILE")"
fi
if [[ -n "$REPOSITORY" && ! "$REPOSITORY" =~ ^[^/]+/[^/]+$ ]]; then
    die "--repo must use OWNER/REPO format"
fi

require_command realpath
require_command sha256sum
require_command stat
require_command xz

compressed_assets=()
checksum_assets=()
declare -A asset_names=()

for image in "${IMAGES[@]}"; do
    [[ -f "$image" && -r "$image" ]] || die "image is not readable: $image"
    [[ "$image" == *.img ]] || die "image must end in .img: $image"

    image="$(realpath "$image")"
    compressed="${image}.xz"
    checksum="${compressed}.sha256"
    compressed_name="$(basename "$compressed")"
    checksum_name="$(basename "$checksum")"

    [[ -z "${asset_names[$compressed_name]:-}" ]] || die "duplicate release asset name: $compressed_name"
    [[ -z "${asset_names[$checksum_name]:-}" ]] || die "duplicate release asset name: $checksum_name"
    asset_names["$compressed_name"]=1
    asset_names["$checksum_name"]=1

    if [[ -e "$compressed" || -e "$checksum" ]]; then
        [[ "$FORCE" == yes ]] || die "output already exists for $image; remove it or use --force"
    fi

    echo "Compressing $(basename "$image") with xz -${XZ_LEVEL}..."
    xz_args=(-T0 "-${XZ_LEVEL}" --keep)
    [[ "$FORCE" == yes ]] && xz_args+=(--force)
    xz "${xz_args[@]}" -- "$image"

    compressed_size="$(stat -c %s "$compressed")"
    if ((compressed_size >= MAX_ASSET_BYTES)); then
        die "$(basename "$compressed") is $(human_size "$compressed_size"); GitHub release assets must be under 2 GiB"
    fi

    (
        cd "$(dirname "$compressed")"
        sha256sum "$(basename "$compressed")" >"$(basename "$checksum")"
    )
    xz --test -- "$compressed"
    (
        cd "$(dirname "$checksum")"
        sha256sum --check "$(basename "$checksum")" >/dev/null
    )

    echo "Prepared: $compressed ($(human_size "$compressed_size"))"
    echo "Checksum: $checksum"
    compressed_assets+=("$compressed")
    checksum_assets+=("$checksum")
done

if [[ "$PREPARE_ONLY" == yes ]]; then
    echo "Preparation complete; GitHub release creation was skipped."
    exit 0
fi

require_command gh
require_command git
gh auth status --hostname github.com >/dev/null 2>&1 || die "GitHub CLI is not authenticated; run: gh auth login"

gh_args=(--title "${TITLE:-$TAG}")
if [[ -n "$REPOSITORY" ]]; then
    gh_args+=(--repo "$REPOSITORY")
fi
if [[ -z "$TARGET" ]]; then
    TARGET="$(git -C "$REPO_DIR" rev-parse HEAD)"
fi
gh_args+=(--target "$TARGET")
if [[ -n "$NOTES_FILE" ]]; then
    gh_args+=(--notes-file "$NOTES_FILE")
else
    gh_args+=(--generate-notes)
fi
[[ "$DRAFT" == yes ]] && gh_args+=(--draft)
[[ "$PRERELEASE" == yes ]] && gh_args+=(--prerelease)

echo "Creating GitHub release ${TAG} with ${#compressed_assets[@]} image asset(s)..."
release_assets=("${compressed_assets[@]}" "${checksum_assets[@]}")
(
    cd "$REPO_DIR"
    gh release create "$TAG" "${release_assets[@]}" "${gh_args[@]}"
)
