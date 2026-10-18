-- Native image support (Neovim 0.13+, EXPERIMENTAL upstream).
--
-- Verified behavior (checked against Neovim master docs and the
-- implementation, not blog posts):
--   * vim.ui.img renders images via the Kitty graphics protocol.
--   * Pixels must be embedded in the escape stream (`t=d`, base64 bytes,
--     4 KB chunks). File-path transmission (`t=f`) is NOT implemented, so the
--     image is read into memory before being shown. Web URLs are NOT
--     fetched natively.
--   * Running inside tmux without DCS passthrough is unsupported upstream;
--     this module treats tmux as "cannot render".
--   * The API was merged as EXPERIMENTAL: it may change until 0.13 drops
--     that marker. This module guards every call with pcall and reports
--     capability honestly instead of guessing.
--   * :checkhealth vim.health covers the health check upstream.
--   * There is no plugin, no external converter, and no custom renderer
--     here. When capability is missing, commands say so and do nothing.

local u = require("config.utils")

local M = {}

---Best-effort capability description; honest, never optimistic.
---@return { supported = boolean, reason = string }
function M.capability()
  if vim.fn.has("nvim-0.13") ~= 1 and not pcall(require, "vim.ui.img") then
    return {
      supported = false,
      reason = "vim.ui.img needs Neovim 0.13 or newer (currently nightly-only, experimental)",
    }
  end
  if not vim.ui or not vim.ui.img then
    return { supported = false, reason = "vim.ui.img is not present in this build" }
  end
  if vim.env.TMUX and not u.has("kitty") then
    return { supported = false, reason = "inside tmux: the kitty graphics protocol needs passthrough, which vim.ui.img does not implement" }
  end
  local term = vim.env.TERM or ""
  local program = vim.env.TERM_PROGRAM or ""
  local gui = vim.env.GHOSTTY_RESOURCES_ID ~= nil -- ghostty ships support
  local kitty_program = program == "kitty" or (term == "xterm-kitty" and true) or gui
      or vim.env.NVIM_IMAGE_CAPABILITY == "kitty" -- explicit escape hatch
  if not kitty_program then
    return {
      supported = false,
      reason = ([[terminal (TERM=%s, TERM_PROGRAM=%s) did not declare graphics-protocol support.
If it really is Kitty-like, set NVIM_IMAGE_CAPABILITY=kitty to try anyway.]]):format(
        term,
        program ~= "" and program or "unset"
      ),
    }
  end
  return { supported = true, reason = "kitty graphics protocol available via vim.ui.img" }
end

---`:ImageShow {path}` — display a local PNG (the only format the kitty
---graphics protocol requires hosts to handle; other formats pass through to
---the host renderer if the terminal supports them). No downloads.
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
  if stat.size > 12 * 1024 * 1024 then
    vim.notify("image is >12MiB; refusing to inline a giant file", vim.log.levels.WARN)
    return
  end

  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    vim.notify("cannot open " .. tostring(path), vim.log.levels.WARN)
    return
  end
  local data = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  if not data then
    vim.notify("could not read image", vim.log.levels.WARN)
    return
  end
  local set_ok, set_err = pcall(vim.ui.img.set, data)
  if not set_ok then
    vim.notify("vim.ui.img.set failed: " .. tostring(set_err), vim.log.levels.WARN)
  end
end

---`:ImageClear` — remove whatever the API last displayed.
function M.clear()
  local cap = M.capability()
  if not cap.supported then
    vim.notify("Image display unavailable: " .. cap.reason, vim.log.levels.WARN)
    return
  end
  pcall(vim.ui.img.del)
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
