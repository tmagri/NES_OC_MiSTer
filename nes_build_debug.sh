#!/usr/bin/env bash
# =============================================================================
# nes_build_debug.sh — NES OC MiSTer: Compile → Deploy → Launch
# =============================================================================
#
# Usage:
#   ./nes_build_debug.sh [rom]          Deploy existing .rbf (+ optional test
#                                       rom), launch the core via MGL
#   ./nes_build_debug.sh --compile      Compile first via Docker, then deploy
#   ./nes_build_debug.sh --no-launch    Deploy but don't auto-launch the core
#   ./nes_build_debug.sh --no-reboot    (legacy alias of --no-launch)
#   ./nes_build_debug.sh --kill         Kill stuck Docker/Quartus processes
#
#   [rom] — optional path to a .nes file (first non-flag argument). It is
#           copied to the MiSTer and auto-loaded via auto_boot.mgl. Without
#           it the core launches with no ROM attached.
#
# Requirements:
#   - SSH key-based access to root@192.168.1.131 (MiSTer)
#   - output_files/NES.rbf must exist (or use --compile to build it)
#
# Examples:
#   ./nes_build_debug.sh --compile ~/roms/Super\ Mario\ Bros.nes
#   ./nes_build_debug.sh                 # redeploy current .rbf, no ROM
# =============================================================================

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
QPF_FILE="$PROJECT_DIR/NES.qpf"
RBF_FILE="$PROJECT_DIR/output_files/NES.rbf"

MISTER_HOST="192.168.1.131"
MISTER_USER="root"
MISTER_SSH="${MISTER_USER}@${MISTER_HOST}"
MISTER_CORE_DIR="/media/fat/_Console"
MISTER_RBF_PATH="${MISTER_CORE_DIR}/NES.rbf"
# The OSD's NES entry loads the canonical games/NES/NES.rbf — always keep it
# in sync so a manual core launch can never run a stale build.
MISTER_LIVE_RBF="/media/fat/games/NES/NES.rbf"

DOCKER_BIN="${DOCKER_BIN:-/Applications/Docker.app/Contents/Resources/bin/docker}"
QUARTUS_IMAGE="ryanfb/quartus-mister"

SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o LogLevel=ERROR -o BatchMode=yes"

# ─── Flags ────────────────────────────────────────────────────────────────────
DO_COMPILE=false
DO_LAUNCH=true
ROM_PATH=""
DO_KILL=false

for arg in "$@"; do
    case "$arg" in
        --compile)      DO_COMPILE=true ;;
        --no-launch|--no-reboot) DO_LAUNCH=false ;;
        --kill)         DO_KILL=true ;;
        --help|-h)
            sed -n '4,20p' "$0" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            if [[ "$arg" != -* && -z "$ROM_PATH" ]]; then ROM_PATH="$arg";
            else echo "Unknown flag: $arg  (try --help)" >&2; exit 1; fi
            ;;
    esac
done

# ─── ANSI colours ─────────────────────────────────────────────────────────────
RED=$'\e[1;31m';  GRN=$'\e[1;32m';  YLW=$'\e[1;33m'
BLU=$'\e[1;34m';  CYN=$'\e[1;36m';  RST=$'\e[0m'
BOLD=$'\e[1m'

log()  { echo "${BLU}▶${RST} ${BOLD}$*${RST}"; }
ok()   { echo "${GRN}✔${RST} $*"; }
warn() { echo "${YLW}⚠${RST}  $*"; }
fail() { echo "${RED}✘${RST} $*" >&2; exit 1; }
step() { echo; echo "${CYN}━━━ $* ━━━${RST}"; }

# ─── Compile-phase lock (same rationale as ti89_build_debug.sh) ──────────────
BUILD_LOCK="${PROJECT_DIR}/debug/.buildlock"

build_lock_wait() {
    if [ -d "$BUILD_LOCK" ]; then
        local owner
        owner=$(cat "$BUILD_LOCK/pid" 2>/dev/null || echo "?")
        if [ -n "$owner" ] && [ "$owner" != "$$" ] && kill -0 "$owner" 2>/dev/null; then
            warn "Another compile is running (pid $owner) — waiting for it to finish"
            while [ -d "$BUILD_LOCK" ] && kill -0 "$owner" 2>/dev/null; do sleep 10; done
        else
            rm -rf "$BUILD_LOCK"
        fi
    fi
    while pgrep -f "quartus_sh --flow compile" >/dev/null 2>&1; do
        warn "quartus_sh compile in flight (no lock) — waiting"
        sleep 10
    done
}

build_lock_acquire() {
    mkdir -p "$(dirname "$BUILD_LOCK")"
    if ! mkdir "$BUILD_LOCK" 2>/dev/null; then
        build_lock_wait
        mkdir "$BUILD_LOCK" 2>/dev/null || fail "cannot acquire build lock"
    fi
    echo "$$" > "$BUILD_LOCK/pid"
}

build_lock_release() {
    [ -d "$BUILD_LOCK" ] && [ "$(cat "$BUILD_LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$BUILD_LOCK"
}

# =============================================================================
if $DO_KILL; then
    step "Killing stuck compile processes and clearing locks"
    if [[ -x "$DOCKER_BIN" ]]; then
        CONTAINERS=$("$DOCKER_BIN" ps -q --filter ancestor="$QUARTUS_IMAGE" 2>/dev/null || echo "")
        [[ -n "$CONTAINERS" ]] && "$DOCKER_BIN" kill $CONTAINERS >/dev/null 2>&1 || true
    fi
    pkill -f "quartus_sh" 2>/dev/null || true
    rm -rf "$BUILD_LOCK"
    ok "Cleanup complete."
    exit 0
fi

# =============================================================================
step "Pre-flight checks"
[[ -f "$QPF_FILE" ]] || fail "Not in project root — NES.qpf not found at $QPF_FILE"
log "Project: $PROJECT_DIR"

if [[ -n "$ROM_PATH" ]]; then
    [[ -f "$ROM_PATH" ]] || fail "ROM not found: $ROM_PATH"
    ROM_BASENAME="$(basename "$ROM_PATH")"
    ok "Test ROM: $ROM_BASENAME ($(du -h "$ROM_PATH" | cut -f1))"
fi

if $DO_COMPILE; then
    [[ -x "$DOCKER_BIN" ]] || fail "Docker binary not found at $DOCKER_BIN"
    if ! "$DOCKER_BIN" info &>/dev/null; then
        warn "Docker Desktop not running — attempting to start..."
        open -a Docker || true
        deadline=$((SECONDS + 60))
        while ! "$DOCKER_BIN" info &>/dev/null; do
            if [[ $SECONDS -ge $deadline ]]; then fail "Docker Desktop did not start within 60 s"; fi
            sleep 2
        done
    fi
    ok "Docker is running"
else
    [[ -f "$RBF_FILE" ]] || fail ".rbf not found at $RBF_FILE — run with --compile to build it"
    ok "RBF found: output_files/NES.rbf ($(du -h "$RBF_FILE" | cut -f1), $(date -r "$RBF_FILE" '+%Y-%m-%d %H:%M'))"
fi

log "Checking MiSTer SSH at $MISTER_HOST..."
ssh $SSH_OPTS "$MISTER_SSH" "true" 2>/dev/null \
    || fail "Cannot reach MiSTer at $MISTER_HOST — is it powered on and connected?"
ok "MiSTer SSH reachable"

# =============================================================================
if $DO_COMPILE; then
    step "Phase 1 — Quartus Compilation (Docker)"
    log "This typically takes 30–60 minutes."
    COMPILE_LOG="/tmp/nes_quartus_build.log"
    COMPILE_START="$(date +%s)"

    build_lock_wait
    build_lock_acquire
    trap build_lock_release EXIT INT TERM

    set +e
    "$DOCKER_BIN" run --rm \
        --platform linux/amd64 \
        -v "${PROJECT_DIR}:/build:rw" \
        -w /build \
        "$QUARTUS_IMAGE" \
        bash -c "export PATH=\$PATH:/opt/intelFPGA_lite/17.0/quartus/bin:/intelFPGA_lite/17.0/quartus/bin && grep -q 'NUM_PARALLEL_PROCESSORS 1' NES.qsf || echo 'set_global_assignment -name NUM_PARALLEL_PROCESSORS 1' >> NES.qsf; quartus_sh --flow compile NES.qpf" \
        > "$COMPILE_LOG" 2>&1
    COMPILE_EXIT=$?
    set -e
    build_lock_release

    grep -E "^(Error|Critical)" "$COMPILE_LOG" | head -10 || true

    if [[ $COMPILE_EXIT -ne 0 ]] || grep -q "^Error" "$COMPILE_LOG"; then
        echo "${RED}─── Compilation Errors ───${RST}"
        grep "^Error" "$COMPILE_LOG" | head -20 || true
        fail "Quartus compilation failed — full log at $COMPILE_LOG"
    fi

    # RBF can lag behind through the Docker/macOS file sync — poll briefly
    RBF_OK=0
    for _ in $(seq 1 30); do
        if [[ -f "$RBF_FILE" && "$(date -r "$RBF_FILE" '+%s')" -gt "$COMPILE_START" ]]; then RBF_OK=1; break; fi
        sleep 2
    done
    [[ "$RBF_OK" == 1 ]] || fail "Compilation finished but a fresh $RBF_FILE was not produced"
    ok "Compiled successfully → output_files/NES.rbf ($(du -h "$RBF_FILE" | cut -f1))"
fi

# =============================================================================
step "Phase 2 — Deploy to MiSTer ($MISTER_HOST)"

ssh $SSH_OPTS "$MISTER_SSH" "mkdir -p ${MISTER_CORE_DIR}" \
    || fail "Cannot create $MISTER_CORE_DIR on MiSTer"

log "Copying NES.rbf → ${MISTER_SSH}:${MISTER_RBF_PATH}"
scp -O $SSH_OPTS "$RBF_FILE" "${MISTER_SSH}:${MISTER_RBF_PATH}" \
    || fail "SCP of .rbf failed"
ok "NES.rbf deployed ($(du -h "$RBF_FILE" | cut -f1))"
log "Syncing canonical core → ${MISTER_LIVE_RBF}"
ssh $SSH_OPTS "$MISTER_SSH" "cp ${MISTER_RBF_PATH} ${MISTER_LIVE_RBF} && sync" \
    || warn "Could not sync canonical core path"

if [[ -n "$ROM_PATH" ]]; then
    log "Copying $ROM_BASENAME → ${MISTER_SSH}:${MISTER_CORE_DIR}/"
    scp -O $SSH_OPTS "$ROM_PATH" "${MISTER_SSH}:${MISTER_CORE_DIR}/" \
        || fail "SCP of ROM failed"
    ok "$ROM_BASENAME deployed"
fi

ssh $SSH_OPTS "$MISTER_SSH" "sync" 2>/dev/null || true

if $DO_LAUNCH; then
    step "Phase 3 — Launch core"
    if [[ -n "$ROM_PATH" ]]; then
        log "Generating auto-boot MGL (with $ROM_BASENAME)..."
        ssh $SSH_OPTS "$MISTER_SSH" "cat << 'EOF' > ${MISTER_CORE_DIR}/auto_boot.mgl
<mistergamedescription>
    <rbf>games/NES</rbf>
    <file delay=\"2\" type=\"f\" index=\"0\" path=\"$ROM_BASENAME\"/>
</mistergamedescription>
EOF"
    else
        log "Generating auto-boot MGL (no ROM)..."
        ssh $SSH_OPTS "$MISTER_SSH" "cat << 'EOF' > ${MISTER_CORE_DIR}/auto_boot.mgl
<mistergamedescription>
    <rbf>games/NES</rbf>
</mistergamedescription>
EOF"
    fi

    log "Launching NES core via MiSTer_cmd..."
    ssh $SSH_OPTS "$MISTER_SSH" "echo 'load_core ${MISTER_CORE_DIR}/auto_boot.mgl' > /dev/MiSTer_cmd"
    ok "Core launched — check your screen."
    echo
    echo "${BOLD}Test checklist:${RST}"
    echo "  1. OC Off:        game must boot and run at 60 fps"
    echo "  2. OSD → CPU Overclock → Plus/Turbo/Maximum (core reloads)"
    echo "  3. OSD → OC Method → CE Turbo: faster vblank processing"
    echo "  4. Watch for: sprite-0 splits (SMB), \$2006 scroll (Tetris), DMC audio"
else
    ok "Deployed (launch skipped)."
fi
