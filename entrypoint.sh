#!/usr/bin/env bash
set -Eeuo pipefail

# --- Configuration (from environment variables with defaults) ---
REPO_DIR="${REPO_DIR:-/data/repo}"
OUT_DIR="${OUT_DIR:-/var/www/html}"
IMG_FILE="${IMG_FILE:-/var/www/html/gource.png}"
GIT_URL="${GIT_URL}" # No default, must be provided
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
# Clone the repository if it doesn't exist.
# IMPORTANT: We do a full clone (no --depth 1) so gource has the complete history.
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "[git] Cloning full history of '$GIT_URL'..."
  git clone --branch "$GIT_BRANCH" "$GIT_URL" "$REPO_DIR"
else
  echo "[git] Repository already exists. Skipping initial clone."
fi
# Ensure git commands work even if directory is mounted by another user
git config --global --add safe.directory "$REPO_DIR"

# --- Core Render Function ---
render_image () {
  echo "[git] Pulling latest changes from origin/$GIT_BRANCH..."
  # Fetch latest changes from the remote repository
  git -C "$REPO_DIR" pull origin "$GIT_BRANCH" || { echo "[WARN] git pull failed, continuing with existing history." >&2; }

  echo "[render] Starting gource visualization..."

  # THE CORE FIX:
  # Run gource inside a virtual X server (Xvfb).
  # -a: automatically find a free server number.
  # -s: specifies screen 0 resolution and color depth (24-bit).
  # This resolution MUST match the one passed to gource.
  xvfb-run -a -s "-screen 0 ${WIDTH}x${HEIGHT}x24" \
    gource "$REPO_DIR" \
      --output-ppm-stream - \
      --stop-at-end \
      "-${WIDTH}x${HEIGHT}" \
      ${GOURCE_OPTS} \
  | ffmpeg -y -v error -f image2pipe -vcodec ppm -i - -frames:v 1 "$IMG_FILE"

  # Check if the ffmpeg command succeeded by verifying the output file exists
  if [[ -f "$IMG_FILE" ]]; then
    date -u +"%Y-%m-%d %H:%M:%SZ" > "$OUT_DIR/last_update.txt"
    echo "[render] Image successfully updated: $(cat "$OUT_DUR/last_update.txt")"
  else
    echo "[render] FAILED to produce image." >&2
  fi
}

# --- Main Execution Logic ---
# Start nginx in the background to serve the files.
echo "[nginx] Starting web server..."
nginx -g 'daemon off;' &

# Perform an initial render immediately on startup.
render_image

# Start the main update loop.
echo "[loop] Starting update loop every ${INTERVAL_SECONDS} seconds."
while true; do
  sleep "$INTERVAL_SECONDS"
  render_image
done