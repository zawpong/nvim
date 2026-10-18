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

-- Persistent undo, swap and backup directories.
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
opt.signcolumn = "yes"

-- Clipboard: requires a provider such as wl-clipboard on Wayland.
opt.clipboard = "unnamedplus"

-- netrw (native file explorer).
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.g.netrw_winsize = 25
vim.g.netrw_keepdir = 1

-- Colorscheme: native, dark, low-distraction.
vim.cmd.colorscheme("habamax")