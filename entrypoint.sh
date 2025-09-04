#!/usr/bin/env bash
set -Eeuo pipefail

# --- Configuration (from environment variables with defaults) ---
REPO_DIR="${REPO_DIR:-/data/repo}"
OUT_DIR="${OUT_DIR:-/var/www/html}"
IMG_FILE="${IMG_FILE:-/var/www/html/gource.png}"
GIT_URL="${GIT_URL}"
GIT_BRANCH="${GIT_BRANCH:-main}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-600}"
WIDTH="${WIDTH:-1920}"
HEIGHT="${HEIGHT:-1080}"
# GOURCE_OPTS is inherited from the environment

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

# --- Core Render Function ---
render_image () {
  echo "[git] Pulling latest changes from origin/$GIT_BRANCH..."
  git -C "$REPO_DIR" pull origin "$GIT_BRANCH" || { echo "[WARN] git pull failed, continuing with existing history." >&2; }

  echo "[render] Starting gource visualization..."
  xvfb-run -a -s "-screen 0 ${WIDTH}x${HEIGHT}x24" \
    gource "$REPO_DIR" \
      -o - \
      --stop-at-end \
      "-${WIDTH}x${HEIGHT}" \
      ${GOURCE_OPTS} \
  | ffmpeg -y -v error -f image2pipe -vcodec ppm -i - -frames:v 1 "$IMG_FILE"

  if [[ -f "$IMG_FILE" ]]; then
    date -u +"%Y-%m-%d %H:%M:%SZ" > "$OUT_DIR/last_update.txt"
    # IMPROVEMENT: Fixed typo in variable name from $OUT_DUR to $OUT_DIR
    echo "[render] Image successfully updated: $(cat "$OUT_DIR/last_update.txt")"
  else
    echo "[render] FAILED to produce image." >&2
  fi
}

# --- Main Execution Logic ---
# Start nginx in the background.
echo "[nginx] Starting web server..."
nginx -g 'daemon off;' &

# IMPROVEMENT: Simplified the main loop. It now renders first, then waits,
# which avoids code duplication and works for both the initial run and subsequent updates.
echo "[loop] Starting update loop. Initial render will begin shortly."
while true; do
  render_image
  echo "[loop] Render complete. Waiting ${INTERVAL_SECONDS} seconds until next update."
  sleep "$INTERVAL_SECONDS"
done