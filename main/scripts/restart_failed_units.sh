#!/usr/bin/env bash
set -u

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Refresh even on failure, but preserve the action's exit status.
trap 'qs ipc -c main call bar refreshModule systemd-failed-units >/dev/null 2>&1 || true' EXIT

if ! system_output=$(systemctl --failed --type=service --no-legend --plain 2>&1); then
  printf 'Cannot query system services: %s\n' "$system_output" >&2
  exit 1
fi
if ! user_output=$(systemctl --user --failed --type=service --no-legend --plain 2>&1); then
  printf 'Cannot query user services: %s\n' "$user_output" >&2
  exit 1
fi
mapfile -t failed_system_services < <(awk 'NF {print $1}' <<< "$system_output")
mapfile -t failed_user_services < <(awk 'NF {print $1}' <<< "$user_output")

total=$(( ${#failed_system_services[@]} + ${#failed_user_services[@]} ))
if (( total == 0 )); then
  exit 0
fi

restarted=0
failed=()

for unit in "${failed_system_services[@]}"; do
  if output=$(systemctl restart "$unit" 2>&1); then
    ((restarted++))
  else
    failed+=("system:$unit: $output")
  fi
done

for unit in "${failed_user_services[@]}"; do
  if output=$(systemctl --user restart "$unit" 2>&1); then
    ((restarted++))
  else
    failed+=("user:$unit: $output")
  fi
done

if (( ${#failed[@]} > 0 )); then
  printf 'Failed to restart %s\n' "${failed[@]}" >&2
  exit 1
fi
printf 'Restarted %d service(s).\n' "$restarted"
