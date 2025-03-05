# ----------------------------------------
# $env.config
# ----------------------------------------

$env.config.show_banner = false # true or false to enable or disable the welcome banner at startup
$env.config.table.mode = 'none' # basic, compact, compact_double, light, thin, with_love, rounded, reinforced, heavy, none, other
$env.config.shell_integration.osc133 = false
$env.config.cursor_shape = {
  emacs: block # block, underscore, line, blink_block, blink_underscore, blink_line, inherit to skip setting cursor shape (line is the default)
  vi_insert: line # block, underscore, line, blink_block, blink_underscore, blink_line, inherit to skip setting cursor shape (block is the default)
  vi_normal: block # block, underscore, line, blink_block, blink_underscore, blink_line, inherit to skip setting cursor shape (underscore is the default)
}

# ----------------------------------------
# custom.nu
# ----------------------------------------

# To load from a custom file you can use:
# source ($nu.default-config-dir | path join 'custom.nu')

# ----------------------------------------
# custom commands
# ----------------------------------------

# use scripts *

# ----------------------------------------
# starship (https://starship.rs)
# ----------------------------------------

$env.STARSHIP_CONFIG = ($nu.config-path | path dirname | path join 'starship.toml')
# starship init nu | save -f  ($nu.config-path | path dirname | path join 'starship.nu')

# source ($nu.default-config-dir | path join 'starship.nu')

# ----------------------------------------
# aliases
# ----------------------------------------

# nvim
alias vim = nvim
alias vi = nvim
