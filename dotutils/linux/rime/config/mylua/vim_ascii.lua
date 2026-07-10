local M = {}

function M.func(key, env)
    local repr = key:repr():lower()
    if repr == "escape" or repr == "control+c" or repr == "control+bracketleft" or repr == "control+g" then
        env.engine.context:set_option("ascii_mode", true)
    end
    return 2
end

return M
