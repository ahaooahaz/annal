#!/usr/bin/env bash

mkdir -p ${HOME}/.local/state/nutstore-sync/log/ || :
rclone bisync ${HOME}/Documents/Nutstore/Nutstore nutstore:/我的坚果云 \
    --max-delete 30 \
    --create-empty-src-dirs \
    --exclude ".DS_Store" \
    --exclude ".Trash/**" \
    --exclude "__pycache__/**" \
    --exclude ".git/**" \
    --checkers 2 \
    --transfers 1 \
    --tpslimit 1 \
    --tpslimit-burst 1 \
    -v \
    --log-file ${HOME}/.local/state/nutstore-sync/log/rclone-nutstore-$(date +%Y%m%d%H%M).log
