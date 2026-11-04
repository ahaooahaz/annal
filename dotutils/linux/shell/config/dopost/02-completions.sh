#!/usr/bin/env bash
# shellcheck shell=bash

# Generate Kubectl/Helm completions on the first Tab, not during shell startup.
apps=(kubectl helm)
for app in "${apps[@]}"; do
    _shell_completion_register "$app"
done

apps=(stern)
for app in "${apps[@]}"; do
    if command -v "$app" >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source <("$app" --completion "$CURRSHELL")
    fi
done
