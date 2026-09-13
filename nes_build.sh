#!/usr/bin/env bash
set -euo pipefail

# Compile the NES MiSTer core using the Quartus Docker image.
# Usage: ./nes_build.sh [--qpf NES.qpf] [--image IMAGE]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
QPF_FILE="$PROJECT_DIR/NES.qpf"
QUARTUS_IMAGE="${QUARTUS_IMAGE:-ryanfb/quartus-mister}"
DOCKER_BIN="${DOCKER_BIN:-}"
BUILD_LOCK="$PROJECT_DIR/.nes_build.lock"

usage() {
	cat <<EOF
Usage: $(basename "$0") [options]

Compile an NES MiSTer Quartus project in Docker.

Options:
  --qpf FILE       Quartus project file, default: NES.qpf
  --image IMAGE    Docker image, default: $QUARTUS_IMAGE
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--qpf)
			[[ $# -ge 2 ]] || { echo "Missing value for --qpf" >&2; exit 1; }
			QPF_FILE="$PROJECT_DIR/$2"
			shift 2
			;;
		--image)
			[[ $# -ge 2 ]] || { echo "Missing value for --image" >&2; exit 1; }
			QUARTUS_IMAGE="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
done

[[ -f "$QPF_FILE" ]] || { echo "Quartus project not found: $QPF_FILE" >&2; exit 1; }

if [[ -z "$DOCKER_BIN" ]]; then
	if command -v docker >/dev/null 2>&1; then
		DOCKER_BIN="$(command -v docker)"
	elif [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
		DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"
	else
		echo "Docker was not found. Install Docker Desktop or set DOCKER_BIN." >&2
		exit 1
	fi
fi

"$DOCKER_BIN" info >/dev/null 2>&1 || {
	echo "Docker Desktop is not running." >&2
	exit 1
}

PROJECT_REVISION="$(sed -n 's/^PROJECT_REVISION = "\([^"]*\)"/\1/p' "$QPF_FILE")"
[[ -n "$PROJECT_REVISION" ]] || {
	echo "Could not determine PROJECT_REVISION from $QPF_FILE" >&2
	exit 1
}
QPF_NAME="$(basename "$QPF_FILE")"
QSF_NAME="${QPF_NAME%.qpf}.qsf"
RBF_FILE="$PROJECT_DIR/output_files/$PROJECT_REVISION.rbf"

if ! "$DOCKER_BIN" image inspect "$QUARTUS_IMAGE" >/dev/null 2>&1; then
	echo "Pulling Docker image: $QUARTUS_IMAGE"
	"$DOCKER_BIN" pull "$QUARTUS_IMAGE"
fi

if ! mkdir "$BUILD_LOCK" 2>/dev/null; then
	echo "Another NES build is already running: $BUILD_LOCK" >&2
	exit 1
fi
cleanup() {
	rmdir "$BUILD_LOCK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Compiling $PROJECT_REVISION with $QUARTUS_IMAGE"
"$DOCKER_BIN" run --rm \
	--platform linux/amd64 \
	-v "$PROJECT_DIR:/build:rw" \
	-w /build \
	"$QUARTUS_IMAGE" \
	bash -c "export PATH=\"\$PATH:/opt/intelFPGA_lite/17.0/quartus/bin:/intelFPGA_lite/17.0/quartus/bin\" && if ! grep -q '^[[:space:]]*set_global_assignment -name NUM_PARALLEL_PROCESSORS[[:space:]]' '$QSF_NAME'; then echo 'set_global_assignment -name NUM_PARALLEL_PROCESSORS 1' >> '$QSF_NAME'; fi && quartus_sh --flow compile '$QPF_NAME'"

# The RBF can take a moment to appear through the Docker bind mount (macOS
# file-sync lag), so poll briefly before declaring failure.
RBF_OK=0
for _ in $(seq 1 20); do
	if [[ -f "$RBF_FILE" ]]; then RBF_OK=1; break; fi
	sleep 1
done
if [[ "$RBF_OK" != 1 ]]; then
	echo "Compilation finished but no RBF was produced: $RBF_FILE" >&2
	exit 1
fi

echo "Compiled successfully: $RBF_FILE"