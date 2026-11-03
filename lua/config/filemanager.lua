-- Native zero-plugin file manager (<leader>e).
--
-- Design goals:
--   * One modal, keyboard-first surface: a left-anchored floating panel opened
--     from the current buffer's directory. It closes when a file is opened, so
--     it never fights the edit window for space.
--   * Vim muscle memory: j/k/gg/G, h/l for parent/enter, y/x/p for
--     copy/move/paste, m/M for marks, a/A for add, d/r for delete/rename.
--   * Everything filesystem-facing goes through libuv (`vim.uv`); no shell
--     strings, no external commands, no plugins, no temporary files.
--   * Destructive actions are confirmed. Existing destinations are never
--     overwritten silently. Recursive copies are rolled back on failure, and
--     moves fall back to copy+delete across filesystems.
--   * Names containing control characters or path separators are rejected at
--     the prompt, so a mistyped name cannot escape the current directory.
--
-- The panel is event-driven: browsing uses buffer-local mappings and a real
-- cursor, while prompts/confirmations/help use short-lived floating windows.
-- No blocking input loop is involved, so it composes cleanly with Neovim's
-- normal command flow and with headless tests.

local uv = vim.uv

local M = {}

M.opts = {
  width_ratio = 0.40,
  width_min = 30,
  width_max = 52,
  max_entries = 20000,
  show_hidden = false,
}

local ns = vim.api.nvim_create_namespace("nvim_config_filemanager")
local augroup = "nvim_config_filemanager"

local state = nil
local clipboard = nil -- { op = "copy"|"move", paths = string[] }

-- Forward declarations keep the helper order readable and let callbacks
-- defined in prompts refer to the browsing functions below them.
local render, rebuild, refresh, set_directory
local close
local current_entry, marked_paths

----------------------------------------
-- Small helpers
----------------------------------------

local function notify(msg, level)
  vim.notify("files: " .. msg, level or vim.log.levels.INFO)
end

local function join(dir, name)
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

local function clamp(n, lo, hi)
  if n < lo then
    return lo
  elseif n > hi then
    return hi
  end
  return n
end

local function width_of(s)
  return vim.fn.strdisplaywidth(s)
end

---Truncate at the end, keeping the beginning. `maxw` is display width.
local function fit_head(s, maxw)
  if maxw <= 0 then
    return ""
  end
  if width_of(s) <= maxw then
    return s
  end
  if maxw == 1 then
    return "…"
  end
  local chars = vim.fn.strchars(s)
  local keep = chars
  while keep > 0 do
    local candidate = vim.fn.strcharpart(s, 0, keep) .. "…"
    if width_of(candidate) <= maxw then
      return candidate
    end
    keep = keep - 1
  end
  return "…"
end

---Truncate at the front, keeping the tail. Used for long paths.
local function fit_tail(s, maxw)
  if maxw <= 0 then
    return ""
  end
  if width_of(s) <= maxw then
    return s
  end
  if maxw == 1 then
    return "…"
  end
  local chars = vim.fn.strchars(s)
  local keep = chars
  while keep > 0 do
    local candidate = "…" .. vim.fn.strcharpart(s, chars - keep)
    if width_of(candidate) <= maxw then
      return candidate
    end
    keep = keep - 1
  end
  return "…"
end

---Replace control characters so a hostile or accidental filename cannot
---break the row layout or inject terminal escape sequences.
local function sanitize(name)
  return (name:gsub("[%z\1-\31\127]", "�"))
end

local function display_path(path)
  local home = uv.os_homedir()
  if home and (path == home or path:sub(1, #home + 1) == home .. "/") then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

local function human_size(n)
  if not n then
    return ""
  end
  if n < 1024 then
    return ("%d B"):format(n)
  end
  local units = { "KB", "MB", "GB", "TB" }
  local value = n / 1024
  local unit = 1
  while value >= 1024 and unit < #units do
    value = value / 1024
    unit = unit + 1
  end
  if value < 10 then
    return ("%.1f %s"):format(value, units[unit])
  end
  return ("%.0f %s"):format(value, units[unit])
end

local function validate_name(name)
  if name == "" then
    return false, "name cannot be empty"
  end
  if name == "." or name == ".." then
    return false, "name cannot be . or .."
  end
  if name:find("/", 1, true) or name:find("\\", 1, true) then
    return false, "name cannot contain a path separator"
  end
  if name:find("[%z\1-\31\127]") then
    return false, "name cannot contain control characters"
  end
  if #name > 255 then
    return false, "name is too long"
  end
  return true
end

local function is_executable(mode)
  if not mode then
    return false
  end
  local ok, bit = pcall(require, "bit")
  if not ok then
    return false
  end
  return bit.band(mode, 73) ~= 0 -- 0o111
end

----------------------------------------
-- Directory listing
----------------------------------------

---Read `dir` and return entries sorted directories-first, then by name.
---@param dir string
---@return table[]|nil entries, string|nil err, boolean truncated
local function read_dir(dir)
  local scanner, serr = uv.fs_scandir(dir)
  if not scanner then
    return nil, tostring(serr or "cannot read directory"), false
  end

  local entries = {}
  local truncated = false
  while true do
    local name, kind = uv.fs_scandir_next(scanner)
    if not name then
      break
    end
    if name ~= "." and name ~= ".." then
      if #entries >= M.opts.max_entries then
        truncated = true
        break
      end
      local path = join(dir, name)
      local lst = uv.fs_lstat(path)
      local entry = {
        name = name,
        path = path,
        type = (lst and lst.type) or kind or "file",
        hidden = name:sub(1, 1) == ".",
        size = lst and lst.size or nil,
        mtime = lst and lst.mtime or nil,
        is_dir = false,
        link = false,
        broken = false,
        exec = false,
      }
      if entry.type == "link" then
        entry.link = true
        local target = uv.fs_stat(path) -- follows the link; may be nil if broken
        if target then
          entry.is_dir = target.type == "directory"
          if target.type == "file" then
            entry.size = target.size
          end
        else
          entry.broken = true
        end
      elseif entry.type == "directory" then
        entry.is_dir = true
      elseif entry.type == "file" then
        entry.exec = is_executable(lst and lst.mode)
      end
      entries[#entries + 1] = entry
    end
  end

  table.sort(entries, function(a, b)
    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    local al, bl = a.name:lower(), b.name:lower()
    if al == bl then
      return a.name < b.name
    end
    return al < bl
  end)

  return entries, nil, truncated
end

local function entry_group(entry)
  if entry.broken then
    return "FileManagerBroken"
  elseif entry.hidden then
    return "FileManagerHidden"
  elseif entry.is_dir then
    return "FileManagerDir"
  elseif entry.link then
    return "FileManagerSymlink"
  elseif entry.exec then
    return "FileManagerExec"
  end
  return "FileManagerFile"
end

current_entry = function()
  if not state then
    return nil
  end
  return state.view[state.cursor]
end

----------------------------------------
-- Window chrome
----------------------------------------

local function build_title(width)
  local suffix = ""
  if state.filter ~= "" then
    suffix = suffix .. " /" .. fit_head(state.filter, 12)
  end
  if clipboard and #clipboard.paths > 0 then
    suffix = suffix .. (" [%d %s]"):format(#clipboard.paths, clipboard.op)
  end
  local marked = 0
  for _ in pairs(state.marked) do
    marked = marked + 1
  end
  if marked > 0 then
    suffix = suffix .. (" *%d"):format(marked)
  end

  local room = width - width_of(" files · ") - width_of(suffix) - 3
  local path = display_path(state.cwd)
  if width_of(path) > math.max(4, room) then
    path = fit_tail(path, math.max(4, room))
  end
  return " files · " .. path .. suffix .. " "
end

local function build_footer(width)
  local tiers = {
    " j/k move · l open · h up · a new · A folder · d delete · r rename · y copy · x move · p paste · ? help ",
    " j/k move · l open · h up · a new · d del · r ren · y/x/p · ? help ",
    " j/k · l open · h up · y/x/p · ? help ",
    " j/k · l open · h up · ? help ",
    " j/k · l/h · ? ",
    " ? ",
  }
  for _, footer in ipairs(tiers) do
    if width_of(footer) <= width then
      return footer
    end
  end
  return " ? "
end

local function layout_config()
  local columns, lines = vim.o.columns, vim.o.lines
  local width = math.floor(columns * M.opts.width_ratio)
  width = math.max(M.opts.width_min, math.min(M.opts.width_max, width))
  width = math.max(1, math.min(width, columns - 4))

  -- `lines` includes the command line and an optional tabline; floats with
  -- `relative = "editor"` do not. Leave one row of breathing room on top and
  -- one on the bottom so the rounded border is never clipped.
  local tabline = 0
  if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then
    tabline = 1
  end
  local available = lines - vim.o.cmdheight - tabline
  local height = math.max(1, available - 3)
  local row = math.max(0, math.min(1, available - height - 2))
  local col = math.max(0, math.min(2, columns - width - 2))

  return {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = build_title(width),
    title_pos = "left",
    footer = build_footer(width),
    footer_pos = "center",
  }
end

----------------------------------------
-- Rendering
----------------------------------------

local function add_hl(buf, group, row, start_col, end_col)
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, group, row, start_col, end_col)
end

---Central repaint. Also re-runs the layout so resizes are handled live.
function render()
  local s = state
  if not s then
    return
  end
  if not (s.win and vim.api.nvim_win_is_valid(s.win)) then
    return
  end
  if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
    return
  end

  local cfg = layout_config()
  s.width = cfg.width
  s.height = cfg.height

  local lines = {}
  local row_meta = {}

  if #s.view == 0 then
    local msg, hint
    if s.read_error then
      msg = "cannot read this directory"
      hint = fit_head(s.read_error, math.max(4, s.width - 6))
    elseif s.filter ~= "" then
      msg = 'no matches for "' .. sanitize(s.filter) .. '"'
      hint = "C-l clears the filter"
    elseif #s.entries > 0 and not s.show_hidden then
      msg = "(no visible entries)"
      hint = ". shows hidden files"
    else
      msg = "(empty directory)"
      hint = "a new file · A new folder"
    end
    lines[1] = "   " .. fit_head(msg, math.max(4, s.width - 3))
    lines[2] = "   " .. fit_head(hint, math.max(4, s.width - 3))
    row_meta[1] = { group = "FileManagerEmpty" }
    row_meta[2] = { group = "FileManagerEmptyHint" }
  else
    for i, entry in ipairs(s.view) do
      local marked = s.marked[entry.path] and true or false
      local size = ""
      if not entry.is_dir and entry.size then
        size = human_size(entry.size)
      end
      local suffix = entry.is_dir and "/" or (entry.link and "@" or "")
      local size_w = size ~= "" and (width_of(size) + 1) or 0
      local avail = math.max(4, s.width - 3 - size_w)
      local label = fit_head(sanitize(entry.name) .. suffix, avail)

      local sel_char = (i == s.cursor) and "›" or " "
      local mark_char = marked and "●" or " "
      local gutter = sel_char .. mark_char .. " "
      local line = gutter .. label
      if size ~= "" then
        local pad = s.width - width_of(line) - width_of(size)
        if pad < 1 then
          pad = 1
        end
        line = line .. string.rep(" ", pad) .. size
      end
      lines[#lines + 1] = line
      row_meta[#row_meta + 1] = {
        entry = entry,
        name_start = #gutter,
        name_end = #gutter + #label,
        mark_start = #sel_char,
        mark_end = #sel_char + #mark_char,
        size_start = size ~= "" and (#line - #size) or nil,
        selected = i == s.cursor,
        marked = marked,
      }
    end
  end

  vim.bo[s.buf].modifiable = true
  local ok = pcall(vim.api.nvim_buf_set_lines, s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  vim.bo[s.buf].modified = false
  if not ok then
    return
  end

  vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for i, meta in ipairs(row_meta) do
    local row = i - 1
    if meta.group then
      add_hl(s.buf, meta.group, row, 0, -1)
    else
      if meta.selected then
        add_hl(s.buf, "FileManagerSelectedGutter", row, 0, #("›"))
      end
      if meta.marked then
        add_hl(s.buf, "FileManagerMark", row, meta.mark_start, meta.mark_end)
      end
      add_hl(s.buf, entry_group(meta.entry), row, meta.name_start, meta.name_end)
      if meta.marked then
        add_hl(s.buf, "FileManagerMarkedName", row, meta.name_start, meta.name_end)
      end
      if meta.size_start then
        add_hl(s.buf, "FileManagerSize", row, meta.size_start, -1)
      end
    end
  end

  pcall(vim.api.nvim_win_set_config, s.win, cfg)
  pcall(vim.api.nvim_win_set_cursor, s.win, { math.max(1, math.min(s.cursor, #lines)), 0 })
  -- Keep the selection comfortably centered, like the search pickers.
  vim.api.nvim_win_call(s.win, function()
    pcall(vim.cmd, "normal! zz")
  end)
end

function rebuild(select_name)
  local s = state
  if not s then
    return
  end
  local needle = s.filter:lower()
  local view = {}
  for _, entry in ipairs(s.entries) do
    if s.show_hidden or not entry.hidden then
      if needle == "" or entry.name:lower():find(needle, 1, true) then
        view[#view + 1] = entry
      end
    end
  end
  s.view = view

  local target = select_name or s.select_name
  s.select_name = nil
  if target then
    for i, entry in ipairs(view) do
      if entry.name == target then
        s.cursor = i
        break
      end
    end
  end
  if #view == 0 then
    s.cursor = 1
  else
    s.cursor = clamp(s.cursor, 1, #view)
  end
  render()
end

function refresh(select_name)
  local s = state
  if not s then
    return
  end
  local entries, err, truncated = read_dir(s.cwd)
  if not entries then
    s.read_error = err
    notify("cannot read " .. display_path(s.cwd) .. ": " .. err, vim.log.levels.ERROR)
    render()
    return
  end
  s.entries = entries
  s.read_error = truncated and ("showing the first %d entries"):format(M.opts.max_entries) or nil
  if truncated then
    notify(s.read_error, vim.log.levels.WARN)
  end
  rebuild(select_name)
end

function set_directory(dir, select_name)
  local s = state
  if not s then
    return false
  end
  local entries, err = read_dir(dir)
  if not entries then
    notify("cannot open " .. display_path(dir) .. ": " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  s.cwd = dir
  s.entries = entries
  s.filter = ""
  s.cursor = 1
  s.select_name = select_name
  s.read_error = nil
  rebuild()
  return true
end

----------------------------------------
-- Auxiliary popups (prompt / confirm / help)
----------------------------------------

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function close_win(win)
  if valid_win(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

---Open a float defensively. Returns `win` or `nil, err`.
local function open_float(buf, enter, cfg)
  local ok, win, err = pcall(vim.api.nvim_open_win, buf, enter, cfg)
  if not ok then
    return nil, tostring(win)
  end
  if not win then
    return nil, tostring(err)
  end
  return win
end

local function track_aux(win, buf)
  if state then
    state.aux[#state.aux + 1] = { win = win, buf = buf }
  end
end

local function untrack_aux(win)
  if not state then
    return
  end
  for i, aux in ipairs(state.aux) do
    if aux.win == win then
      table.remove(state.aux, i)
      return
    end
  end
end

local function restore_focus(win)
  if valid_win(win) then
    pcall(vim.api.nvim_set_current_win, win)
  end
end

---Single-line input popup with inline validation feedback.
---@param spec table {title, default, hint, validate, on_submit}
local function prompt(spec)
  if not state then
    return
  end
  local columns, lines = vim.o.columns, vim.o.lines
  local width = math.max(20, math.min(52, columns - 8))
  width = math.max(1, math.min(width, columns - 2))
  local row = math.max(0, math.min(math.floor((lines - 3) / 2), lines - 4))
  local col = math.max(0, math.floor((columns - width) / 2))
  local prev_win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  local default = spec.default or ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = -1
  vim.bo[buf].modifiable = true

  local base_hl = "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle,FloatFooter:FloatFooter"
  local win, werr = open_float(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " " .. (spec.title or "input") .. " ",
    title_pos = "left",
    footer = " " .. (spec.hint or "Enter confirm · Esc cancel") .. " ",
    footer_pos = "center",
  })
  if not win then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    notify("cannot open input: " .. tostring(werr), vim.log.levels.ERROR)
    return
  end
  vim.wo[win].winhighlight = base_hl
  vim.wo[win].cursorline = true
  track_aux(win, buf)

  local closed = false
  local function finish()
    if closed then
      return
    end
    closed = true
    close_win(win)
    untrack_aux(win)
    restore_focus(prev_win)
  end

  local function submit()
    if closed then
      return
    end
    local value = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    if spec.validate then
      local ok, err = spec.validate(value)
      if not ok then
        vim.wo[win].winhighlight = base_hl:gsub(
          "FloatFooter:FloatFooter",
          "FloatFooter:FileManagerPromptError"
        )
        pcall(vim.api.nvim_win_set_config, win, {
          footer = " " .. tostring(err) .. " ",
          footer_pos = "left",
        })
        return
      end
    end
    finish()
    if spec.on_submit then
      pcall(spec.on_submit, value)
    end
  end

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, "<CR>", submit, { buffer = buf, silent = true, nowait = true })
    vim.keymap.set(mode, "<Esc>", finish, { buffer = buf, silent = true, nowait = true })
    vim.keymap.set(mode, "<C-c>", finish, { buffer = buf, silent = true, nowait = true })
  end

  vim.api.nvim_win_set_cursor(win, { 1, #default })
  pcall(vim.cmd, "startinsert!")
end

---Confirmation popup. The callback receives exactly one boolean.
---@param spec table {title, lines, warn, hint}
---@param cb fun(confirmed: boolean)
local function confirm(spec, cb)
  if not state then
    return
  end
  local columns, lines = vim.o.columns, vim.o.lines
  local width = math.max(24, math.min(54, columns - 8))
  width = math.max(1, math.min(width, columns - 2))
  local body = spec.lines or { "Are you sure?" }
  local height = math.max(1, math.min(#body, lines - 4))
  local row = math.max(0, math.floor((lines - height) / 2) - 1)
  local col = math.max(0, math.floor((columns - width) / 2))
  local prev_win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  local shown = {}
  for i = 1, height do
    shown[i] = fit_head(body[i] or "", width)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, shown)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = -1
  vim.bo[buf].modifiable = false

  local win, werr = open_float(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. (spec.title or "confirm") .. " ",
    title_pos = "left",
    footer = " " .. (spec.hint or "y confirm · n cancel") .. " ",
    footer_pos = "center",
  })
  if not win then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    notify("cannot open confirmation: " .. tostring(werr), vim.log.levels.ERROR)
    return
  end
  vim.wo[win].winhighlight =
    "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle,FloatFooter:FloatFooter"
  vim.wo[win].cursorline = false
  track_aux(win, buf)

  if spec.warn then
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, "FileManagerConfirm", 0, 0, -1)
  end

  local closed = false
  local function finish(yes)
    if closed then
      return
    end
    closed = true
    close_win(win)
    untrack_aux(win)
    restore_focus(prev_win)
    if cb then
      pcall(cb, yes)
    end
  end

  for _, mode in ipairs({ "n" }) do
    vim.keymap.set(mode, "y", function() finish(true) end, { buffer = buf, silent = true, nowait = true })
    vim.keymap.set(mode, "n", function() finish(false) end, { buffer = buf, silent = true, nowait = true })
    vim.keymap.set(mode, "q", function() finish(false) end, { buffer = buf, silent = true, nowait = true })
    vim.keymap.set(mode, "<Esc>", function() finish(false) end, { buffer = buf, silent = true, nowait = true })
    vim.keymap.set(mode, "<C-c>", function() finish(false) end, { buffer = buf, silent = true, nowait = true })
  end
end

local function show_help()
  if not state then
    return
  end
  local rows = {
    { section = "Navigation" },
    { "j / k", "move down / up" },
    { "gg / G", "first / last entry" },
    { "Ctrl-d / Ctrl-u", "half page down / up" },
    { "l / Enter / o", "open file or enter directory" },
    { "h / -", "parent directory" },
    { "s / v / t", "split / vsplit / new tab" },
    { section = "Files" },
    { "a / A", "new file / new folder" },
    { "i / r", "rename" },
    { "d", "delete marks or cursor (confirmed)" },
    { "y / x", "copy / move marks or cursor" },
    { "p", "paste into this directory" },
    { "m / M", "mark / clear marks" },
    { ".", "show / hide dotfiles" },
    { "/ / Ctrl-l", "filter / clear filter" },
    { "R", "refresh" },
    { "~", "home directory" },
    { "q / Esc", "close" },
    { "<Space>e", "toggle from anywhere" },
  }

  local body = {}
  for _, row in ipairs(rows) do
    if row.section then
      body[#body + 1] = row.section
    elseif row[1] then
      body[#body + 1] = ("  %-14s %s"):format(row[1], row[2])
    else
      body[#body + 1] = ""
    end
  end

  local columns, lines = vim.o.columns, vim.o.lines
  local width = math.max(24, math.min(62, columns - 6))
  width = math.max(1, math.min(width, columns - 2))
  local height = math.max(1, math.min(#body, lines - 3))
  local row = math.max(0, math.floor((lines - height) / 2) - 1)
  local col = math.max(0, math.floor((columns - width) / 2))
  local prev_win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  local shown = {}
  for i = 1, height do
    shown[i] = fit_head(body[i] or "", width)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, shown)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = -1
  vim.bo[buf].modifiable = false

  local win, werr = open_float(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " file manager · keys ",
    title_pos = "left",
    footer = " ? or q close ",
    footer_pos = "center",
  })
  if not win then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    notify("cannot open help: " .. tostring(werr), vim.log.levels.ERROR)
    return
  end
  vim.wo[win].winhighlight =
    "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle,FloatFooter:FloatFooter"
  vim.wo[win].cursorline = false
  track_aux(win, buf)

  for i, row_data in ipairs(rows) do
    if i > height then
      break
    end
    if row_data.section then
      pcall(vim.api.nvim_buf_add_highlight, buf, ns, "FileManagerHelpSection", i - 1, 0, -1)
    elseif row_data[1] then
      pcall(vim.api.nvim_buf_add_highlight, buf, ns, "FileManagerHelpKey", i - 1, 2, 2 + #row_data[1])
      pcall(vim.api.nvim_buf_add_highlight, buf, ns, "FileManagerHelpDesc", i - 1, 17, -1)
    end
  end

  local closed = false
  local function finish()
    if closed then
      return
    end
    closed = true
    close_win(win)
    untrack_aux(win)
    restore_focus(prev_win)
  end
  for _, key in ipairs({ "q", "?", "<Esc>", "<C-c>" }) do
    vim.keymap.set("n", key, finish, { buffer = buf, silent = true, nowait = true })
  end
end

----------------------------------------
-- Filesystem actions
----------------------------------------

---A file created or renamed while a filter is active should be visible.
local function reveal_name(name)
  if state and state.filter ~= "" and not name:lower():find(state.filter:lower(), 1, true) then
    state.filter = ""
  end
end

local function create_entry(kind, name)
  if not state then
    return false, "file manager is not open"
  end
  local ok, err = validate_name(name)
  if not ok then
    return false, err
  end
  local path = join(state.cwd, name)
  if uv.fs_lstat(path) then
    return false, "already exists"
  end
  if kind == "directory" then
    local made, merr = uv.fs_mkdir(path, 493) -- 0o755
    if not made then
      return false, tostring(merr)
    end
  else
    -- "wx" is exclusive: even if a file appears between the lstat check and
    -- this call, an existing file is never truncated.
    local fd, oerr = uv.fs_open(path, "wx", 420) -- 0o644
    if not fd then
      return false, tostring(oerr)
    end
    uv.fs_close(fd)
  end
  reveal_name(name)
  refresh(name)
  return true
end

local function new_entry(kind)
  if not state then
    return
  end
  local label = kind == "directory" and "new folder" or "new file"
  prompt({
    title = " " .. label .. " ",
    hint = "Enter create · Esc cancel",
    validate = function(value)
      local ok, err = validate_name(value)
      if not ok then
        return false, err
      end
      if uv.fs_lstat(join(state.cwd, value)) then
        return false, "already exists"
      end
      return true
    end,
    on_submit = function(value)
      local ok, err = create_entry(kind, value)
      if not ok then
        notify(err, vim.log.levels.ERROR)
      end
    end,
  })
end

local function delete_path(path)
  local st = uv.fs_lstat(path)
  if not st then
    return true -- already gone; deletion is idempotent
  end
  if st.type == "directory" then
    local scanner, serr = uv.fs_scandir(path)
    if not scanner then
      return false, tostring(serr)
    end
    while true do
      local name = uv.fs_scandir_next(scanner)
      if not name then
        break
      end
      local ok, err = delete_path(join(path, name))
      if not ok then
        return false, err
      end
    end
    local removed, rerr = uv.fs_rmdir(path)
    return removed and true or false, rerr and tostring(rerr) or nil
  end
  local removed, uerr = uv.fs_unlink(path)
  return removed and true or false, uerr and tostring(uerr) or nil
end

local function prune_clipboard(path)
  if not clipboard then
    return
  end
  local kept = {}
  for _, candidate in ipairs(clipboard.paths) do
    if candidate ~= path and candidate:sub(1, #path + 1) ~= path .. "/" then
      kept[#kept + 1] = candidate
    end
  end
  clipboard.paths = kept
  if #kept == 0 then
    clipboard = nil
  end
end

local function delete_current()
  local targets = marked_paths()
  if #targets == 0 then
    local entry = current_entry()
    if not entry then
      return
    end
    targets = { entry.path }
  end
  local summary
  if #targets == 1 then
    summary = fit_head(sanitize(vim.fs.basename(targets[1])), 36)
  else
    summary = ("%d items"):format(#targets)
  end

  confirm({
    title = " delete ",
    warn = true,
    lines = {
      "Delete " .. summary .. "?",
      "This cannot be undone.",
    },
    hint = "y delete · n cancel",
  }, function(yes)
    if not yes then
      return
    end
    for _, path in ipairs(targets) do
      local ok, err = delete_path(path)
      if ok then
        if state then
          state.marked[path] = nil
        end
        prune_clipboard(path)
      else
        notify(("delete failed for %s: %s"):format(vim.fs.basename(path), tostring(err)),
          vim.log.levels.ERROR)
      end
    end
    refresh()
  end)
end

local function rebase_marks(old_path, new_path)
  if not state then
    return
  end
  local keys = {}
  for path in pairs(state.marked) do
    keys[#keys + 1] = path
  end
  for _, path in ipairs(keys) do
    if path == old_path then
      state.marked[path] = nil
      state.marked[new_path] = true
    elseif path:sub(1, #old_path + 1) == old_path .. "/" then
      state.marked[path] = nil
      state.marked[new_path .. path:sub(#old_path + 1)] = true
    end
  end
end

local function rebase_clipboard(old_path, new_path)
  if not clipboard then
    return
  end
  local paths = {}
  for _, path in ipairs(clipboard.paths) do
    if path == old_path then
      paths[#paths + 1] = new_path
    elseif path:sub(1, #old_path + 1) == old_path .. "/" then
      paths[#paths + 1] = new_path .. path:sub(#old_path + 1)
    else
      paths[#paths + 1] = path
    end
  end
  clipboard.paths = paths
end

local function rename_path(old_path, new_name)
  local ok, err = validate_name(new_name)
  if not ok then
    return false, err
  end
  if not state then
    return false, "file manager is not open"
  end
  local dest = join(state.cwd, new_name)
  if dest == old_path then
    return true
  end
  if uv.fs_lstat(dest) then
    return false, "already exists"
  end
  local moved, merr = uv.fs_rename(old_path, dest)
  if not moved then
    return false, tostring(merr)
  end
  rebase_marks(old_path, dest)
  rebase_clipboard(old_path, dest)
  reveal_name(new_name)
  refresh(new_name)
  return true
end

local function rename_current()
  local entry = current_entry()
  if not entry then
    return
  end
  prompt({
    title = " rename ",
    default = entry.name,
    hint = "Enter rename · Esc cancel",
    validate = function(value)
      local ok, err = validate_name(value)
      if not ok then
        return false, err
      end
      if value ~= entry.name and uv.fs_lstat(join(state.cwd, value)) then
        return false, "already exists"
      end
      return true
    end,
    on_submit = function(value)
      local ok, err = rename_path(entry.path, value)
      if not ok then
        notify("rename failed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  })
end

---Copy a file tree recursively, preserving symlinks. Rolls back partial
---destinations on failure.
local function copy_walk(src, dest)
  local st, serr = uv.fs_lstat(src)
  if not st then
    return false, tostring(serr)
  end
  if st.type == "link" then
    local target, rerr = uv.fs_readlink(src)
    if not target then
      return false, tostring(rerr)
    end
    local made, merr = uv.fs_symlink(target, dest)
    return made and true or false, merr and tostring(merr) or nil
  elseif st.type == "directory" then
    local made, merr = uv.fs_mkdir(dest, 493)
    if not made then
      return false, tostring(merr)
    end
    local scanner, cerr = uv.fs_scandir(src)
    if not scanner then
      return false, tostring(cerr)
    end
    while true do
      local name = uv.fs_scandir_next(scanner)
      if not name then
        break
      end
      local ok, err = copy_walk(join(src, name), join(dest, name))
      if not ok then
        return false, err
      end
    end
    return true
  end
  local copied, cerr = uv.fs_copyfile(src, dest)
  return copied and true or false, cerr and tostring(cerr) or nil
end

local function copy_path(src, dest)
  if src == dest then
    return false, "source and destination are the same"
  end
  if uv.fs_lstat(dest) then
    return false, "destination exists"
  end
  local ok, err = copy_walk(src, dest)
  if not ok then
    pcall(delete_path, dest)
    return false, err
  end
  return true
end

local function move_path(src, dest)
  if src == dest then
    return true
  end
  if uv.fs_lstat(dest) then
    return false, "destination exists"
  end
  local ok, err = uv.fs_rename(src, dest)
  if ok then
    return true
  end
  local message = tostring(err):lower()
  if message:find("cross%-device") or message:find("exdev") then
    local copied, cerr = copy_path(src, dest)
    if not copied then
      return false, cerr
    end
    local removed, rerr = delete_path(src)
    if not removed then
      return false, rerr
    end
    return true
  end
  return false, tostring(err)
end

local function unique_dest(dir, name)
  local candidate = join(dir, name)
  if not uv.fs_lstat(candidate) then
    return candidate
  end
  local base, ext = name, ""
  local dot = name:match("^.*()%.")
  if dot and dot > 1 then
    base = name:sub(1, dot - 1)
    ext = name:sub(dot)
  end
  local n = 1
  while true do
    local tag = n == 1 and " copy" or (" copy %d"):format(n)
    candidate = join(dir, base .. tag .. ext)
    if not uv.fs_lstat(candidate) then
      return candidate
    end
    n = n + 1
  end
end

function marked_paths()
  local paths = {}
  if state then
    for path in pairs(state.marked) do
      paths[#paths + 1] = path
    end
  end
  table.sort(paths)
  -- A marked directory already covers its marked descendants; operating on
  -- both would copy/delete the same subtree twice.
  local out = {}
  for _, path in ipairs(paths) do
    local covered = false
    for _, parent in ipairs(out) do
      if path == parent or path:sub(1, #parent + 1) == parent .. "/" then
        covered = true
        break
      end
    end
    if not covered then
      out[#out + 1] = path
    end
  end
  return out
end

local function set_clipboard(op)
  local paths = marked_paths()
  if #paths == 0 then
    local entry = current_entry()
    if entry then
      paths = { entry.path }
    end
  end
  if #paths == 0 then
    notify("nothing to " .. (op == "copy" and "copy" or "move"), vim.log.levels.INFO)
    return
  end
  clipboard = { op = op, paths = paths }
  if state then
    state.marked = {}
    render()
  end
end

local function paste()
  if not state then
    return
  end
  if not clipboard or #clipboard.paths == 0 then
    notify("clipboard is empty", vim.log.levels.INFO)
    return
  end

  local clip = {
    op = clipboard.op,
    paths = vim.deepcopy(clipboard.paths),
  }
  local index = 1

  local function step()
    if not state then
      return
    end
    if index > #clip.paths then
      if clip.op == "move" then
        clipboard = nil
      end
      refresh()
      return
    end

    local src = clip.paths[index]
    index = index + 1
    local st = uv.fs_lstat(src)
    if not st then
      notify("skipped missing item: " .. display_path(src), vim.log.levels.WARN)
      step()
      return
    end

    local name = vim.fs.basename(src)
    local dest = join(state.cwd, name)
    if src == dest then
      if clip.op == "move" then
        notify("already in this directory: " .. name, vim.log.levels.INFO)
        step()
        return
      end
      dest = unique_dest(state.cwd, name)
    end
    if st.type == "directory" and (dest == src or dest:sub(1, #src + 1) == src .. "/") then
      notify("cannot place a folder inside itself: " .. name, vim.log.levels.ERROR)
      step()
      return
    end

    local function apply()
      local ok, err
      if clip.op == "move" then
        ok, err = move_path(src, dest)
      else
        ok, err = copy_path(src, dest)
      end
      if not ok then
        notify(("paste failed for %s: %s"):format(name, tostring(err)), vim.log.levels.ERROR)
      end
      step()
    end

    if uv.fs_lstat(dest) then
      confirm({
        title = " replace ",
        warn = true,
        lines = {
          "Replace " .. fit_head(sanitize(name), 36) .. "?",
          "The existing item will be deleted.",
        },
        hint = "y replace · n skip",
      }, function(yes)
        if not state then
          return
        end
        if not yes then
          step()
          return
        end
        local removed, rerr = delete_path(dest)
        if not removed then
          notify("cannot replace " .. name .. ": " .. tostring(rerr), vim.log.levels.ERROR)
          step()
          return
        end
        apply()
      end)
    else
      apply()
    end
  end

  step()
end

local function move_cursor(delta)
  if not state or #state.view == 0 then
    return
  end
  local target = clamp(state.cursor + delta, 1, #state.view)
  if target ~= state.cursor then
    state.cursor = target
    render()
  end
end

local function jump_cursor(target)
  if not state or #state.view == 0 then
    return
  end
  local next_cursor = target == "last" and #state.view or 1
  if next_cursor ~= state.cursor then
    state.cursor = next_cursor
    render()
  end
end

local function toggle_mark()
  local entry = current_entry()
  if not entry or not state then
    return
  end
  if state.marked[entry.path] then
    state.marked[entry.path] = nil
  else
    state.marked[entry.path] = true
  end
  state.cursor = math.min(#state.view, state.cursor + 1)
  render()
end

local function clear_marks()
  if not state then
    return
  end
  state.marked = {}
  render()
end

local function toggle_hidden()
  if not state then
    return
  end
  state.show_hidden = not state.show_hidden
  M.opts.show_hidden = state.show_hidden
  state.cursor = 1
  rebuild()
end

local function filter_prompt()
  if not state then
    return
  end
  prompt({
    title = " filter ",
    default = state.filter,
    hint = "Enter apply · Esc keep current",
    on_submit = function(value)
      if not state then
        return
      end
      state.filter = value
      state.cursor = 1
      rebuild()
    end,
  })
end

local function clear_filter()
  if not state or state.filter == "" then
    return
  end
  state.filter = ""
  state.cursor = 1
  rebuild()
end

local function go_home()
  if not state then
    return
  end
  local home = uv.os_homedir()
  if home then
    set_directory(home)
  end
end

local function go_parent()
  if not state then
    return
  end
  local parent = vim.fs.dirname(state.cwd)
  if not parent or parent == state.cwd or parent == "" then
    notify("already at the root of this view", vim.log.levels.INFO)
    return
  end
  set_directory(parent, vim.fs.basename(state.cwd))
end

local function open_current(mode)
  local entry = current_entry()
  if not entry then
    return
  end
  if entry.is_dir then
    set_directory(entry.path)
    return
  end
  local st = uv.fs_stat(entry.path)
  if not st then
    notify("no longer exists: " .. entry.name, vim.log.levels.WARN)
    refresh()
    return
  end
  if st.type == "directory" then
    set_directory(entry.path)
    return
  end
  if st.type ~= "file" then
    notify("not a regular file: " .. entry.name, vim.log.levels.WARN)
    return
  end

  local target = entry.path
  local commands = {
    edit = "edit",
    split = "split",
    vsplit = "vsplit",
    tab = "tabedit",
  }
  local cmd = commands[mode] or "edit"
  close()
  local ok, err = pcall(vim.cmd, { cmd = cmd, args = { vim.fn.fnameescape(target) } })
  if not ok then
    notify("open failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

----------------------------------------
-- Panel lifecycle
----------------------------------------

local function resolve_start(start_dir)
  if start_dir and start_dir ~= "" then
    local expanded = vim.fn.fnamemodify(start_dir, ":p")
    if #expanded > 1 then
      expanded = expanded:gsub("/+$", "")
    end
    local st = uv.fs_stat(expanded)
    if st and st.type == "directory" then
      return expanded
    elseif st and st.type == "file" then
      return vim.fs.dirname(expanded)
    end
  end

  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" then
    local st = uv.fs_stat(name)
    if st and st.type == "file" then
      local dir = vim.fs.dirname(name)
      if dir and dir ~= "" then
        return dir
      end
    elseif st and st.type == "directory" then
      return name
    end
  end
  return uv.cwd() or uv.os_homedir() or "/"
end

local function setup_buffer(s)
  vim.bo[s.buf].buftype = "nofile"
  vim.bo[s.buf].bufhidden = "wipe"
  vim.bo[s.buf].swapfile = false
  vim.bo[s.buf].undolevels = -1
  vim.bo[s.buf].modifiable = false
  vim.bo[s.buf].filetype = "filemanager"

  local wo = vim.wo[s.win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.wrap = false
  wo.spell = false
  wo.list = false
  wo.cursorline = true
  pcall(function()
    wo.cursorlineopt = "line"
  end)
  wo.scrolloff = 2
  wo.sidescrolloff = 0
  wo.winhighlight =
    "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle,FloatFooter:FloatFooter,CursorLine:FileManagerSelected"
end

local function map_buffer(buf, lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, {
    buffer = buf,
    silent = true,
    nowait = true,
    desc = "File manager: " .. desc,
  })
end

local function setup_mappings(buf)
  map_buffer(buf, "j", function() move_cursor(1) end, "next entry")
  map_buffer(buf, "<Down>", function() move_cursor(1) end, "next entry")
  map_buffer(buf, "<C-n>", function() move_cursor(1) end, "next entry")
  map_buffer(buf, "k", function() move_cursor(-1) end, "previous entry")
  map_buffer(buf, "<Up>", function() move_cursor(-1) end, "previous entry")
  map_buffer(buf, "<C-p>", function() move_cursor(-1) end, "previous entry")
  map_buffer(buf, "gg", function() jump_cursor("first") end, "first entry")
  map_buffer(buf, "G", function() jump_cursor("last") end, "last entry")
  map_buffer(buf, "<C-d>", function()
    if state then
      move_cursor(math.max(1, math.floor(state.height / 2)))
    end
  end, "half page down")
  map_buffer(buf, "<C-u>", function()
    if state then
      move_cursor(-math.max(1, math.floor(state.height / 2)))
    end
  end, "half page up")

  map_buffer(buf, "l", function() open_current("edit") end, "open")
  map_buffer(buf, "<CR>", function() open_current("edit") end, "open")
  map_buffer(buf, "o", function() open_current("edit") end, "open")
  map_buffer(buf, "h", go_parent, "parent directory")
  map_buffer(buf, "-", go_parent, "parent directory")
  map_buffer(buf, "<BS>", go_parent, "parent directory")
  map_buffer(buf, "s", function() open_current("split") end, "open in split")
  map_buffer(buf, "v", function() open_current("vsplit") end, "open in vsplit")
  map_buffer(buf, "t", function() open_current("tab") end, "open in tab")

  map_buffer(buf, "i", rename_current, "rename")
  map_buffer(buf, "a", function() new_entry("file") end, "new file")
  map_buffer(buf, "A", function() new_entry("directory") end, "new folder")
  map_buffer(buf, "r", rename_current, "rename")
  map_buffer(buf, "d", delete_current, "delete")
  map_buffer(buf, "y", function() set_clipboard("copy") end, "copy")
  map_buffer(buf, "x", function() set_clipboard("move") end, "move")
  map_buffer(buf, "p", paste, "paste")
  map_buffer(buf, "m", toggle_mark, "mark")
  map_buffer(buf, "M", clear_marks, "clear marks")

  map_buffer(buf, ".", toggle_hidden, "toggle hidden files")
  map_buffer(buf, "/", filter_prompt, "filter")
  map_buffer(buf, "<C-l>", clear_filter, "clear filter")
  map_buffer(buf, "R", refresh, "refresh")
  map_buffer(buf, "~", go_home, "home directory")
  map_buffer(buf, "?", show_help, "help")
  map_buffer(buf, "q", close, "close")
  map_buffer(buf, "<Esc>", close, "close")
  map_buffer(buf, "<2-LeftMouse>", function()
    if not state then
      return
    end
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    if row <= #state.view then
      state.cursor = row
      open_current("edit")
    end
  end, "open")
end

function close()
  local s = state
  if not s then
    return
  end
  state = nil
  for _, aux in ipairs(s.aux or {}) do
    close_win(aux.win)
    if aux.buf and vim.api.nvim_buf_is_valid(aux.buf) then
      pcall(vim.api.nvim_buf_delete, aux.buf, { force = true })
    end
  end
  if valid_win(s.win) then
    pcall(vim.api.nvim_win_close, s.win, true)
  end
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(s.buf) then
        pcall(vim.api.nvim_buf_delete, s.buf, { force = true })
      end
    end)
  end
  restore_focus(s.origin_win)
end

function M.open(start_dir)
  if state then
    if valid_win(state.win) then
      pcall(vim.api.nvim_set_current_win, state.win)
    end
    return true
  end

  local dir = resolve_start(start_dir)
  local entries, err = read_dir(dir)
  if not entries then
    notify("cannot read " .. display_path(dir) .. ": " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  local origin_win = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_get_current_buf()
  local initial = nil
  local origin_name = vim.api.nvim_buf_get_name(origin_buf)
  if origin_name ~= "" and vim.fs.dirname(origin_name) == dir then
    initial = vim.fs.basename(origin_name)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local s = {
    win = nil,
    buf = buf,
    cwd = dir,
    entries = entries,
    view = {},
    cursor = 1,
    filter = "",
    show_hidden = M.opts.show_hidden,
    marked = {},
    select_name = initial,
    read_error = nil,
    origin_win = origin_win,
    aux = {},
    width = 0,
    height = 0,
  }
  state = s

  local cfg = layout_config()
  local win, werr = open_float(buf, true, cfg)
  if not win then
    state = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    notify("cannot open panel: " .. tostring(werr), vim.log.levels.ERROR)
    return false
  end
  s.win = win
  s.width = cfg.width
  s.height = cfg.height

  setup_buffer(s)
  setup_mappings(buf)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if not state or state.win ~= vim.api.nvim_get_current_win() then
        return
      end
      local row = vim.api.nvim_win_get_cursor(state.win)[1]
      if row >= 1 and row <= #state.view then
        state.cursor = row
      end
    end,
  })

  rebuild()
  pcall(vim.api.nvim_set_current_win, win)
  return true
end

function M.close()
  close()
end

function M.toggle()
  if state then
    close()
  else
    M.open()
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup(augroup, { clear = true })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if not state or state.win ~= win then
        return
      end
      local s = state
      state = nil
      for _, aux in ipairs(s.aux or {}) do
        close_win(aux.win)
        if aux.buf and vim.api.nvim_buf_is_valid(aux.buf) then
          pcall(vim.api.nvim_buf_delete, aux.buf, { force = true })
        end
      end
      if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(s.buf) then
            pcall(vim.api.nvim_buf_delete, s.buf, { force = true })
          end
        end)
      end
      restore_focus(s.origin_win)
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if state then
        render()
      end
    end,
  })

  vim.api.nvim_create_user_command("Files", function(opts)
    M.open(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", complete = "dir", desc = "Open the native file manager" })

  vim.keymap.set("n", "<leader>e", M.toggle, { desc = "Toggle file manager", silent = true })
end

----------------------------------------
-- Test hooks (smoke.sh drives these headlessly)
----------------------------------------

M._open = M.open
M._close = function()
  close()
end
M._refresh = function(select_name)
  refresh(select_name)
end
M._create = create_entry
M._rename = rename_path
M._delete = delete_path
M._copy = copy_path
M._move = move_path
M._unique = unique_dest
M._validate_name = validate_name
M._set_directory = set_directory
M._select = function(name)
  if not state then
    return false
  end
  for i, entry in ipairs(state.view) do
    if entry.name == name then
      state.cursor = i
      render()
      return true
    end
  end
  return false
end
M._move_cursor = move_cursor
M._toggle_mark = toggle_mark
M._yank = set_clipboard
M._paste = paste
M._state = function()
  if not state then
    return nil
  end
  local view = {}
  for _, entry in ipairs(state.view) do
    view[#view + 1] = {
      name = entry.name,
      path = entry.path,
      is_dir = entry.is_dir,
      type = entry.type,
      size = entry.size,
      hidden = entry.hidden,
      link = entry.link,
      broken = entry.broken,
    }
  end
  local marked = marked_paths()
  return {
    cwd = state.cwd,
    cursor = state.cursor,
    filter = state.filter,
    show_hidden = state.show_hidden,
    entries = state.entries,
    view = view,
    marked = marked,
    clipboard = clipboard and { op = clipboard.op, paths = vim.deepcopy(clipboard.paths) } or nil,
    win = state.win,
    buf = state.buf,
    width = state.width,
    height = state.height,
    read_error = state.read_error,
  }
end

return M
