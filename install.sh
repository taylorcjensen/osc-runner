#!/bin/bash
set -e

LABEL="com.taylorcjensen.osc-runner"
SERVICE_DIR="$HOME/services/osc-runner"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing osc-runner..."

# Create service directory
mkdir -p "$SERVICE_DIR"

# Copy binary
cp "$SCRIPT_DIR/osc-runner" "$SERVICE_DIR/osc-runner"
chmod +x "$SERVICE_DIR/osc-runner"

# Copy example config if none exists
if [ ! -f "$SERVICE_DIR/config.json" ]; then
    cp "$SCRIPT_DIR/config.example.json" "$SERVICE_DIR/config.json"
    echo ""
    echo "  Config created at $SERVICE_DIR/config.json"
    echo "  Edit it to set your Eos IP and rules before starting the service."
    echo ""
fi

# Install plist with real HOME path substituted
sed "s|__HOME__|$HOME|g" "$SCRIPT_DIR/com.taylorcjensen.osc-runner.plist" > "$PLIST_DST"

# Load (or reload) the service
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo "Done. osc-runner is running as a launch agent."
echo "Logs: $SERVICE_DIR/osc-runner.log"
