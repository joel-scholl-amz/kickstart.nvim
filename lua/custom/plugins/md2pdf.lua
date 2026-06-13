-- md2pdf.lua — Convert current markdown buffer to PDF via pandoc + XeLaTeX
-- Keybinding : <leader>mp  (normal mode, any buffer — warns if not .md)
-- User command: :Md2Pdf
--
-- Dependencies (install once):
--   sudo apt update && sudo apt install -y pandoc texlive-xetex \
--     texlive-fonts-recommended texlive-latex-extra fonts-liberation wslu

local TEMPLATE   = vim.fn.expand("~/.config/pandoc/templates/company.tex")
local ASSETS_DIR = vim.fn.expand("~/.config/pandoc/assets")

--- Open a file with the best available opener for WSL / native Linux.
---@param path string  absolute path to the file
local function open_file(path)
  if vim.fn.executable("wslview") == 1 then
    -- wslu package — cleanest WSL opener
    vim.fn.jobstart({ "wslview", path }, { detach = true })
  elseif vim.fn.executable("cmd.exe") == 1 then
    -- Built-in WSL fallback: convert path and open with Windows default app
    local win_path = vim.fn.system("wslpath -w " .. vim.fn.shellescape(path)):gsub("\n", "")
    vim.fn.jobstart({ "cmd.exe", "/c", "start", "", win_path }, { detach = true })
  else
    vim.fn.jobstart({ "xdg-open", path }, { detach = true })
  end
end

--- Run pandoc on the current buffer and open the resulting PDF.
local function convert_md_to_pdf()
  local filepath = vim.api.nvim_buf_get_name(0)

  if filepath == "" then
    vim.notify("md2pdf: buffer has no file name — save first", vim.log.levels.WARN)
    return
  end

  if not filepath:match("%.md$") then
    vim.notify("md2pdf: not a markdown file (" .. filepath .. ")", vim.log.levels.WARN)
    return
  end

  if not vim.loop.fs_stat(TEMPLATE) then
    vim.notify("md2pdf: template not found: " .. TEMPLATE, vim.log.levels.ERROR)
    return
  end

  -- Save the buffer before converting
  if vim.bo.modified then
    vim.cmd("write")
  end

  local outfile = filepath:gsub("%.md$", ".pdf")

  local cmd = {
    "pandoc",
    filepath,
    "--template=" .. TEMPLATE,
    "--pdf-engine=xelatex",
    "--variable=assets:" .. ASSETS_DIR,
    "--highlight-style=tango",
    "--standalone",
    "-o", outfile,
  }

  vim.notify("md2pdf: converting…", vim.log.levels.INFO)

  local stderr_lines = {}

  vim.fn.jobstart(cmd, {
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_lines, line)
        end
      end
    end,

    on_exit = function(_, code)
      if code == 0 then
        vim.schedule(function()
          vim.notify("md2pdf: saved → " .. outfile, vim.log.levels.INFO)
          open_file(outfile)
        end)
      else
        vim.schedule(function()
          local detail = table.concat(stderr_lines, "\n")
          vim.notify(
            "md2pdf: pandoc failed (exit " .. code .. ")\n" .. detail,
            vim.log.levels.ERROR
          )
        end)
      end
    end,
  })
end

-- ── Keymaps ───────────────────────────────────────────────────────────
vim.keymap.set("n", "<leader>mpdf", convert_md_to_pdf, {
  desc = "[M]arkdown → [P]DF (pandoc)",
})

-- ── User command ──────────────────────────────────────────────────────
vim.api.nvim_create_user_command("Md2Pdf", convert_md_to_pdf, {
  desc = "Convert current markdown file to PDF",
})

-- ── which-key group label (registered after VimEnter) ─────────────────
vim.api.nvim_create_autocmd("User", {
  pattern  = "VeryLazy",
  once     = true,
  callback = function()
    local ok, wk = pcall(require, "which-key")
    if ok then
      wk.add({ { "<leader>mp", group = "[M]arkdown [P]DF" } })
    end
  end,
})

-- No external plugin to install
return {}
