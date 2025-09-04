# --------------------------------------------------------------------
# Gource Image Server (Debian-based) - Fixed for Recent Activity
# --------------------------------------------------------------------
FROM debian:bookworm-slim

# ---- Packages ----
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      gource ffmpeg git nginx bash ca-certificates xvfb xauth && \
    rm -f /etc/nginx/sites-enabled/default && \
    rm -rf /var/lib/apt/lists/*

# ---- App layout and Configuration ----
ENV REPO_DIR=/data/repo \
    OUT_DIR=/var/www/html \
    IMG_FILE=/var/www/html/gource.png \
    GIT_BRANCH=main \
    GIT_URL="" \
    INTERVAL_SECONDS=600 \
    WIDTH=1920 \
    HEIGHT=1080 \
    # IMPROVED GOURCE OPTIONS - Focus on recent activity and longer timespan
    GOURCE_OPTS="--seconds-per-day 2.0 \
                 --auto-skip-seconds 0.1 \
                 --background-colour 000000 \
                 --font-size 18 \
                 --hide progress,mouse \
                 --show-filenames \
                 --highlight-users \
                 --max-files 1000 \
                 --file-idle-time 30 \
                 --user-image-dir /tmp \
                 --date-format '%Y-%m-%d %H:%M' \
                 --title 'Repository Activity'"

# ---- NGINX Setup ----
RUN mkdir -p /run/nginx ${OUT_DIR} && \
    printf '%s\n' \
    'server {' \
    '  listen 80;' \
    '  server_name _;' \
    '  root /var/www/html;' \
    '  autoindex off;' \
    '  add_header Cache-Control "no-store, must-revalidate";' \
    '  location / { try_files $uri =404; }' \
    '}' \
    > /etc/nginx/conf.d/default.conf

# ---- Web Page Setup ----
RUN cat > ${OUT_DIR}/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Gource Repository Visualization</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  html,body{height:100%;margin:0;background:#0b0b0b;color:#ddd;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
  .wrap{display:flex;flex-direction:column;min-height:100%}
  header{padding:16px;text-align:center;border-bottom:1px solid #333}
  main{flex:1;display:flex;align-items:center;justify-content:center;padding:16px}
  img{max-width:100%;height:auto;display:block;border-radius:8px;box-shadow:0 4px 20px rgba(0,0,0,0.7)}
  .status{display:flex;gap:20px;justify-content:center;flex-wrap:wrap;font-size:14px}
  .status span{opacity:0.8}
  .repo-info{margin-top:10px;opacity:0.6;font-size:12px}
  h1{margin:0;font-size:24px;color:#fff}
</style>
<script>
async function refresh() {
  const img = document.getElementById('gource-img');
  const timestamp = Date.now();
  img.src = 'gource.png?t=' + timestamp;
  
  try {
    const res = await fetch('last_update.txt', {cache:'no-store'});
    if(res.ok){ 
      const updateTime = await res.text();
      document.getElementById('last-update').textContent = updateTime;
    }
  } catch(e) {
    console.log('Could not fetch update time:', e);
  }
  
  try {
    const res = await fetch('repo_info.txt', {cache:'no-store'});
    if(res.ok){ 
      const repoInfo = await res.text();
      document.getElementById('repo-info').textContent = repoInfo;
    }
  } catch(e) {
    console.log('Could not fetch repo info:', e);
  }
}

setInterval(refresh, 30000); // Check every 30 seconds
window.addEventListener('load', refresh);
</script>
</head>
<body>
<div class="wrap">
  <header>
    <h1>Repository Activity Visualization</h1>
    <div class="status">
      <span>Last updated: <strong id="last-update">Loading...</strong></span>
      <span>Updates every 10 minutes</span>
    </div>
    <div class="repo-info" id="repo-info">Repository info loading...</div>
  </header>
  <main><img id="gource-img" src="gource.png" alt="Gource repository visualization"></main>
</div>
</body>
</html>
HTML

# ---- Entrypoint Script ----
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=45s CMD test -f /var/www/html/gource.png || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]