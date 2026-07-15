#!/usr/bin/env bash
# shellcheck shell=bash

# completion.
apps=(kubectl helm)
for app in "${apps[@]}"; do
    if command -v "$app" >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source <("$app" completion "$CURRSHELL")
    fi
done

apps=(stern)
for app in "${apps[@]}"; do
    if command -v "$app" >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source <("$app" --completion "$CURRSHELL")
    fi
done
