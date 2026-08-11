-- WSL account that owns the distribution below. Kept in one place so the home
-- path stays in sync; override with the WSL_USERNAME env var on other machines.
local wsl_username = os.getenv("WSL_USERNAME") or "ahaooahaz"

return {
    -- ref: https://wezfurlong.org/wezterm/config/lua/SshDomain.html
    ssh_domains = {},

    -- ref: https://wezfurlong.org/wezterm/multiplexing.html#unix-domains
    unix_domains = {},

    -- ref: https://wezfurlong.org/wezterm/config/lua/WslDomain.html
    wsl_domains = {
        {
            name = "WSL:Ubuntu-24.04",
            distribution = "Ubuntu-24.04",
            username = wsl_username,
            default_cwd = "/home/" .. wsl_username,
            -- default_prog = { "zsh" },
        },
    },
}
