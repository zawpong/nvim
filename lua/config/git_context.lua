-- Git context provider for the single footer statusline.
--
-- Collects and caches repository information asynchronously so the statusline
-- redraw path only reads cached state. No winbar or secondary strip is used.

local u = require("config.utils")

local M = {}

M.opts = {
  events = { "BufEnter", "WinEnter", "BufWritePost", "DirChanged", "FocusGained" },
}

local cache = {}       -- root path -> { branch, dirty, count, known, failed }
local pending = {}     -- root path -> bool
local root_cache = {}  -- bufnr -> root path or false

local function repo_root(bufnr)
  bufnr = bufnr or 0
  if root_cache[bufnr] ~= nil then
    return root_cache[bufnr] or nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  local dir = (name ~= "" and vim.fs.dirname(name) or vim.uv.cwd()) or vim.uv.cwd()
  local found = vim.fs.find(".git", {
    upward = true,
    stop = vim.uv.os_homedir(),
    path = dir,
    limit = 1,
  })[1]
  local root = found and vim.fs.dirname(found) or false
  root_cache[bufnr] = root
  return root or nil
end

local function escape_statusline(s)
  return (s or ""):gsub("%%", "%%%%")
end

local function get_branch(root, cb)
  if vim.fn.executable("git") ~= 1 then
    cb(nil)
    return
  end
  vim.system({ "git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb(nil)
        return
      end
      local b = vim.trim(res.stdout or "")
      if b ~= "" and b ~= "HEAD" then
        cb(b)
        return
      end
      vim.system({ "git", "-C", root, "rev-parse", "--short", "HEAD" }, { text = true }, function(res2)
        vim.schedule(function()
          if res2.code == 0 then
            local sha = vim.trim(res2.stdout or "")
            if sha ~= "" then
              cb(sha)
              return
            end
          end
          cb(b ~= "" and b or "HEAD")
        end)
      end)
    end)
  end)
end

function M.refresh(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local root = repo_root(bufnr)
  if not root then
    return
  end
  if vim.fn.executable("git") ~= 1 then
    cache[root] = { no_git = true }
    return
  end
  if pending[root] then
    return
  end
  pending[root] = true

  local result = { root = root }
  local remaining = 2

  local function finish()
    remaining = remaining - 1
    if remaining <= 0 then
      pending[root] = false
      cache[root] = result
      vim.schedule(function()
        pcall(vim.cmd, "redraw")
      end)
    end
  end

  get_branch(root, function(b)
    result.branch = b
    result.branch_known = (b ~= nil)
    finish()
  end)

  vim.system({ "git", "-C", root, "status", "--porcelain", "-z" }, { text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        local tracked, untracked = 0, 0
        local fields = vim.split(res.stdout or "", "\0", { plain = true })
        local i = 1
        while i <= #fields do
          local rec = fields[i]
          i = i + 1
          if rec ~= "" then
            local status = rec:sub(1, 2)
            if status == "??" then
              untracked = untracked + 1
            else
              tracked = tracked + 1
            end
            -- Rename/copy records are followed by an extra original-path field.
            if status:find("R", 1, true) or status:find("C", 1, true) then
              i = i + 1
            end
          end
        end
        result.tracked = tracked
        result.untracked = untracked
        result.count = tracked + untracked
        result.dirty = (tracked + untracked > 0)
        result.known = true
      else
        result.tracked = nil
        result.untracked = nil
        result.count = nil
        result.dirty = nil
        result.known = false
      end
      finish()
    end)
  end)
end

function M.collect(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local root = repo_root(bufnr)
  if not root then
    return nil
  end
  if vim.fn.executable("git") ~= 1 then
    return nil
  end
  local result = { root = root }
  local r = vim.system({ "git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }):wait()
  local b = nil
  if r.code == 0 then
    b = vim.trim(r.stdout or "")
    if b == "" or b == "HEAD" then
      local r2 = vim.system({ "git", "-C", root, "rev-parse", "--short", "HEAD" }, { text = true }):wait()
      if r2.code == 0 then
        local sha = vim.trim(r2.stdout or "")
        if sha ~= "" then
          b = sha
        end
      end
      if b == "" then
        b = "HEAD"
      end
    end
  end
  result.branch = b
  result.branch_known = (b ~= nil)
  local s = vim.system({ "git", "-C", root, "status", "--porcelain", "-z" }, { text = true }):wait()
  if s.code == 0 then
    local tracked, untracked = 0, 0
    local fields = vim.split(s.stdout or "", "\0", { plain = true })
    local i = 1
    while i <= #fields do
      local rec = fields[i]
      i = i + 1
      if rec ~= "" then
        local status = rec:sub(1, 2)
        if status == "??" then
          untracked = untracked + 1
        else
          tracked = tracked + 1
        end
        if status:find("R", 1, true) or status:find("C", 1, true) then
          i = i + 1
        end
      end
    end
    result.tracked = tracked
    result.untracked = untracked
    result.count = tracked + untracked
    result.dirty = (tracked + untracked > 0)
    result.known = true
  else
    result.tracked = nil
    result.untracked = nil
    result.count = nil
    result.dirty = nil
    result.known = false
  end
  cache[root] = result
  return result
end

-- Formatted Git segment for the footer statusline. Returns "" when unavailable.
-- `active` controls whether accent highlights are used (inactive windows stay
-- muted).
function M.line(bufnr, active)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local root = repo_root(bufnr)
  if not root then
    return ""
  end
  if vim.fn.executable("git") ~= 1 then
    return ""
  end
  local data = cache[root]
  if not data then
    M.refresh(bufnr)
    return ""
  end
  if data.no_git or not data.branch_known or not data.branch then
    return ""
  end

  -- Truncate long branch names gracefully.
  local branch = data.branch
  if #branch > 24 then
    branch = branch:sub(1, 21) .. "..."
  end

  local tracked = data.tracked
  local untracked = data.untracked
  if tracked == nil and untracked == nil and (data.count or 0) > 0 then
    tracked = data.count
    untracked = 0
  end
  tracked = tracked or 0
  untracked = untracked or 0

  local branch_hl = active == false and "StatusLineNC" or "StatusLineGitBranch"
  local dirty_hl = active == false and "StatusLineNC" or "StatusLineGitDirty"
  local untracked_hl = active == false and "StatusLineNC" or "StatusLineGitUntracked"
  local out = "%#" .. branch_hl .. "#" .. escape_statusline(branch)
  if data.known then
    if tracked > 0 then
      out = out .. "%#StatusLineInfo#  " .. "%#" .. dirty_hl .. "#!" .. tracked
    end
    if untracked > 0 then
      out = out .. "%#StatusLineInfo#  " .. "%#" .. untracked_hl .. "#?" .. untracked
    end
  end
  out = out .. "%#StatusLineInfo#"
  return out
end

M.segment = M.line
M.get = M.line

_G.nvim_git_context = function()
  local win = vim.g.statusline_winid
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
    win = vim.api.nvim_get_current_win()
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return M.line(buf)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("nvim_config_git_context", { clear = true })
  for _, ev in ipairs(M.opts.events) do
    vim.api.nvim_create_autocmd(ev, {
      group = group,
      callback = function(ev2)
        M.refresh(ev2 and ev2.buf or 0)
      end,
    })
  end
  vim.api.nvim_create_autocmd({ "BufFilePost", "BufWipeout", "BufDelete" }, {
    group = group,
    callback = function(ev2)
      if ev2 and ev2.buf then
        root_cache[ev2.buf] = nil
      end
    end,
  })

  vim.schedule(function()
    M.refresh(0)
  end)
end

function M._state()
  return { cache = cache, pending = pending, root_cache = root_cache }
end

function M._repo_root(bufnr)
  return repo_root(bufnr or 0)
end

-- Compatibility aliases (kept minimal).
M.update = M.refresh
M.get_line = M.line
M.render = M.line
M.status = M.line
M.apply = M.setup

return M