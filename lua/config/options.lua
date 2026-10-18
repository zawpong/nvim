-- Core editor options and persistent state directories.

local opt = vim.opt

-- Leader keys.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Optional global toggles.
vim.g.format_on_save = false

-- Line numbers.
opt.number = true
opt.relativenumber = true

-- Cursor and scrolling.
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.sidescrolloff = 8

-- Wrapping: off for source code by default.
opt.wrap = false
opt.linebreak = true

-- Indentation defaults (filetype overrides live in autocmds).
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.softtabstop = 4
opt.smartindent = true
opt.autoindent = true

-- Search.
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

-- Splits.
opt.splitbelow = true
opt.splitright = true

-- Mouse as a convenience, not a requirement.
opt.mouse = "a"

-- Completion.
opt.completeopt = "menu,menuone,noselect,popup"
opt.pumheight = 12

-- Command-line completion.
opt.wildmenu = true
opt.wildmode = "longest:full,full"

-- Timing.
opt.updatetime = 300
opt.timeoutlen = 400

-- Persistent undo, swap and backup directories (in Nvim's state dir, so they
-- never pollute the working tree).
local state = vim.fn.stdpath("state")
local backup_dir = state .. "/backup"
local swap_dir = state .. "/swap"
local undo_dir = state .. "/undo"
for _, dir in ipairs({ backup_dir, swap_dir, undo_dir }) do
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

opt.backup = false
opt.writebackup = true
opt.swapfile = true
opt.undofile = true
opt.backupdir = backup_dir .. "//"
opt.directory = swap_dir .. "//"
opt.undodir = undo_dir .. "//"

-- UI.
opt.termguicolors = true
opt.laststatus = 2
opt.showmode = false
opt.cmdheight = 1

-- Floating window border: the 'winborder' option exists in 0.12+.
pcall(function()
  opt.winborder = "rounded"
end)

-- Clipboard: 'unnamedplus' shares the system clipboard when a provider
-- (wl-clipboard on Wayland, pbcopy on macOS, OSC 52-capable terminal) exists.
-- Capability detection rather than OS-name guessing: if no provider is found
-- (common in SSH/TTY), the option is left unset so internal registers work.
local clipboard_provider = false
for _, cmd in ipairs({
  "wl-copy", "wl-paste", -- Wayland
  "pbcopy", "pbpaste", -- macOS
  "xclip", "xsel", -- X11
}) do
  if vim.fn.executable(cmd) == 1 then
    clipboard_provider = true
    break
  end
end
if clipboard_provider or vim.env.SSH_TTY or os.getenv("DISPLAY") or os.getenv("WAYLAND_DISPLAY") then
  opt.clipboard = "unnamedplus"
end

-- netrw (native file explorer).
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.g.netrw_winsize = 25
vim.g.netrw_keepdir = 1

-- Colorscheme: native, dark, low-distraction.
vim.cmd.colorscheme("habamax")
