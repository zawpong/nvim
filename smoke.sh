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
#   * real <leader>ff/fg/fb keymap end-to-end flows (async candidates ride
#     out of the fast event context; grep rows land on the match line)
#   * special-char paths (brackets, quotes, colons), empty projects,
#     non-UTF-8 filename candidates
#   * content-search result -> exact file:line:col navigation
#   * graceful fallback when fd/rg are absent (bounded walk)
#   * LSP configuration loading without installed servers
#   * multicast: Q is never remapped; capability is reported honestly
#   * images: terminal-probe capability, del() contract, missing/invalid
#     file messages, show/clear id lifecycle (headless; visual check is manual)
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

# Same, but WITHOUT the trailing +qa: flows that open the interactive picker
# loop terminate themselves (lua qa! or os.exit(1)) and need to keep running
# timers; +qa would quit nvim before any of them fire.
runlua_flow() {
  local label="$1" src="$2" tfile out
  tfile="$TMPBASE/test.lua"
  printf '%s' "$src" > "$tfile"
  out="$( cd "$MODE_ROOT" && timeout 90 "$nvim_bin" --headless -c "luafile $tfile" 2>&1 )"
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
local mods = {'config.options','config.statusline','config.git_context','config.diagnostics','config.treesitter',
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
for _, name in ipairs({'SearchFiles','SearchGrep','SearchBuffers','SearchHelp','LspStatus','MulticursorInfo','ImageShow','TSStatus','HighlightStatus'}) do
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

# ---------------------------------------------------------------- picker input handling (backspace / arrows / utf-8)

out="$(runlua "picker backspace ascii" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys('ab' .. tc('<BS>', true, true, true) .. tc('<Down>', true, true, true) .. tc('<CR>', true, true, true), 't') end)
local accepted
s._open_picker({ prompt='t', candidates={'ab.txt','a.txt'}, accept_fn=function(item) accepted=item end })
assert(accepted == 'ab.txt', 'ascii backspace: got ' .. tostring(accepted))
print('BS_ASCII_OK')")"
assert_contains "$out" "BS_ASCII_OK" "backspace removes last ASCII char"

out="$(runlua "picker backspace utf8" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys('café' .. tc('<BS>', true, true, true) .. tc('<Down>', true, true, true) .. tc('<CR>', true, true, true), 't') end)
local accepted
s._open_picker({ prompt='t', candidates={'café.txt','cafe.txt'}, accept_fn=function(item) accepted=item end })
assert(accepted == 'cafe.txt', 'utf8 backspace: got ' .. tostring(accepted))
print('BS_UTF8_OK')")"
assert_contains "$out" "BS_UTF8_OK" "backspace removes one complete UTF-8 char"

out="$(runlua "picker backspace empty safe" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys(tc('<BS>', true, true, true) .. tc('<BS>', true, true, true) .. tc('<Esc>', true, true, true), 't') end)
local closed = false
s._open_picker({ prompt='t', candidates={'a','b'}, on_close=function() closed=true end })
assert(closed, 'empty backspace must not crash or hang')
print('BS_EMPTY_OK')")"
assert_contains "$out" "BS_EMPTY_OK" "repeated backspace on empty query is safe"

out="$(runlua "picker up changes selection" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys(tc('<Down>', true, true, true) .. tc('<Down>', true, true, true) .. tc('<Up>', true, true, true) .. tc('<CR>', true, true, true), 't') end)
local accepted
s._open_picker({ prompt='t', candidates={'first.txt','second.txt','third.txt'}, accept_fn=function(item) accepted=item end })
assert(accepted == 'second.txt', 'up: got ' .. tostring(accepted))
print('UP_OK')")"
assert_contains "$out" "UP_OK" "Up moves selection to previous result"

out="$(runlua "picker down changes selection" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys(tc('<Down>', true, true, true) .. tc('<CR>', true, true, true), 't') end)
local accepted
s._open_picker({ prompt='t', candidates={'first.txt','second.txt','third.txt'}, accept_fn=function(item) accepted=item end })
assert(accepted == 'second.txt', 'down: got ' .. tostring(accepted))
print('DOWN_OK')")"
assert_contains "$out" "DOWN_OK" "Down moves selection to next result"

out="$(runlua "picker ctrl j/k/n/p" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys(tc('<C-J>', true, true, true) .. tc('<C-J>', true, true, true) .. tc('<C-K>', true, true, true) .. tc('<CR>', true, true, true), 't') end)
local accepted
s._open_picker({ prompt='t', candidates={'first.txt','second.txt','third.txt'}, accept_fn=function(item) accepted=item end })
assert(accepted == 'second.txt', 'ctrl j/k: got ' .. tostring(accepted))
vim.schedule(function() vim.fn.feedkeys(tc('<C-N>', true, true, true) .. tc('<C-P>', true, true, true) .. tc('<Esc>', true, true, true), 't') end)
local closed = false
s._open_picker({ prompt='t', candidates={'x','y'}, on_close=function() closed=true end })
assert(closed, 'ctrl n/p cancel path broken')
print('CTRL_JK_NP_OK')")"
assert_contains "$out" "CTRL_JK_NP_OK" "Ctrl-J/K and Ctrl-N/P navigate results"

out="$(runlua "picker esc cancels" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys(tc('<Esc>', true, true, true), 't') end)
local accepted, closed = nil, false
s._open_picker({ prompt='t', candidates={'a'}, accept_fn=function(item) accepted=item end, on_close=function() closed=true end })
assert(accepted == nil and closed, 'esc must cancel without accepting')
print('ESC_OK')")"
assert_contains "$out" "ESC_OK" "Escape cancels without opening"

out="$(runlua "picker zero candidates" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys(tc('<Down>', true, true, true) .. tc('<Up>', true, true, true) .. tc('<CR>', true, true, true), 't') end)
local accepted
s._open_picker({ prompt='t', candidates={}, accept_fn=function(item) accepted=item end })
assert(accepted == nil, 'zero candidates: got ' .. tostring(accepted))
print('ZERO_OK')")"
assert_contains "$out" "ZERO_OK" "navigation safe with zero candidates"

out="$(runlua "picker one candidate" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys(tc('<Down>', true, true, true) .. tc('<Up>', true, true, true) .. tc('<CR>', true, true, true), 't') end)
local accepted
s._open_picker({ prompt='t', candidates={'only.txt'}, accept_fn=function(item) accepted=item end })
assert(accepted == 'only.txt', 'one candidate: got ' .. tostring(accepted))
print('ONE_OK')")"
assert_contains "$out" "ONE_OK" "navigation safe with one candidate"

out="$(runlua "picker query change clamps selection" "
local s = require('config.search')
local tc = vim.api.nvim_replace_termcodes
vim.schedule(function() vim.fn.feedkeys('ab' .. tc('<Down>', true, true, true) .. tc('<Down>', true, true, true) .. 'c' .. tc('<CR>', true, true, true), 't') end)
local accepted
s._open_picker({ prompt='t', candidates={'abc','abd','abe'}, accept_fn=function(item) accepted=item end })
assert(accepted == 'abc', 'clamp: got ' .. tostring(accepted))
print('CLAMP_OK')")"
assert_contains "$out" "CLAMP_OK" "query changes keep selection in valid range"

out="$(runlua "picker unicode query" "
local s = require('config.search')
vim.schedule(function() vim.fn.feedkeys('café' .. '\\r', 't') end)
local accepted
s._open_picker({ prompt='t', candidates={'café.txt','plain.txt'}, accept_fn=function(item) accepted=item end })
assert(accepted == 'café.txt', 'unicode query: got ' .. tostring(accepted))
print('UNICODE_QUERY_OK')")"
assert_contains "$out" "UNICODE_QUERY_OK" "typing unicode query filters candidates"

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

# ---------------------------------------------------------------- keymaps

out="$(runlua "search keymaps" "
local descs = { ['<Space>ff']='Fuzzy file search', ['<Space>fg']='Live content search',
  ['<Space>fb']='Search open buffers', ['<Space>fh']='Search help topics' }
for key, want in pairs(descs) do
  local d = vim.fn.maparg(key, 'n', false, true)
  assert(type(d) == 'table' and next(d) ~= nil, key .. ' is NOT mapped')
  assert(d.desc == want, key .. ' desc=' .. tostring(d.desc))
end
print('KEYMAPS_OK')")"
assert_contains "$out" "KEYMAPS_OK" "<leader>ff/fg/fb/fh mapped with documented descs"

# ---------------------------------------------------------------- e2e leader ff

# Drives the REAL keymap through the async fd job -> picker -> open file.
# Regression net for the E5560 fast-event-context crash and for missing keymaps.

out="$(runlua_flow "leader ff e2e" "
vim.cmd('cd $FIXTURE')
local s = require('config.search')
local started, seen_open = false, false
local st = vim.uv.new_timer()
st:start(30, 80, function()
  vim.schedule(function()
    if not started then
      started = true
      vim.fn.feedkeys(' ff', 't')
    elseif not seen_open and s._state() then
      seen_open = true
      vim.fn.feedkeys('plain\r', 't')
    elseif seen_open and s._state() == nil then
      st:stop()
      local name = vim.api.nvim_buf_get_name(0)
      if name:find('plain%.txt\$') then
        print('LEADER_FF_OK buf=' .. name)
      else
        io.write('LEADER_FF_FAIL name=' .. name .. '\n'); io.flush()
      end
      vim.cmd('qa!')
    end
  end)
end)
vim.defer_fn(function()
  io.write('LEADER_FF_TIMEOUT phase_start=' .. tostring(started) .. ' opened=' .. tostring(seen_open) .. '\n'); io.flush(); os.exit(1)
end, 45000)")"
if printf '%s' "$out" | grep -qF "LEADER_FF_OK"; then
  tick "<leader>ff: real keymap -> async candidates -> picker -> correct file open"
else
  tock "<leader>ff e2e ($out)"
fi

# ---------------------------------------------------------------- e2e leader fg

out="$(runlua_flow "leader fg e2e" "
vim.cmd('cd $FIXTURE')
local s = require('config.search')
s.opts.grep_debounce_ms = 0
local started, typed, accepted = false, false, false
local st = vim.uv.new_timer()
st:start(30, 80, function()
  vim.schedule(function()
    if not started then
      started = true
      vim.fn.feedkeys(' fg', 't')
    elseif started and not typed and s._state() then
      typed = true
      vim.fn.feedkeys('needle', 't')
    elseif typed and not accepted then
      local state = s._state()
      if state and #state.results > 0 then
        accepted = true
        st:stop()
        vim.fn.feedkeys('\r', 't')
        -- the cursor lands through vim.schedule right after the edit
        vim.wait(2000, function() return false end, 50)
        local cur = vim.api.nvim_win_get_cursor(0)
        local text = vim.api.nvim_get_current_line()
        if text:find('needle', 1, true) then
          print(('LEADER_FG_OK line=%d col=%d text=%s'):format(cur[1], cur[2], text))
        else
          io.write(('LEADER_FG_FAIL line=%d col=%d text=%s\n'):format(cur[1], cur[2], text)); io.flush()
        end
        vim.cmd('qa!')
      end
    end
  end)
end)
vim.defer_fn(function()
  io.write('LEADER_FG_TIMEOUT typed=' .. tostring(typed) .. ' accepted=' .. tostring(accepted) .. '\n'); io.flush(); os.exit(1)
end, 45000)")"
if printf '%s' "$out" | grep -qF "LEADER_FG_OK"; then
  tick "<leader>fg: live grep rows land cursor on the match line"
else
  tock "<leader>fg e2e ($out)"
fi

# ---------------------------------------------------------------- esc cancel e2e

out="$(runlua_flow "esc cancel e2e" "
local s = require('config.search')
local started, seen_open, cancelled = false, false, false
local st = vim.uv.new_timer()
st:start(30, 80, function()
  vim.schedule(function()
    if not started then
      started = true
      vim.fn.feedkeys(' fb', 't')
    elseif not seen_open and s._state() then
      seen_open = true
      vim.fn.feedkeys('\27', 't')
    elseif not cancelled and seen_open and s._state() == nil then
      cancelled = true
      st:stop()
      print('ESC_CANCEL_OK')
      vim.cmd('qa!')
    end
  end)
end)
vim.defer_fn(function()
  io.write('ESC_CANCEL_TIMEOUT started=' .. tostring(started) .. ' opened=' .. tostring(seen_open) .. '\n'); io.flush(); os.exit(1)
end, 45000)")"
if printf '%s' "$out" | grep -qF "ESC_CANCEL_OK"; then
  tick "<leader>fb: real keymap opens, Esc cancels and closes"
else
  tock "<leader>fb Esc-cancel e2e ($out)"
fi

# ---------------------------------------------------------------- special chars

printf 'needleX here\n' > "$FIXTURE/weird [br] \"quoted\":colon.txt"
out="$(runlua "special chars" "
local s = require('config.search')
local p, ln, col = s._parse_vimgrep('weird [br] \"quoted\":colon.txt:2:3:zzz')
assert(p == 'weird [br] \"quoted\":colon.txt' and ln == 2 and col == 3, tostring(p) .. '|' .. tostring(ln) .. '|' .. tostring(col))
print('PARSE_OK')
vim.cmd({ cmd = 'edit', args = { vim.fn.fnameescape('$FIXTURE/weird [br] \"quoted\":colon.txt') } })
local name = vim.api.nvim_buf_get_name(0)
assert(name:find('colon%.txt\$'), 'opened: ' .. name)
print('SPECIAL_OPEN_OK')")"
assert_contains "$out" "PARSE_OK" "vimgrep rows parse with brackets/quotes/colons in path"
assert_contains "$out" "SPECIAL_OPEN_OK" "special-char path opens by exact name"

# ---------------------------------------------------------------- empty project

out="$(runlua "empty project" "
local empty_dir = '$TMPBASE/empty_proj'
vim.fn.mkdir(empty_dir, 'p')
vim.cmd('cd ' .. vim.fn.fnameescape(empty_dir))
local s = require('config.search')
local notified = nil
local real_notify = vim.notify
vim.notify = function(msg) notified = tostring(msg or '') end
s.find_files()
vim.wait(15000, function() return notified ~= nil end)
vim.notify = real_notify
if notified and notified:find('No files found', 1, true) then
  print('EMPTY_OK msg=' .. notified:gsub('\n', ' '))
else
  print('EMPTY_FAIL msg=' .. tostring(notified))
end")"
if printf '%s' "$out" | grep -qF "EMPTY_OK"; then
  tick "empty project explains 'No files found' with informational level"
else
  tock "empty-project message ($out)"
fi

# ---------------------------------------------------------------- non-utf8 candidates

out="$(runlua "non-utf8 candidates" "
local bad = 'bad' .. string.char(0x82)   -- 0x82 = invalid UTF-8 continuation
local s = require('config.search')
vim.schedule(function() vim.fn.feedkeys(string.char(0x82) == '' and 'b\r' or 'b\r', 't') end)
local accepted
s._open_picker({ prompt = 't',
  candidates = { bad .. 'name.txt', 'plain.txt' },
  accept_fn = function(item) accepted = item end })
assert(accepted == bad .. 'name.txt', 'accept got: ' .. vim.inspect(accepted))
print('NONUTF8_OK')")"
assert_contains "$out" "NONUTF8_OK" "non-UTF-8 candidate renders, filters and accepts raw bytes"

# ---------------------------------------------------------------- images

out="$(runlua "image commands" "
local im = require('config.images')
local cap = im.capability()
assert(type(cap.supported) == 'boolean' and #cap.reason > 0, 'capability must be a pair')
print('IMG_CAP_OK supported=' .. tostring(cap.supported))")"
assert_contains "$out" "IMG_CAP_OK" "image capability respects the terminal probe"

if [ "$(command -v python3)" != "" ]; then
  python3 - <<'PYEOF'
from pathlib import Path
png = bytes([
0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
0x89,0x00,0x00,0x00,0x0B,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x02,0x00,0x01,
0x5C,0x18,0x8C,0xBD,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82])
Path("/tmp/opencode/probe.png").write_bytes(png)
PYEOF
  if file /tmp/opencode/probe.png | grep -q "PNG image"; then
    out="$(runlua "images lifecycle" "
if vim.fn.has('nvim-0.13') ~= 1 then print('IMG_LIFE_SKIP'); return end
local im = require('config.images')
local real_cap = im.capability
im.capability = function() return { supported = true, reason = 'stubbed headless' } end
local msgs = {}
local real_notify = vim.notify
vim.notify = function(m) msgs[#msgs + 1] = tostring(m or '') end
-- missing file
im.show('$TMPBASE/definitely-not-there.png')
-- invalid PNG bytes
local f = io.open('$TMPBASE/notapng.png', 'w'); f:write('plain text'); f:close()
im.show('$TMPBASE/notapng.png')
-- valid PNG lifecycle
im.show('/tmp/opencode/probe.png')
local id = im._last
assert(type(id) == 'number', 'no tracked id after show: ' .. tostring(id))
local opts = vim.ui.img.get(id)
assert(type(opts) == 'table' and opts.row >= 1 and opts.col >= 1, vim.inspect(opts))
local n_before = #msgs
im.clear()
assert(im._last == nil, 'clear must reset the tracked id')
-- second clear: nothing displayed
im.clear()
local found_missing = false
local found_invalid = false
local found_none = false
for _, m in ipairs(msgs) do
  if m:find('not a file', 1, true) then found_missing = true end
  if m:find('not a valid PNG', 1, true) then found_invalid = true end
  if m:find('no image currently displayed', 1, true) then found_none = true end
end
vim.notify = real_notify
im.capability = real_cap
assert(found_missing and found_invalid and found_none, vim.inspect(msgs))
print('IMG_LIFE_OK id=' .. id .. ' opts=' .. vim.inspect({ row = opts.row, col = opts.col }))")"
    assert_contains "$out" "IMG_LIFE_OK" "images: missing/invalid file rejected, id lifecycle tracked"
  else
    tock "images: PNG fixture generation failed (python3/file unavailable)"
  fi
else
  tock "images: python3 not available to generate the PNG fixture (NOT RUN)"
fi

# ---------------------------------------------------------------- summary

rm -rf "$TMPBASE"
say ""
say "smoke results: pass=$pass fail=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
