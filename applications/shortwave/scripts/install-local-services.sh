#!/bin/sh
# Execute inside the development VM, through scripts/vm.sh run.
set -eu
if [ "$(uname -s)" != Linux ]; then echo 'Run this inside the isolated development VM.' >&2; exit 1; fi
project_dir=$(pwd)
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/shortwave-web.service" <<EOF
[Unit]
Description=Shortwave local development server
After=network-online.target

[Service]
WorkingDirectory=$project_dir
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$HOME/.local/bin/npm run dev
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
cat > "$HOME/.config/systemd/user/shortwave-events.service" <<EOF
[Unit]
Description=Shortwave durable click delivery worker
After=network-online.target

[Service]
WorkingDirectory=$project_dir
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$HOME/.local/bin/npm run events:flush -- --watch
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now shortwave-web shortwave-events
