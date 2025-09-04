# --------------------------------------------------------------------
# Gource Image Server (Debian-based)
# --------------------------------------------------------------------
# Using bookworm as it has more recent packages.
FROM debian:bookworm-slim

# ---- Packages ----
# Added 'xvfb' to provide a virtual display for gource.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      gource ffmpeg git nginx bash ca-certificates xvfb && \
    # Clean up the default nginx site to avoid 'conflicting server name' warnings
    rm -f /etc/nginx/sites-enabled/default && \
    rm -rf /var/lib/apt/lists/*

# ---- App layout and Configuration ----
# These variables control the behavior of the server.
ENV REPO_DIR=/data/repo \
    OUT_DIR=/var/www/html \
    IMG_FILE=/var/www/html/gource.png \
    GIT_BRANCH=main \
    # GIT_URL must be provided at runtime, e.g., -e GIT_URL="https://github.com/..."
    GIT_URL="" \
    INTERVAL_SECONDS=600 \
    WIDTH=1920 \
    HEIGHT=1080 \
    # GOURCE_OPTS: Removed '--headless' as it's not a valid option.
    # Customization of gource's appearance happens here.
    GOURCE_OPTS="--seconds-per-day 0.5 --auto-skip-seconds 1 \
                 --background-colour 000000 --font-size 22 \
                 --hide progress,mouse,filenames \
                 --highlight-users \
                 --max-files 0 --file-idle-time 0"

# ---- NGINX Setup ----
# Create necessary directories and set up a simple Nginx config to serve the image.
RUN mkdir -p /run/nginx ${OUT_DIR} && \
    printf '%s\n' \
    'server {' \
    '  listen 80;' \
    '  server_name _;' \
    '  root /var/www/html;' \
    '  autoindex off;' \
    # Ensure browsers always fetch the latest image and update time
    '  add_header Cache-Control "no-store, must-revalidate";' \
    '  location / { try_files $uri =404; }' \
    '}' \
    > /etc/nginx/conf.d/default.conf

# ---- Web Page Setup ----
# A simple HTML page that auto-refreshes the image and the 'last updated' time.
RUN cat > ${OUT_DIR}/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Gource Snapshot</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  html,body{height:100%;margin:0;background:#0b0b0b;color:#ddd;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol"}
  .wrap{display:flex;flex-direction:column;min-height:100%}
  header{padding:12px 16px;opacity:.85}
  main{flex:1;display:flex;align-items:center;justify-content:center;padding:8px}
  img{max-width:100%;height:auto;display:block;border-radius:8px;box-shadow:0 0 20px rgba(0,0,0,0.5)}
  small{opacity:.7}
</style>
<script>
async function refresh() {
  const img = document.getElementById('gource-img');
  // Add a timestamp to the URL to bypass browser cache
  img.src = 'gource.png?t=' + Date.now();
  try {
    const res = await fetch('last_update.txt', {cache:'no-store'});
    if(res.ok){ document.getElementById('last-update').textContent = await res.text(); }
  } catch(_) {}
}
// Refresh the image every 60 seconds.
setInterval(refresh, 60000);
window.addEventListener('load', refresh);
</script>
</head>
<body>
<div class="wrap">
  <header><small>Auto-updating gource snapshot &bull; Last update: <span id="last-update">…</span></small></header>
  <main><img id="gource-img" src="gource.png" alt="Gource snapshot"></main>
</div>
</body>
</html>
HTML

# ---- Entrypoint Script ----
# This script manages the git repo and the render loop.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD test -f /var/www/html/gource.png || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]