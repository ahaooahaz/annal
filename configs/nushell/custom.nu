## Press Ctrl-O to edit command line in nvim.
$env.EDITOR = "nvim"

## To add entries to PATH
use std "path add"
path add ~/.local/bin


def cat [] {
    open --raw $in
}