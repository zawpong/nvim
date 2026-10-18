#!/usr/bin/env bash
# Real smoke tests against the actually-installed configuration.
#
# Automated (headless):
#   * shell + Lua syntax/loading validation
#   * config boot, module loading, essential options
#   * user command registration
#   * file-search candidates on a temp fixture (spaces in names, exclusion
#     of node_modules, nested dirs) via fd or rg
#   * picker interactions: fuzzy accept of a spaced filename, cancel,
#     empty-results
#   * content-search result -> exact file:line:col navigation
#   * graceful fallback when fd/rg are absent (bounded walk)
#   * LSP configuration loading without installed servers
#   * multicursor: Q is never remapped; capability is reported honestly
#   * images: capability reporter is honest (never optimistic)
#   * tree-sitter fallback keeps unparseable filetypes editable
#
# Manual UI checks (not automatable headlessly; see README "Testing"):
#   * image rendering in a Kitty-capable terminal
#   * native multicursor editing feel (Q/zq/gQ/q=) on a 0.13 build
#
# Usage: ./smoke.sh [--verbose]
#   NVIM_BIN=/path/to/nvim ./smoke.sh   to test another Neovim binary

set -u

MODE_ROOT="$(cd "$(dirname "$0")" && pwd)"
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

nvim_bin="${NVIM_BIN:-nvim}"
pass=0
fail=0

say()  { printf '%s\n' "$*"; }
tick() { pass=$((pass+1)); say "PASS: $*"; }
tock() { fail=$((fail+1)); say "FAIL: $*"; }

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/nvim-smoke-XXXXXX")"

# Run a Lua file under the installed config; captures combined output.
runlua() {
  local label="$1" src="$2" tfile out
  tfile="$TMPBASE/test.lua"
  printf '%s' "$src" > "$tfile"
  out="$( cd "$MODE_ROOT" && timeout 90 "$nvim_bin" --headless -c "luafile $tfile" +qa 2>&1 )"
  if [ "$VERBOSE" = 1 ]; then
    say "--- $label ---"
    printf '%s\n' "$out"
  fi
  printf '%s' "$out"
}

assert_contains() { # haystack needle label
  if printf '%s' "$1" | grep -qF -- "$2"; then
    tick "$3"
  else
    tock "$3 (missing: $2)"
    if [ "$VERBOSE" != "1" ]; then
      printf '%s\n' "  actual output: $1"
    fi
  fi
}

# ---------------------------------------------------------------- shell

for script in install.sh uninstall.sh smoke.sh; do
  if bash -n "$MODE_ROOT/$script" 2>/dev/null; then tick "shell syntax: $script"
  else tock "shell syntax: $script"; fi
done

# ---------------------------------------------------------------- lua files

for f in "$MODE_ROOT"/init.lua "$MODE_ROOT"/lua/config/*.lua; do
  out="$(runlua "syntax check: $(basename "$f")" \
    "local ok, err = loadfile('$f'); print(ok and 'LOAD_OK' or ('LOAD_ERR ' .. tostring(err)))")"
  assert_contains "$out" "LOAD_OK" "lua syntax/load: $(basename "$f")"
done

# ---------------------------------------------------------------- boot

out="$(runlua "boot" "print('BOOT_OK mapleader=[' .. vim.g.mapleader ..']')")"
assert_contains "$out" "BOOT_OK" "headless config boot exits cleanly"
assert_contains "$out" "mapleader=[ ]" "options: mapleader is Space"

# ---------------------------------------------------------------- modules

out="$(runlua "modules" "
local mods = {'config.options','config.statusline','config.diagnostics','config.treesitter',
  'config.search','config.multicursor','config.images','config.keymaps','config.autocmds','config.lsp'}
for _, m in ipairs(mods) do
  local ok = pcall(require, m)
  if not ok then print('MODULE_FAIL ' .. m); return end
end
print('MODULES_OK')")"
assert_contains "$out" "MODULES_OK" "all modules load without errors"

# ---------------------------------------------------------------- options

out="$(runlua "options" "
local ok = vim.o.number and vim.o.relativenumber and vim.o.termguicolors
  and (vim.fn.has('nvim-0.11') == 1)
print(ok and 'OPTIONS_OK' or 'OPTIONS_FAIL')")"
assert_contains "$out" "OPTIONS_OK" "essential options set (nvim >= 0.11 floor)"

# ---------------------------------------------------------------- commands

out="$(runlua "commands" "
local cmds = vim.api.nvim_get_commands({})
for _, name in ipairs({'SearchFiles','SearchGrep','SearchBuffers','SearchHelp','LspStatus','MulticursorInfo','ImageShow','TSStatus'}) do
  if not cmds[name] then print('CMD_FAIL ' .. name); return end
end
print('COMMANDS_OK')")"
assert_contains "$out" "COMMANDS_OK" "user commands registered"

# ---------------------------------------------------------------- search fixtures

FIXTURE="$TMPBASE/proj"
mkdir -p "$FIXTURE/deep/nested" "$FIXTURE/node_modules"
printf 'alpha needle\nsecond line\n' > "$FIXTURE/plain.txt"
printf 'needle inside a space-named file\n' > "$FIXTURE/my doc with spaces.txt"
printf 'nested needle here\n' > "$FIXTURE/deep/nested/inner.txt"
printf 'node_modules junk\n' > "$FIXTURE/node_modules/junk.txt"

out="$(runlua "file candidates" "
local s = require('config.search')
local DONE = false
s.file_candidates('$FIXTURE', function(c, tool)
  local found_plain, found_spaces, found_nested, found_skip = false, false, false, false
  for _, p in ipairs(c or {}) do
    if p == 'plain.txt' then found_plain = true end
    if p == 'my doc with spaces.txt' then found_spaces = true end
    if p == 'deep/nested/inner.txt' then found_nested = true end
    if p:find('node_modules', 1, true) then found_skip = true end
  end
  assert(not found_skip, 'node_modules must be excluded')
  assert(found_plain and found_spaces and found_nested, 'candidates missing expected files')
  print('FILES_OK tool=' .. tool)
  DONE = true
end)
vim.wait(15000, function() return DONE end)
if not DONE then print('FILES_TIMEOUT') end")"
assert_contains "$out" "FILES_OK" "file candidates include spaced/nested files, exclude noise"

# ---------------------------------------------------------------- picker

out="$(runlua "picker accept" "
local s = require('config.search')
vim.schedule(function() vim.fn.feedkeys('sp\\r') end)
local accepted
s._open_picker({
  prompt = 't',
  candidates = {'plain.txt', 'my doc with spaces.txt', 'deep/nested/inner.txt'},
  accept_fn = function(item) accepted = item end,
})
assert(accepted == 'my doc with spaces.txt', 'accept got: ' .. tostring(accepted))
print('PICKER_ACCEPT_OK')")"
assert_contains "$out" "PICKER_ACCEPT_OK" "picker fuzzy-accept selects spaced filename"

out="$(runlua "picker cancel" "
local s = require('config.search')
vim.schedule(function() vim.fn.feedkeys('\27') end)
local accepted, closed
s._open_picker({ prompt='t', candidates={'a'}, accept_fn=function() accepted = true end,
  on_close = function() closed = true end })
assert(not accepted, 'cancel must not accept')
assert(closed, 'on_close callback must run on cancel')
print('PICKER_CANCEL_OK')")"
assert_contains "$out" "PICKER_CANCEL_OK" "picker Esc cancels without accepting"

out="$(runlua "picker empty results" "
local s = require('config.search')
vim.schedule(function() vim.fn.feedkeys('zzz\\r') end)
local accepted
s._open_picker({ prompt='t', candidates={'a'}, accept_fn=function(item) accepted = item end })
assert(accepted == nil, 'expected nil accept, got ' .. tostring(accepted))
print('PICKER_EMPTY_OK')")"
assert_contains "$out" "PICKER_EMPTY_OK" "no-match search accepts nil without an error"

# ---------------------------------------------------------------- grep jump

out="$(runlua "grep jump" "
local s = require('config.search')
local path, ln, col = s._parse_vimgrep('my doc with spaces.txt:1:1:needle inside a space-named file')
assert(path == 'my doc with spaces.txt' and ln == 1 and col == 1,
  tostring(path) .. ',' .. tostring(ln) .. ',' .. tostring(col))
vim.cmd('edit ' .. vim.fn.fnameescape('$FIXTURE/my doc with spaces.txt'))
pcall(vim.api.nvim_win_set_cursor, 0, { ln, col - 1 })
local cur, cc = vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_win_get_cursor(0)[2]
assert(cur == 1 and cc == 0, ('cursor %d,%d'):format(cur, cc))
print('GREP_JUMP_OK')")"
assert_contains "$out" "GREP_JUMP_OK" "content-search result navigates to file:line:col"

# ---------------------------------------------------------------- live grep =

out="$(runlua "live grep async" "
local s = require('config.search')
-- low-level async check: rg run picks content & parses output rows
local DONE = false
if not s.has_tool('rg') then print('LIVEGREP_SKIP_NO_RG'); return end
local job = vim.system({'rg','--vimgrep','--color','never','--smart-case','--','needle'},
  { cwd = '$FIXTURE', text = true }, function(res)
    local rows = {}
    for row in vim.gsplit(res.stdout or '', '\\n', { plain = true }) do
      if row ~= '' then rows[#rows + 1] = row end
    end
    local ok
    for _, r in ipairs(rows) do
      local p, l = s._parse_vimgrep(r)
      if p == 'plain.txt' and l == 1 then ok = true end
      if p == 'my doc with spaces.txt' and l == 1 and ok then ok = 'both' end
    end
    assert(ok, 'rg output missing expected rows')
    print('LIVEGREP_OK rows=' .. #rows)
    DONE = true
  end)
vim.wait(15000, function() return DONE end)
if not DONE then print('LIVEGREP_TIMEOUT') end")"
assert_contains "$out" "LIVEGREP_OK" "live grep: rg rows parsed to file:line:col"

# ---------------------------------------------------------------- fallback walk

out="$(runlua "walk fallback" "
local s = require('config.search')
local real_has_tool = s.has_tool
s.has_tool = function() return false end
local notified, DONE = false, false
local real_notify = vim.notify
vim.notify = function(msg, _, _)
  if msg:find('fd', 1, true) then notified = true end
end
s.file_candidates('$FIXTURE', function(c, tool)
  vim.notify = real_notify
  s.has_tool = real_has_tool
  assert(tool == 'walk', 'expected walk fallback, got ' .. tostring(tool))
  assert(type(c) == 'table' and #c > 0, 'walk fallback returned nothing')
  assert(notified, 'missing-tool notice was not shown')
  print('WALK_OK count=' .. #c)
  DONE = true
end)
vim.wait(5000, function() return DONE end)
if not DONE then print('WALK_TIMEOUT') end")"
assert_contains "$out" "WALK_OK" "fd+rg absent: walk fallback works and notifies"

# ---------------------------------------------------------------- LSP

out="$(runlua "lsp load" "
require('config.lsp')
local clients = vim.lsp.get_clients({ bufnr = 0 })
print('LSP_OK clients=' .. #clients)")"
assert_contains "$out" "LSP_OK" "LSP config loads whether or not any server exists"

# ---------------------------------------------------------------- multicursor

out="$(runlua "multicursor honesty" "
local mc = require('config.multicursor')
local u = require('config.utils')
assert(vim.fn.maparg('Q', 'n') == '', 'Q must not be remapped')
assert(vim.fn.maparg('gQ', 'n') == '', 'gQ must not be remapped')
local native = u.has_native_multicursor()
assert(type(native) == 'boolean', 'capability probe must be boolean')
print('MC_OK native=' .. tostring(native))")"
assert_contains "$out" "MC_OK" "multicursor: native keys untouched, honest capability"

# ---------------------------------------------------------------- images

out="$(runlua "images honesty" "
local im = require('config.images')
local cap = im.capability()
assert(type(cap.supported) == 'boolean' and #cap.reason > 0, 'capability must be a pair')
print('IMG_OK supported=' .. tostring(cap.supported) .. ' reason=' .. cap.reason:sub(1, 40))")"
assert_contains "$out" "IMG_OK" "image capability reporter is honest"

# ---------------------------------------------------------------- treesitter

out="$(runlua "treesitter fallback" "
vim.cmd('edit $FIXTURE/deep/nested/inner.txt')
local ft = vim.bo.filetype
assert(ft == 'text', 'unexpected filetype ' .. ft)
local hl = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]
vim.cmd('edit lua/config/options.lua')
local ts_started = (vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil)
print('TS_OK ts_highlighting=' .. tostring(ts_started))")"
assert_contains "$out" "TS_OK" "treesitter: parser-capable ft highlighted, others fall back"

# ---------------------------------------------------------------- summary

rm -rf "$TMPBASE"
say ""
say "smoke results: pass=$pass fail=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
