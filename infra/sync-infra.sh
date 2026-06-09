#!/bin/bash
# Usage: sudo ./sync-infra.sh /path/to/my-nas-gitops/infra
set -euo pipefail

if [ $# -lt 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 <path_to_infra_folder>" >&2
    exit 1
fi

REPO_ROOT=$(realpath "$1")

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
fi


PREFIX="gitops-"

# Adds the prefix unless the name already has it
prefixed() {
    local name=$1
    [[ "$name" == "$PREFIX"* ]] && echo "$name" || echo "$PREFIX$name"
}

# --- 1. SYNC CRON CONFIG ---
CRON_SRC="$REPO_ROOT/cron.d"
CRON_DST="/etc/cron.d"

if [ -d "$CRON_SRC" ]; then
    echo "Syncing cron jobs..."
    declare -A cron_desired=()

    for src in "$CRON_SRC"/*; do
        [ -f "$src" ] || continue
        name=$(prefixed "$(basename "$src")")

        # cron silently ignores /etc/cron.d files whose names contain a dot
        if [[ "$name" == *.* ]]; then
            echo "WARNING: '$name' contains a dot; cron will ignore it. Skipping."
            continue
        fi

        cron_desired["$name"]=1
        dest="$CRON_DST/$name"
        if ! cmp -s "$src" "$dest" 2>/dev/null; then
            echo "Installing cron job: $name"
            install -m 644 -o root -g root "$src" "$dest"
        fi
    done

    # Remove our prefixed cron files that no longer exist in the repo
    for f in "$CRON_DST/$PREFIX"*; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        if [ -z "${cron_desired[$name]:-}" ]; then
            echo "Removing stale cron job: $name"
            rm "$f"
        fi
    done
fi

# --- 2. SYNC SYSTEMD UNITS ---
SYSTEMD_SRC="$REPO_ROOT/systemd"
SYSTEMD_DST="/etc/systemd/system"

if [ -d "$SYSTEMD_SRC" ]; then
    echo "Syncing systemd units..."
    declare -A unit_desired=()
    changed_units=()
    needs_reload=false

    # Copy (and rename) units, tracking which ones changed
    for src in "$SYSTEMD_SRC"/*.service "$SYSTEMD_SRC"/*.timer; do
        [ -e "$src" ] || continue
        name=$(prefixed "$(basename "$src")")
        unit_desired["$name"]=1
        dest="$SYSTEMD_DST/$name"

        if ! cmp -s "$src" "$dest" 2>/dev/null; then
            echo "Installing unit: $name"
            install -m 644 -o root -g root "$src" "$dest"
            changed_units+=("$name")
            needs_reload=true
        fi
    done

    # Remove our prefixed units that no longer exist in the repo.
    # Stop and disable them BEFORE deleting the file, while systemd
    # still knows about the unit.
    for f in "$SYSTEMD_DST/$PREFIX"*.service "$SYSTEMD_DST/$PREFIX"*.timer; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        if [ -z "${unit_desired[$name]:-}" ]; then
            echo "Removing stale unit: $name"
            systemctl disable --now "$name" || true
            rm "$f"
            needs_reload=true
        fi
    done

    if $needs_reload; then
        echo "Reloading systemd daemon..."
        systemctl daemon-reload
    fi

    # Enable + start. Timers get enabled; services are only enabled
    # directly if no matching timer exists (timer-driven services
    # shouldn't also start at boot on their own).
    for name in "${!unit_desired[@]}"; do
        case "$name" in
            *.timer)
                systemctl enable --now "$name"
                ;;
            *.service)
                timer_name="${name%.service}.timer"
                if [ -z "${unit_desired[$timer_name]:-}" ]; then
                    systemctl enable --now "$name"
                fi
                ;;
        esac
    done

    # Restart units whose files changed, so running services pick up
    # the new config. (enable --now does nothing if already running.)
    for name in "${changed_units[@]}"; do
        if systemctl is-active --quiet "$name"; then
            echo "Restarting changed unit: $name"
            systemctl restart "$name"
        fi
    done
fi

echo "Infrastructure synchronization complete!"
