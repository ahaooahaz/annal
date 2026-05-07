return {
    -- behaviours
    automatically_reload_config = true,
    check_for_updates = true,
    exit_behavior = "CloseOnCleanExit", -- if the shell program exited with a successful status
    status_update_interval = 1000,

    -- scrollbar
    scrollback_lines = 5000,

    audible_bell = "Disabled", -- 禁用终端 bell 声音
    visual_bell = {
        fade_in_function = "EaseIn",
        fade_in_duration_ms = 75,
        fade_out_function = "EaseOut",
        fade_out_duration_ms = 75,
    },

    -- paste behaviours
    canonicalize_pasted_newlines = "CarriageReturn",

    hyperlink_rules = {
        -- Matches: a URL in parens: (URL)
        {
            regex = "\\((\\w+://\\S+)\\)",
            format = "$1",
            highlight = 1,
        },
        -- Matches: a URL in brackets: [URL]
        {
            regex = "\\[(\\w+://\\S+)\\]",
            format = "$1",
            highlight = 1,
        },
        -- Matches: a URL in curly braces: {URL}
        {
            regex = "\\{(\\w+://\\S+)\\}",
            format = "$1",
            highlight = 1,
        },
        -- Matches: a URL in angle brackets: <URL>
        {
            regex = "<(\\w+://\\S+)>",
            format = "$1",
            highlight = 1,
        },
        -- Then handle URLs not wrapped in brackets
        {
            regex = "\\b\\w+://\\S+[)/a-zA-Z0-9-]+",
            format = "$0",
        },
        -- implicit mailto link
        {
            regex = "\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b",
            format = "mailto:$0",
        },
    },
}
