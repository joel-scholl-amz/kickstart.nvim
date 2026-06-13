local M = {}

local THEME_FILE = vim.fn.expand('~/.config/theme')

local function read_mode()
    local f = io.open(THEME_FILE, 'r')
    if not f then return 'dark' end
    local mode = f:read('*l')
    f:close()
    return (mode == 'light') and 'light' or 'dark'
end

local function write_mode(mode)
    local f = io.open(THEME_FILE, 'w')
    if f then
        f:write(mode)
        f:close()
    end
end

function M.apply()
    local mode = read_mode()
    if mode == 'light' then
        vim.o.background = 'light'
        vim.cmd.colorscheme('tokyonight-day')
    else
        vim.o.background = 'dark'
        vim.cmd.colorscheme('tokyonight-night')
    end
end

function M.toggle()
    local current = read_mode()
    local new_mode = current == 'dark' and 'light' or 'dark'
    write_mode(new_mode)
    M.apply()
    -- Pass the already-decided mode so the script doesn't double-flip
    vim.fn.jobstart({ 'toggle-theme', new_mode }, { detach = true })
end

return M
