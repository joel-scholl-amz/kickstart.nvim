---@brief Scrum-daily glue between the Obsidian daily note and Polarion.
---
--- pull(): fetches each team member's in-progress tasks of the configured
--- sprint and inserts them under the "- **Today**" block of the member's
--- section in the daily note. push(): sends the notes written indented below
--- those task lines to the work items' Comments section in Polarion.
---
--- Generic Polarion access lives in polarion.nvim (require("polarion.api"));
--- this module only knows about the daily note layout:
---
---   ### Paul                      ← member section: single-word heading
---   - **Today**                   ← existing template block
---   	- [WI-123] Task title (status)    ← added by pull()
---   		- note typed during the standup   ← push() sends this as a comment
---   		- second note ✅                  ← already pushed (marker), skipped

local M = {}

M.opts = {
  -- short id of the sprint/milestone work item the kanban filters on
  -- (e.g. "HELAX-5137" = Sprint 5); update it when a new sprint starts
  sprint = 'HELAX-5156',
  -- custom field on tasks that references that sprint work item
  sprint_field = 'cfTargetSprint',
  -- only tasks in these states are pulled
  statuses = { 'inprogress' },
  -- section-name → Polarion user overrides: the exact user id or full
  -- display name, e.g. { Paul = "MusterP" } or { Paul = "Paul Muster" }.
  -- Sections without an entry are matched by first name against the
  -- assignees' display names and user ids.
  members = {},
  -- template block the tasks are inserted into (created when missing)
  today_label = 'Today',
  -- appended to a note line once its comment is in Polarion
  pushed_marker = ' ✅',
}

---@param opts table|nil  overrides for M.opts
function M.setup(opts)
  M.opts = vim.tbl_deep_extend('force', M.opts, opts or {})
  vim.api.nvim_create_user_command('PolarionDailyPull', M.pull, {
    desc = 'Insert open sprint tasks into the daily note',
  })
  vim.api.nvim_create_user_command('PolarionDailyPush', M.push, {
    desc = 'Push daily-note task remarks to Polarion as comments',
  })
end

-- ── pure note parsing (exported for tests) ───────────────────────────────────

--- Member sections: markdown headings whose text is a single word
--- ("### Paul"); any other heading ends the previous section.
---@param lines string[]
---@return table[]  { { name, first, last } }  1-based, heading line included
function M._sections(lines)
  local secs, open = {}, nil
  for i, line in ipairs(lines) do
    if line:match '^#+%s' then
      if open then
        open.last = i - 1
        open = nil
      end
      local name = line:match '^#+%s+(%a[%w_%-]*)%s*$'
      if name then
        open = { name = name, first = i, last = #lines }
        secs[#secs + 1] = open
      end
    end
  end
  return secs
end

--- Parse a task bullet: returns indent (whitespace prefix) and work item id.
local function task_line_id(line)
  return line:match '^([\t ]*)[-*]%s+%[([%w_]+%-%d+)%]'
end

--- Format the bullet line for one pulled task.
local function format_task(task)
  local status = task.status ~= '' and (' (%s)'):format(task.status) or ''
  return ('\t- [%s] %s%s'):format(task.short_id, task.title, status)
end

--- Does `task` belong to member `name`? With an `override` only an exact
--- user id or full display name counts; otherwise the first name is matched
--- against id and full name.
local function task_matches(task, name, override)
  for _, a in ipairs(task.assignees or {}) do
    if override then
      if a.id:lower() == override:lower() or a.name:lower() == override:lower() then
        return true
      end
    elseif a.id:lower():find(name:lower(), 1, true) or a.name:lower():find(name:lower(), 1, true) then
      return true
    end
  end
  return false
end

--- Merge tasks into the note lines: for every member section, append missing
--- tasks to its "- **Today**" block (creating the block at the section end
--- when the template didn't provide one). Pure — returns the new lines plus
--- stats; existing task lines and the notes under them are left untouched.
---@param lines string[]
---@param tasks table[]  items from polarion.api.planned_tasks
---@param opts table  M.opts
---@return string[] new_lines, table stats  { added, present, unmatched = {task,…} }
function M._merge_tasks(lines, tasks, opts)
  local out = vim.deepcopy(lines)
  local stats = { added = 0, present = 0, unmatched = {} }
  local matched = {}

  local secs = M._sections(out)
  -- walk bottom-up so insertions don't shift not-yet-processed sections
  for s = #secs, 1, -1 do
    local sec = secs[s]

    -- ids already present anywhere in the section
    local present = {}
    for i = sec.first, sec.last do
      local _, id = task_line_id(out[i])
      if id then
        present[id] = true
      end
    end

    local new_lines = {}
    for _, task in ipairs(tasks) do
      if task_matches(task, sec.name, opts.members[sec.name]) then
        matched[task.short_id] = true
        if present[task.short_id] then
          stats.present = stats.present + 1
        else
          new_lines[#new_lines + 1] = format_task(task)
          stats.added = stats.added + 1
        end
      end
    end

    if #new_lines > 0 then
      -- find the Today block header in the section
      local header
      for i = sec.first, sec.last do
        if out[i]:match('^[-*]%s+%*%*' .. vim.pesc(opts.today_label) .. '%*%*%s*$') then
          header = i
          break
        end
      end
      local at -- insert new task lines after this line
      if header then
        at = header
        while at + 1 <= sec.last and out[at + 1]:match '^[\t ]+[-*]%s' do
          at = at + 1
        end
      else
        -- no block in the template: append one at the section end, above
        -- trailing blanks
        at = sec.last
        while at > sec.first and out[at]:match '^%s*$' do
          at = at - 1
        end
        table.insert(new_lines, 1, ('- **%s**'):format(opts.today_label))
      end
      for i = #new_lines, 1, -1 do
        table.insert(out, at + 1, new_lines[i])
      end
    end
  end

  for _, task in ipairs(tasks) do
    if not matched[task.short_id] then
      stats.unmatched[#stats.unmatched + 1] = task
    end
  end
  return out, stats
end

--- Visual width of an indent string; tabs advance to the next multiple of 4,
--- so tab- and space-indented lines compare sanely.
local function indent_width(ws)
  local w = 0
  for c in ws:gmatch '.' do
    w = c == '\t' and (w + 4 - w % 4) or (w + 1)
  end
  return w
end

--- Collect unpushed notes: every bullet nested below a task line starts one
--- note; bullets indented deeper than a note's first line are folded into it
--- as extra lines. Indentation is compared by visual width, so tabs and
--- spaces can be mixed. Notes whose first line already ends with `marker`,
--- or that hold only placeholder text ("" or "."), are skipped.
---@param lines string[]
---@param marker string
---@return table[]  { { id, lnum, text = {…}, section } }  lnum = the note's first line
function M._collect_notes(lines, marker)
  -- map a line number to the member section (heading name) it falls under
  local secs = M._sections(lines)
  local function section_of(lnum)
    for _, s in ipairs(secs) do
      if lnum >= s.first and lnum <= s.last then
        return s.name
      end
    end
  end

  local notes = {}
  local i = 1
  while i <= #lines do
    local indent, id = task_line_id(lines[i])
    if id then
      local base = indent_width(indent)
      local note, note_w
      local j = i + 1
      while j <= #lines do
        local nindent, text = lines[j]:match '^([\t ]+)[-*]%s+(.-)%s*$'
        local w = nindent and indent_width(nindent)
        if not w or w <= base then
          break
        end
        if note and w > note_w then
          note.text[#note.text + 1] = text
        else
          note = { id = id, lnum = j, text = { text }, section = section_of(j) }
          note_w = w
          notes[#notes + 1] = note
        end
        j = j + 1
      end
      i = j
    else
      i = i + 1
    end
  end
  return vim.tbl_filter(function(n)
    local head = n.text[1]
    return head ~= '' and head ~= '.' and not vim.endswith(lines[n.lnum], marker)
  end, notes)
end

--- Escape text and join a note's lines into the comment HTML. The member
--- section the note was written under (e.g. "Paul") is prefixed to the body
--- so the comment names who reported it.
---@param note table
---@param date string  "YYYY-MM-DD" of the daily note
function M._comment_html(note, date)
  local parts = {}
  for _, t in ipairs(note.text) do
    parts[#parts + 1] = t:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
  end
  local who = note.section and (note.section .. ': ') or ''
  return ('<p>[Daily %s] %s%s</p>'):format(date, who, table.concat(parts, '<br/>'))
end

-- ── commands ─────────────────────────────────────────────────────────────────

local function notify(msg, level)
  vim.notify('polarion daily: ' .. msg, level or vim.log.levels.INFO)
end

--- Date of the daily note in the current buffer (from the file name),
--- falling back to today.
local function note_date(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name:match '(%d%d%d%d%-%d%d%-%d%d)' or os.date '%Y-%m-%d'
end

--- Pull open tasks of the configured sprint into the daily note in the
--- current buffer, one Tasks block per member section.
function M.pull()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_get_name(buf):match '%.md$' then
    notify('current buffer is not a markdown note', vim.log.levels.ERROR)
    return
  end
  if M.opts.sprint == '' then
    notify('no sprint configured — set opts.sprint to the sprint work item id', vim.log.levels.ERROR)
    return
  end
  local api = require 'polarion.api'
  local cfg, cerr = api.config()
  if not cfg then
    notify(cerr, vim.log.levels.ERROR)
    return
  end
  notify(('fetching tasks of sprint %s…'):format(M.opts.sprint))
  -- resolve the sprint item first: its title for the summary, and a clear
  -- error when the configured id has gone stale
  api.tasks(('id:(%s)'):format(M.opts.sprint), function(sprint_items, err)
    if not sprint_items then
      notify(err, vim.log.levels.ERROR)
      return
    end
    if not sprint_items[1] then
      notify(('sprint work item %s not found — update opts.sprint'):format(M.opts.sprint), vim.log.levels.ERROR)
      return
    end
    local sprint = sprint_items[1]
    local query = ('type:%s AND %s.KEY:(%s)'):format(cfg.work_item_types.task, M.opts.sprint_field, M.opts.sprint)
    api.tasks(query, function(tasks, terr)
      if not tasks then
        notify(terr, vim.log.levels.ERROR)
        return
      end
      local wanted = {}
      for _, s in ipairs(M.opts.statuses) do
        wanted[s:lower()] = true
      end
      local open_tasks = vim.tbl_filter(function(t)
        return wanted[t.status:lower()]
      end, tasks)

      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local new_lines, stats = M._merge_tasks(lines, open_tasks, M.opts)
      if stats.added > 0 then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
      end

      local msg = ('%s: %d task(s) added, %d already present'):format(sprint.title, stats.added, stats.present)
      local unassigned = 0
      local ids = {}
      for _, t in ipairs(stats.unmatched) do
        if #(t.assignees or {}) == 0 then
          unassigned = unassigned + 1
        else
          ids[#ids + 1] = ('%s (%s)'):format(t.short_id, t.assignees[1].name)
        end
      end
      if #ids > 0 then
        msg = msg .. ('\nno matching section for: %s'):format(table.concat(ids, ', '))
      end
      if unassigned > 0 then
        msg = msg .. ('\n%d matching task(s) unassigned'):format(unassigned)
      end
      notify(msg)
    end)
  end)
end

--- Push the notes written below task lines as comments to Polarion, after
--- confirmation. Pushed notes are marked with the pushed_marker and skipped
--- on the next run.
function M.push()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local notes = M._collect_notes(lines, M.opts.pushed_marker)
  if #notes == 0 then
    notify 'no new notes to push'
    return
  end

  local date = note_date(buf)
  local summary = {}
  for _, n in ipairs(notes) do
    local head = n.text[1]
    if #head > 60 then
      head = head:sub(1, 57) .. '…'
    end
    summary[#summary + 1] = ('  %s ← %s'):format(n.id, head)
  end
  local prompt = ('Push %d comment(s) to Polarion?\n%s'):format(#notes, table.concat(summary, '\n'))
  if vim.fn.confirm(prompt, '&Push\n&Cancel', 2) ~= 1 then
    return
  end

  local api = require 'polarion.api'
  local idx, pushed, errs = 1, 0, {}
  local function step()
    if idx > #notes then
      local msg = ('pushed %d comment(s)'):format(pushed)
      if #errs > 0 then
        notify(msg .. '\nfailed:\n  ' .. table.concat(errs, '\n  '), vim.log.levels.ERROR)
      else
        notify(msg)
      end
      return
    end
    local n = notes[idx]
    idx = idx + 1
    api.add_comment(n.id, M._comment_html(n, date), nil, function(err)
      if err then
        errs[#errs + 1] = ('%s: %s'):format(n.id, err)
      else
        pushed = pushed + 1
        if vim.api.nvim_buf_is_valid(buf) then
          local cur = vim.api.nvim_buf_get_lines(buf, n.lnum - 1, n.lnum, false)[1]
          if cur and not vim.endswith(cur, M.opts.pushed_marker) then
            vim.api.nvim_buf_set_lines(buf, n.lnum - 1, n.lnum, false, { cur .. M.opts.pushed_marker })
          end
        end
      end
      step()
    end)
  end
  step()
end

return M
