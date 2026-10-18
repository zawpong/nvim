-- Native zero-plugin search integration.
--
--   <leader>ff  fuzzy file search      (fd; fallback: rg --files; fallback: walk)
--   <leader>fg  live content search    (rg --vimgrep, debounced per keystroke)
--   <leader>fb  buffer search          (listed buffers)
--   <leader>fh  help-topic search      (native :help completion list)
--
-- Design:
--   * External tools are always invoked as ARGUMENT ARRAYS (vim.system) --
--     never as shell strings -- so filenames containing spaces, quotes or
--     special characters are safe and there is no shell-injection surface.
--   * The fuzzy engine is `fzf --filter` when fzf is on PATH (exact fzf
--     semantics, testable headlessly); otherwise the native matchfuzzy()
--     builtin. Both are rolled into one helper so results are consistent.
--   * One shared picker backs all four flows: a centered float plus a
--     preview float. It runs a plain getchar() input loop; no insert-mode
--     state, no buffer-local mappings to unwind.
--   * Background jobs are killed when a new query starts, and the picker
--     drops stale async results when it closes. No orphaned processes, no
--     temp files.
--     The editor boots and edits fine with none of these tools installed;
--     missing dependencies produce an actionable message, not an error.

local u = require("config.utils")

local M = {}

M.opts = {
  hidden = true, -- search hidden files by default
  excludes = { -- fd --exclude / rg --glob "!<dir>/**"
    ".git",
    "node_modules",
    "build",
    "dist",
    "out",
    "target",
    "vendor",
    ".cache",
    ".venv",
    "venv",
    "__pycache__",
  },
  preview_lines = 10, -- context lines shown around the selected match
  max_results = 1000, -- picker rows rendered at once
  grep_debounce_ms = 120,
}

----------------------------------------
-- Tool availability
----------------------------------------

---True when an external tool is usable right now.
---@param name "fzf"|"fd"|"rg"|"rgf" name (rgf = rg used as a file lister)
---@return boolean
function M.has_tool(name)
  if name == "rgf" then
    return u.has("rg")
  end
  return u.has(name)
end

local function notify_missing(tool, install_hint, fallback)
  vim.notify(
    ("Search depends on `%s`, which is not installed.\n%s\nFallback: %s"):format(
      tool, install_hint, fallback
    ),
    vim.log.levels.WARN
  )
end

----------------------------------------
-- Fuzzy engine (fzf --filter | native matchfuzzy)
----------------------------------------

---Return fuzzy-filtered `candidates`. Synchronous; cheap for in-memory lists.
---@param query string
---@param candidates string[]
---@return string[]
local function fuzzy_filter(query, candidates)
  if query == "" then
    return candidates
  end
  if u.has("fzf") and #candidates <= 100000 then
    -- fzf --filter: exit 0 with matches, exit 1 when nothing matched,
    -- other codes mean fzf itself failed (old version, etc.).
    -- Candidates are written to fzf's stdin via the `input` argument
    -- (never a shell pipe).
    local out = vim.fn.systemlist({ "fzf", "--filter", query }, candidates)
    local err = vim.v.shell_error
    if err <= 1 and #out > 0 then
      return out
    elseif err == 1 then
      return {}
    end
    -- fzf failed for a real reason; fall through to the native engine.
  end
  return vim.fn.matchfuzzy(candidates, query)
end

----------------------------------------
-- Shared picker
----------------------------------------

local picker = nil -- active picker state (nil when closed)

local function close_picker()
  local s = picker
  if not s then
    return
  end
  picker = nil
  if s.job then
    pcall(function() s.job:kill("term") end)
    s.job = nil
  end
  if s.preview_win and vim.api.nvim_win_is_valid(s.preview_win) then
    vim.api.nvim_win_close(s.preview_win, true)
  end
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  if s.origin_win and vim.api.nvim_win_is_valid(s.origin_win) then
    pcall(vim.api.nvim_set_current_win, s.origin_win)
  end
  if s.on_close then
    pcall(s.on_close)
  end
end

local function render(s)
  local buf = vim.api.nvim_win_get_buf(s.win)
  local results = fuzzy_filter(s.query, s.candidates)
  s.results = results
  s.selected = math.min(s.selected, math.max(1, #results))
  local lines = { "> " .. s.query }
  local n = math.min(#results, M.opts.max_results)
  for i = 1, n do
    lines[#lines + 1] = (i == s.selected and "> " or "  ") .. results[i]
  end
  if #results > n then
    lines[#lines + 1] = ("  ... %d more"):format(#results - n)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function render_preview(s)
  if not s.preview_win or not vim.api.nvim_win_is_valid(s.preview_win) then
    return
  end
  local pbuf = vim.api.nvim_win_get_buf(s.preview_win)
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { "" })
  vim.api.nvim_buf_clear_namespace(pbuf, s.ns, 0, -1)
  local item = s.results[s.selected]
  if not item or not s.preview_fn then
    return
  end
  local t = s.preview_fn(item)
  if not t or not t.path then
    return
  end
  local ok, content = pcall(vim.fn.readfile, t.path)
  if not ok or not content then
    return
  end
  local line = math.min(t.line or 1, math.max(1, #content))
  local start = math.max(1, line - M.opts.preview_lines)
  local stop = math.min(#content, line + M.opts.preview_lines)
  local lines = {}
  for i = start, stop do
    lines[#lines + 1] = content[i] or ""
  end
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_add_highlight, pbuf, s.ns, "Visual", line - start, 0, -1)
end

local function move(s, delta)
  if #s.results == 0 then
    return
  end
  s.selected = math.min(math.max(1, s.selected + delta), math.min(#s.results, M.opts.max_results))
  render(s)
  render_preview(s)
end

---Accept the current selection: close first (restores focus), then act.
local function accept(s)
  local item = s.results[s.selected]
  close_picker()
  if s.accept_fn then
    pcall(s.accept_fn, item)
  end
end

---Open the shared picker. Runs a synchronous getchar() loop; async callbacks
---(grep results, file sweeps) keep firing while it waits.
---@param spec table
---   prompt string            float title
---   candidates string[]      initial candidate list (may be empty)
---   accept_fn fun(item)      action on Enter; item may be nil
---   preview_fn fun(item)     {path=, line=} | nil for the preview pane
---   on_query fun(q)          invoked on every query change (live grep)
---   on_close fun()           invoked after close (cancels pending work)
local function open_picker(spec)
  close_picker()

  local width = math.max(40, math.min(90, math.floor(vim.o.columns * 0.55)))
  local height = math.max(5, math.min(18, math.floor(vim.o.lines * 0.5)))
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = row, col = col, width = width, height = height,
    style = "minimal", border = "rounded", title = " " .. (spec.prompt or "pick") .. " ",
  })
  local preview_buf = vim.api.nvim_create_buf(false, true)
  local preview_width = math.max(20, math.min(50, math.floor(vim.o.columns * 0.3)))
  local preview_win = vim.api.nvim_open_win(preview_buf, false, {
    relative = "editor", row = row, col = col + width + 2, width = preview_width, height = height,
    style = "minimal", border = "rounded",
  })
  if not win or not preview_win then
    return
  end

  local s = {
    win = win,
    preview_win = preview_win,
    origin_win = vim.api.nvim_get_current_win(),
    candidates = spec.candidates or {},
    results = {},
    query = "",
    selected = 1,
    accept_fn = spec.accept_fn,
    preview_fn = spec.preview_fn,
    on_query = spec.on_query,
    on_close = spec.on_close,
    ns = vim.api.nvim_create_namespace("nvim_config_picker"),
    timer = vim.uv.new_timer(),
  }
  picker = s
  render(s)
  render_preview(s)
  vim.api.nvim_set_current_win(win)

  -- Type-ahead loop. Key bytes: 27 Esc, 13 Enter, 8/127 Backspace,
  -- 10 = Ctrl-J next, 11 = Ctrl-K prev, 14/16 = Ctrl-N/P, 9 Tab prev.
  while true do
    local ok, ch = pcall(vim.fn.getcharstr)
    if not ok or picker ~= s then
      return -- closed by accept/cancel on another path
    end
    local b = ch:byte(1)
    if b == 27 then
      close_picker()
      return
    elseif b == 13 then
      accept(s)
      return
    elseif b == 8 or b == 127 then
      local n = vim.fn.strchars(s.query)
      if n > 0 then
        s.query = vim.fn.strcharpart(s.query, 0, n - 1) -- UTF-8 aware
      end
      s.selected = 1
      render(s)
      render_preview(s)
      if s.on_query then
        pcall(s.on_query, s.query)
      end
    elseif b == 10 or b == 14 then
      move(s, 1)
    elseif b == 11 or b == 16 or b == 9 then
      move(s, -1)
    elseif b == nil or b < 32 then
      -- ignore other control keys
    else
      s.query = s.query .. ch
      s.selected = 1
      render(s)
      render_preview(s)
      if s.on_query then
        pcall(s.on_query, s.query)
      end
    end
  end
end

----------------------------------------
-- Candidate helpers (root-aware, exclusion-aware)
----------------------------------------

---Plugin directory additions (fd) / globs (rg).
---@param cmd string[] command array being built
---@param fd boolean true for fd style, false for rg glob style
local function add_excludes(cmd, fd)
  for _, ex in ipairs(M.opts.excludes) do
    if fd then
      cmd[#cmd + 1] = "--exclude"
      cmd[#cmd + 1] = ex .. "/*"
    else
      cmd[#cmd + 1] = "--glob"
      cmd[#cmd + 1] = "!" .. ex .. "/**"
    end
  end
end

----------------------------------------
-- <leader>ff -- fuzzy file search
----------------------------------------

---Bounded pure-Lua directory walk; last resort when fd and rg are absent.
local function walk_files(root, out, depth)
  if depth > 6 or #out > 5000 then
    return
  end
  local scanner = vim.uv.fs_scandir(root)
  if not scanner then
    return
  end
  while true do
    local name, t = vim.uv.fs_scandir_next(scanner)
    if not name then
      return
    end
    local skipped = false
    for _, ex in ipairs(M.opts.excludes) do
      if name == ex then
        skipped = true
        break
      end
    end
    if not skipped then
      local full = root == "." and name or (root .. "/" .. name)
      if t == "file" then
        out[#out + 1] = full
      elseif t == "directory" then
        walk_files(full, out, depth + 1)
      end
    end
  end
end

---Collect file names under `root`, asynchronously where possible.
---Callback receives (candidates[], tool_name). tool_name "failed" marks a
---command failure with zero output (e.g. unreadable root).
---@param root string
---@param cb fun(candidates: string[], tool: string)
function M.file_candidates(root, cb)
  local cmd
  if M.has_tool("fd") then
    cmd = { "fd", "--type", "f", "--color", "never" }
    if M.opts.hidden then
      cmd[#cmd + 1] = "--hidden"
    end
    add_excludes(cmd, true)
  elseif M.has_tool("rg") then
    cmd = { "rg", "--files", "--color", "never" }
    if M.opts.hidden then
      cmd[#cmd + 1] = "--hidden"
    end
    add_excludes(cmd, false)
  end

  if cmd then
    local running = true
    vim.system(cmd, { cwd = root, text = true }, function(res)
      if not running then
        return -- picker gone; drop results
      end
      local out = {}
      local prefix = (root ~= "." and root ~= "/" and not root:match("/$")) and (root .. "/") or nil
      for path in vim.gsplit(res.stdout or "", "\n", { plain = true }) do
        if path ~= "" then
          if prefix and path:sub(1, #prefix) == prefix then
            path = path:sub(#prefix + 1) -- display root-relative in the picker
          end
          out[#out + 1] = path
        end
      end
      local tool_ok = res.code == 0 or #out > 0
      cb(out, tool_ok and (cmd[1] == "fd" and "fd" or "rg --files") or "failed")
    end)
    return
  end

  notify_missing(
    "fd",
    "  Arch:   sudo pacman -S fd ripgrep\n  Debian: sudo apt install fd-find ripgrep\n  Fedora: sudo dnf install fd-find ripgrep\n  macOS:  brew install fd ripgrep",
    "bounded directory walk (depth 6)"
  )
  local out = {}
  walk_files(root, out, 0)
  cb(out, "walk")
end

---Fuzzy file search, rooted at the project root (or CWD outside a project).
function M.find_files()
  local root = u.project_root(0)
  local running = true
  M.file_candidates(root, function(candidates, tool)
    if not running or picker then
      return -- superseded by a new invocation
    end
    if tool == "failed" then
      vim.notify(("File search failed under %s (tool: %s)."):format(root, tool), vim.log.levels.WARN)
      return
    end
    if #candidates == 0 then
      vim.notify(("No files found under %s"):format(root), vim.log.levels.INFO)
      return
    end
    local abs = function(item)
      if item:sub(1, 1) == "/" then
        return item
      end
      return root == "." and item or (root .. "/" .. item)
    end
    open_picker({
      prompt = "find files (" .. tool .. ")",
      candidates = candidates,
      on_close = function()
        running = false
      end,
      accept_fn = function(item)
        if item then
          vim.cmd({ cmd = "edit", args = { vim.fn.fnameescape(abs(item)) } })
        end
      end,
      preview_fn = function(item)
        return item and { path = abs(item), line = 1 } or nil
      end,
    })
  end)
end

----------------------------------------
-- <leader>fg -- live content search
----------------------------------------

---Split an rg --vimgrep row "path:line:col:text".
---@param row string
---@return string? path, integer? line, integer? col
local function parse_vimgrep(row)
  local path, ln, col, text = row:match("^(.-):(%d+):(%d+):(.*)$")
  if not path or not ln then
    return nil
  end
  return path, tonumber(ln), tonumber(col)
end

---Live grep. The picker starts empty; every keystroke (debounced) spawns
---`rg --vimgrep` and refreshes the list. Previous job is killed first.
function M.live_grep()
  if not M.has_tool("rg") then
    notify_missing(
      "rg",
      "  Arch:   sudo pacman -S ripgrep\n  Debian: sudo apt install ripgrep\n  Fedora: sudo dnf install ripgrep\n  macOS:  brew install ripgrep",
      ":vim /pattern/j ../* -- classic vimgrep still works"
    )
    return
  end
  local root = u.project_root(0)
  local base = { "rg", "--vimgrep", "--color", "never", "--smart-case", "--no-messages", "--" }
  if M.opts.hidden then
    base[#base + 1] = "--hidden"
    base[#base + 1] = "--glob"
    base[#base + 1] = "!.git/**"
  end
  add_excludes(base, false)

  local job = nil

  local function search(query)
    if job then
      pcall(function() job:kill("term") end)
      job = nil
    end
    if picker == nil or picker.query ~= query then
      return -- stale keystroke or picker already closed
    end
    if query == "" then
      picker.candidates = {}
      render(picker)
      render_preview(picker)
      return
    end
    job = vim.system(vim.list_extend(vim.deepcopy(base), { query }), { cwd = root, text = true }, function(res)
      job = nil
      local s = picker
      if not s or s.query ~= query then
        return -- picker closed, or a newer query superseded us
      end
      local items = {}
      for row in vim.gsplit(res.stdout or "", "\n", { plain = true }) do
        if row ~= "" then
          items[#items + 1] = row
        end
      end
      s.candidates = items
      s.selected = 1
      render(s)
      render_preview(s)
    end)
    if picker then
      picker.job = job -- so close_picker kills an in-flight search
    end
  end

  -- Debounced on_query: collapse keystroke bursts into one rg process.
  local function on_query(query)
    local s = picker
    if not s then
      return
    end
    s.timer:stop()
    s.timer:start(M.opts.grep_debounce_ms, 0, function()
      vim.schedule(function()
        if picker and picker.query == query then
          search(query)
        end
      end)
    end)
  end

  open_picker({
    prompt = "live grep (rg)",
    candidates = {},
    on_query = on_query,
    on_close = function()
      if job then
        pcall(function() job:kill("term") end)
        job = nil
      end
    end,
    accept_fn = function(item)
      if not item then
        return
      end
      local path, ln, col = parse_vimgrep(item)
      if not path then
        return
      end
      local abs = path:sub(1, 1) == "/" and path or (root == "." and path or (root .. "/" .. path))
      vim.cmd({ cmd = "edit", args = { vim.fn.fnameescape(abs) } })
      -- Jump after the window switch settles.
      vim.schedule(function()
        pcall(vim.api.nvim_win_set_cursor, 0, { ln, math.max(0, col - 1) })
        vim.cmd("normal! zz")
      end)
    end,
    preview_fn = function(item)
      local path, ln = parse_vimgrep(item or "")
      if not path then
        return nil
      end
      local abs = path:sub(1, 1) == "/" and path or (root == "." and path or (root .. "/" .. path))
      return { path = abs, line = ln or 1 }
    end,
  })
end

----------------------------------------
-- <leader>fb -- buffer search
----------------------------------------

function M.buffers_search()
  local listed = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted and vim.bo[b].buftype == "" then
      local name = vim.api.nvim_buf_get_name(b)
      listed[#listed + 1] = name == "" and ("%d [No Name]"):format(b) or name
    end
  end
  if #listed == 0 then
    vim.notify("No listed buffers", vim.log.levels.INFO)
    return
  end
  open_picker({
    prompt = "buffers",
    candidates = listed,
    accept_fn = function(item)
      if not item then
        return
      end
      local bufnr = item:match("^(%d+) ")
      if bufnr then
        vim.api.nvim_set_current_buf(tonumber(bufnr))
      else
        vim.cmd({ cmd = "buffer", args = { vim.fn.fnameescape(item) } })
      end
    end,
    preview_fn = function(item)
      if not item or item:match("^(%d+) ") then
        return nil
      end
      return { path = item, line = 1 }
    end,
  })
end

----------------------------------------
-- <leader>fh -- help search
----------------------------------------

function M.help_search()
  local topics = vim.fn.getcompletion("", "help")
  if #topics == 0 then
    vim.notify("No help topics available", vim.log.levels.WARN)
    return
  end
  open_picker({
    prompt = "help",
    candidates = topics,
    accept_fn = function(item)
      if item then
        pcall(vim.cmd, { cmd = "help", args = { item } })
      end
    end,
    preview_fn = nil, -- :help renders its own window
  })
end

----------------------------------------
-- Setup (idempotent)
----------------------------------------

function M.setup()
  local commands = {
    SearchFiles = M.find_files,
    SearchGrep = M.live_grep,
    SearchBuffers = M.buffers_search,
    SearchHelp = M.help_search,
  }
  for name, fn in pairs(commands) do
    vim.api.nvim_create_user_command(name, function(opts)
      fn()
    end, { desc = name })
  end
end

-- Expose internals for tests (smoke.sh drives them headlessly).
M._open_picker = open_picker
M._fuzzy_filter = fuzzy_filter
M._close_picker = close_picker
M._parse_vimgrep = parse_vimgrep

return M
