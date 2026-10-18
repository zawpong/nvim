-- Native image support (Neovim 0.13+, EXPERIMENTAL upstream).
--
-- Verified behavior (checked against the docs and implementation shipped in
-- the running build: runtime/doc/lua.txt and runtime/lua/vim/ui/img.lua):
--   * `vim.ui.img.set(data, {row, col, width, height, zindex}) -> id`
--     displays PNG bytes via the Kitty graphics protocol; `vim.ui.img.del(id)`
--     removes one image, `del(math.huge)` removes all. Sending `del()` with
--     no argument throws (`id: expected number, got nil`), so the id returned
--     by `set()` is tracked and passed back.
--   * Upstream exposes `vim.ui.img._supported()` which QUERIES the terminal
--     (Kitty APC handshake) instead of guessing from $TERM. This module uses
--     that probe, guarded with pcall because the whole API is experimental.
--   * Pixels are embedded in the escape stream (`t=d`, base64, 4 KiB chunks);
--     file-path transmission (`t=f`) is NOT implemented upstream, so the
--     image is read into memory before being shown.
--   * Upstream sends raw `\027_G` sequences with no tmux DCS passthrough, so
--     inside tmux the terminal query gets no answer and rendering is
--     unsupported — the probe reports that honestly instead of by assumption.
--   * The API is EXPERIMENTAL and may change until 0.13 drops that marker;
--     every call is guarded with pcall and failures are reported, not hidden.
--   * No plugin, no external converter, no custom renderer.

local M = {}

M._last = nil -- placement id returned by the last successful :ImageShow

local PNG_SIGNATURE = "\137PNG\r\n\026\n"
local PROBE_TIMEOUT_MS = 500
local MAX_IMAGE_BYTES = 12 * 1024 * 1024

local function env_hint()
  local bits = {}
  if vim.env.TMUX then
    bits[#bits + 1] = "inside tmux (upstream vim.ui.img implements no tmux passthrough)"
  end
  if vim.env.TERM and vim.env.TERM ~= "" then
    bits[#bits + 1] = "TERM=" .. vim.env.TERM
  end
  if vim.env.TERM_PROGRAM and vim.env.TERM_PROGRAM ~= "" then
    bits[#bits + 1] = "TERM_PROGRAM=" .. vim.env.TERM_PROGRAM
  end
  return #bits > 0 and table.concat(bits, "; ") or "terminal environment: no TERM information"
end

---Capability decided by ASKING THE TERMINAL (upstream probe), never guessed
---from environment variables. Fails closed with an actionable reason.
---@param opts? {timeout?: integer}
---@return { supported = boolean, reason = string }
function M.capability(opts)
  opts = opts or {}
  if vim.fn.has("nvim-0.13") ~= 1 then
    local v = vim.version()
    local label = ("%d.%d.%d"):format(v.major, v.minor, v.patch or 0)
    if v.prerelease and v.prerelease ~= "" then
      label = label .. "-" .. v.prerelease
    end
    return {
      supported = false,
      reason = ("vim.ui.img needs Neovim 0.13 or newer (currently %s, nightly-only, experimental)"):format(label),
    }
  end
  local ok_loaded, img = pcall(require, "vim.ui.img")
  if not ok_loaded or type(img) ~= "table" or type(img.set) ~= "function" or type(img.del) ~= "function" then
    return { supported = false, reason = "vim.ui.img is not present in this build" }
  end
  if type(img._supported) ~= "function" then
    -- About to change upstream: capability probe itself is experimental.
    return {
      supported = false,
      reason = "vim.ui.img._supported (capability probe) is missing in this build; " .. env_hint(),
    }
  end
  local ok_probe, supported, msg = pcall(img._supported, { timeout = opts.timeout or PROBE_TIMEOUT_MS })
  if not ok_probe then
    return {
      supported = false,
      reason = ("capability probe failed: %s; %s"):format(tostring(supported), env_hint()),
    }
  end
  if not supported then
    local base = msg
        and ("terminal responded to the kitty graphics protocol query with an error: %s"):format(msg)
      or "terminal did not answer the kitty graphics protocol query"
    return { supported = false, reason = base .. "; " .. env_hint() }
  end
  return { supported = true, reason = "terminal confirmed kitty graphics protocol support" }
end

---Screen position (terminal cells, 1-indexed) at the current cursor, used as
---the default image placement.
---@return { row: integer, col: integer }
local function image_pos()
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local sp = vim.fn.screenpos(win, cursor[1], cursor[2] + 1)
  if type(sp) == "table" and sp.row >= 1 and sp.col >= 1 then
    return { row = sp.row, col = sp.col + 2 }
  end
  return { row = 1, col = 1 }
end

---`:ImageShow {path}` — display a local PNG (the only format the kitty
---graphics protocol requires hosts to handle; other formats pass through to
---the host renderer if the terminal supports them). Shows at the cursor.
---No downloads, no fabricated sizes: without width/height opts the terminal
---renders the image at its native pixel size.
function M.show(path)
  local cap = M.capability()
  if not cap.supported then
    vim.notify("Image display unavailable: " .. cap.reason, vim.log.levels.WARN)
    return
  end

  -- No argument: use the filename under the cursor.
  if not path or vim.trim(path) == "" then
    path = vim.fn.expand("<cfile>")
  end
  path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  local stat = vim.uv.fs_stat(path)
  if not stat then
    vim.notify("not a file: " .. tostring(path), vim.log.levels.WARN)
    return
  end
  if stat.type ~= "file" then
    vim.notify("not a regular file: " .. tostring(path), vim.log.levels.WARN)
    return
  end
  if stat.size > MAX_IMAGE_BYTES then
    vim.notify("image is >12MiB; refusing to inline a giant file", vim.log.levels.WARN)
    return
  end

  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    vim.notify("cannot open " .. tostring(path), vim.log.levels.WARN)
    return
  end
  local sig = vim.uv.fs_read(fd, #PNG_SIGNATURE, 0)
  if sig ~= PNG_SIGNATURE then
    vim.uv.fs_close(fd)
    vim.notify(
      ("not a valid PNG (signature mismatch): %s"):format(path),
      vim.log.levels.WARN
    )
    return
  end
  local rest = vim.uv.fs_read(fd, stat.size - #PNG_SIGNATURE, #PNG_SIGNATURE)
  vim.uv.fs_close(fd)
  if not rest then
    vim.notify("could not read image data from " .. tostring(path), vim.log.levels.WARN)
    return
  end

  local pos = image_pos()
  local ok_set, placed = pcall(vim.ui.img.set, (sig or "") .. rest,
    { row = pos.row, col = pos.col, zindex = 10 })
  if not ok_set or type(placed) ~= "number" then
    vim.notify(("vim.ui.img.set failed: %s"):format(tostring(placed)), vim.log.levels.WARN)
    return
  end
  M._last = placed
end

---`:ImageClear` — remove the image shown by the last :ImageShow. The id is
---explicit because upstream `del()` requires one (`del(math.huge)` wipes all
---displayed images, which would clobber images created by other Lua code).
function M.clear()
  local cap = M.capability()
  if not cap.supported then
    vim.notify("Image display unavailable: " .. cap.reason, vim.log.levels.WARN)
    return
  end
  if M._last == nil then
    vim.notify("no image currently displayed", vim.log.levels.INFO)
    return
  end
  local ok_del, found = pcall(vim.ui.img.del, M._last)
  if not ok_del then
    vim.notify(("vim.ui.img.del failed: %s"):format(tostring(found)), vim.log.levels.WARN)
    return
  end
  M._last = nil
  if not found then
    -- The id was already gone upstream; nothing was left in the terminal.
    vim.notify("image was already gone", vim.log.levels.INFO)
  end
end

function M.setup()
  vim.api.nvim_create_user_command("ImageShow", function(opts)
    M.show(opts.args)
  end, { nargs = "?", complete = "file", desc = "Show image via vim.ui.img (0.13+)" })
  vim.api.nvim_create_user_command("ImageClear", function()
    M.clear()
  end, { desc = "Clear displayed image" })
end

return M
