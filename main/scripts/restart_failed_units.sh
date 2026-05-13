#!/usr/bin/env bash
set -u

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

mapfile -t failed_system_services < <(systemctl --failed --type=service --no-legend --plain 2>/dev/null | awk '{print $1}')
mapfile -t failed_user_services < <(systemctl --user --failed --type=service --no-legend --plain 2>/dev/null | awk '{print $1}')

total=$(( ${#failed_system_services[@]} + ${#failed_user_services[@]} ))
if (( total == 0 )); then
  qs ipc -c main call bar refreshModule systemd-failed-units >/dev/null 2>&1 || true
  exit 0
fi

restarted=0
failed=()

for unit in "${failed_system_services[@]}"; do
  if systemctl restart "$unit" >/dev/null 2>&1; then
    ((restarted++))
  else
    failed+=("system:$unit")
  fi
done

for unit in "${failed_user_services[@]}"; do
  if systemctl --user restart "$unit" >/dev/null 2>&1; then
    ((restarted++))
  else
    failed+=("user:$unit")
  fi
done

qs ipc -c main call bar refreshModule systemd-failed-units >/dev/null 2>&1 || true
