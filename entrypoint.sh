#!/usr/bin/env bash
set -Eeuo pipefail

# --- Configuration ---
REPO_DIR="${REPO_DIR:-/data/repo}"
OUT_DIR="${OUT_DIR:-/var/www/html}"
IMG_FILE="${IMG_FILE:-/var/www/html/gource.png}"
GIT_URL="${GIT_URL}"
GIT_BRANCH="${GIT_BRANCH:-main}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-600}"
WIDTH="${WIDTH:-1920}"
HEIGHT="${HEIGHT:-1080}"
# Snapshot strategy: latest (default) | start | percent (0.0-1.0)
SNAPSHOT_MODE="${SNAPSHOT_MODE:-latest}"
# If SNAPSHOT_MODE=percent, use SNAPSHOT_POSITION (0.0 - 1.0)
SNAPSHOT_POSITION="${SNAPSHOT_POSITION:-0.9}"

# --- Pre-flight Checks ---
if [[ -z "$GIT_URL" ]]; then
  echo "[ERROR] GIT_URL environment variable is not set. Aborting." >&2
  exit 1
fi

mkdir -p "$REPO_DIR" "$OUT_DIR"

# --- Git Repository Management ---
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "[git] Cloning full history of '$GIT_URL'..."
  git clone --branch "$GIT_BRANCH" "$GIT_URL" "$REPO_DIR"
else
  echo "[git] Repository already exists. Skipping initial clone."
fi
git config --global --add safe.directory "$REPO_DIR"

# --- Repository Analysis Function ---
analyze_repo() {
  local repo_path="$1"
  local commit_count=$(git -C "$repo_path" rev-list --count HEAD 2>/dev/null || echo "0")
  local latest_commit=$(git -C "$repo_path" log -1 --format="%h %s (%cr)" 2>/dev/null || echo "No commits")
  local authors_count=$(git -C "$repo_path" shortlog -sn --all | wc -l 2>/dev/null || echo "0")
  local first_commit=$(git -C "$repo_path" log --reverse --format="%ci" --max-count=1 2>/dev/null || echo "Unknown")
  local last_commit=$(git -C "$repo_path" log -1 --format="%ci" 2>/dev/null || echo "Unknown")
  
  echo "Commits: $commit_count | Authors: $authors_count | Latest: $latest_commit" > "$OUT_DIR/repo_info.txt"
  
  echo "[info] Repository analysis:"
  echo "  Total commits: $commit_count"
  echo "  Total authors: $authors_count"
  echo "  First commit: $first_commit"
  echo "  Latest commit: $last_commit"
  echo "  Latest: $latest_commit"
}

# --- Core Render Function ---
render_image () {
  echo "[git] Pulling latest changes from origin/$GIT_BRANCH..."
  git -C "$REPO_DIR" pull origin "$GIT_BRANCH" || { echo "[WARN] git pull failed, continuing with existing history." >&2; }

  # Analyze the repository
  analyze_repo "$REPO_DIR"

  echo "[render] Starting gource visualization..."
  
  # Determine snapshot strategy (we only need a single representative frame, not an animation)
  local gource_extra_opts=""
  local start_position=""
  case "$SNAPSHOT_MODE" in
    latest)
      # Jump to end of simulation to show most recent commit state
      start_position="--start-position 1.0"
      ;;
    start|earliest)
      start_position="--start-position 0.0"
      ;;
    percent)
      start_position="--start-position ${SNAPSHOT_POSITION}"
      ;;
    *)
      start_position="--start-position 1.0"
      ;;
  esac
  # Make sure idle items don't fade away before we snapshot
  gource_extra_opts+=" ${start_position} --file-idle-time 0"
  echo "[render] Snapshot mode: $SNAPSHOT_MODE ($start_position)"
  
  # Run gource positioned at desired progress and capture the resulting first frame (which now represents that point)
  xvfb-run -a -s "-screen 0 ${WIDTH}x${HEIGHT}x24" bash -c "
    gource '$REPO_DIR' \
      --output-ppm-stream - \
      --stop-at-end \
      '-${WIDTH}x${HEIGHT}' \
      $gource_extra_opts \
      ${GOURCE_OPTS}
  " | ffmpeg -y -v error -f image2pipe -vcodec ppm -i - -frames:v 1 "$IMG_FILE"

  if [[ -f "$IMG_FILE" ]]; then
    local file_size=$(stat -f%z "$IMG_FILE" 2>/dev/null || stat -c%s "$IMG_FILE" 2>/dev/null || echo "unknown")
    date -u +"%Y-%m-%d %H:%M:%SZ" > "$OUT_DIR/last_update.txt"
    echo "[render] Image successfully updated (${file_size} bytes): $(cat "$OUT_DIR/last_update.txt")"
  else
    echo "[render] FAILED to produce image." >&2
    # Create a fallback message
    echo "Image generation failed at $(date -u +"%Y-%m-%d %H:%M:%SZ")" > "$OUT_DIR/last_update.txt"
  fi
}

# --- Alternative Render Function (if main one fails) ---
render_image_fallback () {
  echo "[render] Trying fallback rendering method..."
  
  # Simpler gource command focusing on recent commits
  xvfb-run -a -s "-screen 0 ${WIDTH}x${HEIGHT}x24" \
    gource "$REPO_DIR" \
      --output-ppm-stream - \
      --stop-at-end \
      "-${WIDTH}x${HEIGHT}" \
      --seconds-per-day 1.0 \
      --auto-skip-seconds 0.5 \
      --background-colour 000000 \
      --highlight-users \
      --hide progress,mouse \
      --max-files 500 \
  | ffmpeg -y -v warning -f image2pipe -vcodec ppm -i - -frames:v 1 "$IMG_FILE"
}

# --- Main Execution Logic ---
echo "[nginx] Starting web server..."
nginx -g 'daemon off;' &

echo "[loop] Starting update loop. Initial render will begin shortly."
while true; do
  # Try main render first, fallback if it fails
  if ! render_image; then
    echo "[render] Main render failed, trying fallback method..."
    render_image_fallback || echo "[render] Both render methods failed."
  fi
  
  echo "[loop] Render complete. Waiting ${INTERVAL_SECONDS} seconds until next update."
  sleep "$INTERVAL_SECONDS"
done