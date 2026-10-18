-- Centralized palette and highlight definitions (native, zero plugins).
--
-- One module owns every RGB value and semantic highlight group so the rest of
-- the config stays free of scattered color literals. Reapplied on ColorScheme
-- so a later `:colorscheme` does not wipe the design.

local M = {}

-- Design tokens (dark forest green / charcoal / muted sage).
M.palette = {
  bg = "#101512",
  surface = "#171E19",
  elevated = "#202923",
  separator = "#303B33",
  text = "#E2E9E3",
  secondary = "#A2AEA5",
  muted = "#77847A",
  green = "#8FCBA0",
  strong = "#55B879",
  cyan = "#8BBFC0",
  warn = "#D9B879",
  error = "#E38C8C",
  search = "#365A43",
}

local p = M.palette

local function H(name, spec)
  vim.api.nvim_set_hl(0, name, spec)
end

function M.apply()
  local bg, surface, elevated = p.bg, p.surface, p.elevated
  local sep, text, secondary, muted = p.separator, p.text, p.secondary, p.muted
  local green, strong, cyan = p.green, p.strong, p.cyan
  local warn, err, search = p.warn, p.error, p.search

  -- Base surfaces.
  H("Normal", { fg = text, bg = bg })
  H("NormalNC", { fg = secondary, bg = bg })
  H("NormalFloat", { fg = text, bg = elevated })
  H("FloatBorder", { fg = sep, bg = elevated })
  H("FloatTitle", { fg = green, bg = elevated, bold = true })
  H("FloatFooter", { fg = muted, bg = elevated })

  -- Cursor / selection.
  H("Cursor", { fg = bg, bg = green })
  H("lCursor", { fg = bg, bg = green })
  H("CursorLine", { bg = surface })
  H("CursorLineNr", { fg = green, bg = surface, bold = true })
  H("CursorColumn", { bg = surface })
  H("Visual", { fg = text, bg = search })
  H("VisualNOS", { fg = bg, bg = green })

  -- Line numbers / columns.
  H("LineNr", { fg = muted })
  H("LineNrAbove", { fg = muted })
  H("LineNrBelow", { fg = muted })
  H("SignColumn", { fg = muted, bg = bg })
  H("FoldColumn", { fg = muted, bg = bg })
  H("ColorColumn", { bg = elevated })
  H("Conceal", { fg = muted })
  H("EndOfBuffer", { fg = "#263028" })
  H("Whitespace", { fg = "#263028" })
  H("SpecialKey", { fg = muted })
  H("NonText", { fg = muted })

  -- Search.
  H("Search", { fg = text, bg = search })
  H("CurSearch", { fg = bg, bg = strong, bold = true })
  H("IncSearch", { fg = bg, bg = strong, bold = true })
  H("Substitute", { fg = bg, bg = warn })

  -- Matching / folds.
  H("MatchParen", { fg = strong, bg = elevated, bold = true })
  H("Folded", { fg = secondary, bg = surface })

  -- Window chrome.
  H("WinSeparator", { fg = sep, bg = bg })
  H("VertSplit", { fg = sep, bg = bg })
  H("StatusLine", { fg = text, bg = surface })
  H("StatusLineNC", { fg = muted, bg = bg })
  H("TabLine", { fg = secondary, bg = surface })
  H("TabLineSel", { fg = bg, bg = green, bold = true })
  H("TabLineFill", { fg = muted, bg = bg })
  H("WinBar", { fg = secondary, bg = surface })
  H("WinBarNC", { fg = muted, bg = bg })
  H("TitleBar", { fg = text, bg = surface })
  H("TitleBarNC", { fg = muted, bg = bg })

  -- Popup menu (completion).
  H("Pmenu", { fg = text, bg = elevated })
  H("PmenuSel", { fg = text, bg = search, bold = true })
  H("PmenuSbar", { bg = surface })
  H("PmenuThumb", { bg = sep })
  H("PmenuMatch", { fg = strong, bg = elevated, bold = true })
  H("PmenuMatchSel", { fg = strong, bg = search, bold = true })
  H("PmenuExtra", { fg = muted, bg = elevated })
  H("PmenuExtraSel", { fg = secondary, bg = search })
  H("PmenuKind", { fg = cyan, bg = elevated })
  H("PmenuKindSel", { fg = cyan, bg = search })
  H("WildMenu", { fg = bg, bg = green, bold = true })

  -- Messages.
  H("ErrorMsg", { fg = err, bg = bg, bold = true })
  H("WarningMsg", { fg = warn, bg = bg })
  H("MoreMsg", { fg = green, bg = bg })
  H("Question", { fg = cyan, bg = bg })
  H("ModeMsg", { fg = secondary, bg = bg, bold = true })
  H("Title", { fg = green, bold = true })

  -- Diagnostics.
  H("DiagnosticError", { fg = err })
  H("DiagnosticWarn", { fg = warn })
  H("DiagnosticInfo", { fg = cyan })
  H("DiagnosticHint", { fg = green })
  H("DiagnosticOk", { fg = strong })
  H("DiagnosticSignError", { fg = err, bg = bg })
  H("DiagnosticSignWarn", { fg = warn, bg = bg })
  H("DiagnosticSignInfo", { fg = cyan, bg = bg })
  H("DiagnosticSignHint", { fg = green, bg = bg })
  H("DiagnosticUnderlineError", { undercurl = true, sp = err })
  H("DiagnosticUnderlineWarn", { undercurl = true, sp = warn })
  H("DiagnosticUnderlineInfo", { undercurl = true, sp = cyan })
  H("DiagnosticUnderlineHint", { undercurl = true, sp = green })
  H("DiagnosticVirtualTextError", { fg = err, italic = true })
  H("DiagnosticVirtualTextWarn", { fg = warn, italic = true })
  H("DiagnosticVirtualTextInfo", { fg = cyan, italic = true })
  H("DiagnosticVirtualTextHint", { fg = green, italic = true })

  -- Diff.
  H("DiffAdd", { fg = text, bg = "#1E2E20" })
  H("DiffChange", { fg = text, bg = "#2A2A20" })
  H("DiffDelete", { fg = muted, bg = "#2E1F1F" })
  H("DiffText", { fg = bg, bg = cyan, bold = true })

  -- Syntax (legacy groups).
  H("Comment", { fg = muted, italic = true })
  H("Constant", { fg = warn })
  H("String", { fg = "#9FCFA8" })
  H("Character", { fg = "#9FCFA8" })
  H("Number", { fg = warn })
  H("Boolean", { fg = warn })
  H("Float", { fg = warn })
  H("Identifier", { fg = text })
  H("Function", { fg = cyan })
  H("Statement", { fg = green })
  H("Conditional", { fg = green })
  H("Repeat", { fg = green })
  H("Label", { fg = green })
  H("Operator", { fg = secondary })
  H("Keyword", { fg = green })
  H("Exception", { fg = err })
  H("PreProc", { fg = cyan })
  H("Include", { fg = cyan })
  H("Define", { fg = cyan })
  H("Macro", { fg = cyan })
  H("PreCondit", { fg = cyan })
  H("Type", { fg = strong })
  H("StorageClass", { fg = strong })
  H("Structure", { fg = strong })
  H("Typedef", { fg = strong })
  H("Special", { fg = cyan })
  H("SpecialChar", { fg = cyan })
  H("Tag", { fg = green })
  H("Delimiter", { fg = secondary })
  H("SpecialComment", { fg = muted, italic = true, bold = true })
  H("Debug", { fg = warn })
  H("Underlined", { fg = cyan, underline = true })
  H("Error", { fg = err, bold = true })
  H("Todo", { fg = bg, bg = warn, bold = true })

  -- Treesitter captures.
  local ts = {
    ["@comment"] = { fg = muted, italic = true },
    ["@string"] = { fg = "#9FCFA8" },
    ["@string.escape"] = { fg = cyan },
    ["@character"] = { fg = "#9FCFA8" },
    ["@number"] = { fg = warn },
    ["@boolean"] = { fg = warn },
    ["@float"] = { fg = warn },
    ["@constant"] = { fg = warn },
    ["@constant.builtin"] = { fg = warn, bold = true },
    ["@function"] = { fg = cyan },
    ["@function.builtin"] = { fg = cyan, bold = true },
    ["@function.call"] = { fg = cyan },
    ["@method"] = { fg = cyan },
    ["@method.call"] = { fg = cyan },
    ["@constructor"] = { fg = strong },
    ["@keyword"] = { fg = green },
    ["@keyword.function"] = { fg = green },
    ["@keyword.operator"] = { fg = green },
    ["@keyword.return"] = { fg = green },
    ["@conditional"] = { fg = green },
    ["@repeat"] = { fg = green },
    ["@label"] = { fg = green },
    ["@operator"] = { fg = secondary },
    ["@punctuation"] = { fg = secondary },
    ["@punctuation.bracket"] = { fg = secondary },
    ["@punctuation.delimiter"] = { fg = secondary },
    ["@punctuation.special"] = { fg = cyan },
    ["@type"] = { fg = strong },
    ["@type.builtin"] = { fg = strong, bold = true },
    ["@type.definition"] = { fg = strong },
    ["@property"] = { fg = text },
    ["@field"] = { fg = text },
    ["@parameter"] = { fg = text },
    ["@variable"] = { fg = text },
    ["@variable.builtin"] = { fg = green },
    ["@variable.parameter"] = { fg = text },
    ["@tag"] = { fg = green },
    ["@tag.attribute"] = { fg = cyan },
    ["@tag.delimiter"] = { fg = secondary },
    ["@module"] = { fg = cyan },
    ["@namespace"] = { fg = cyan },
    ["@text"] = { fg = text },
    ["@text.title"] = { fg = green, bold = true },
    ["@text.uri"] = { fg = cyan, underline = true },
    ["@text.reference"] = { fg = cyan },
    ["@markup.heading"] = { fg = green, bold = true },
    ["@markup.link"] = { fg = cyan, underline = true },
    ["@markup.raw"] = { fg = "#9FCFA8" },
    ["@markup.list"] = { fg = green },
  }
  for name, spec in pairs(ts) do
    H(name, spec)
  end

  -- Picker-specific groups.
  H("PickerPrompt", { fg = green, bg = elevated, bold = true })
  H("PickerSelected", { fg = text, bg = search, bold = true })
  H("PickerMatch", { fg = strong, bold = true })
  H("PickerPath", { fg = muted })
  H("PickerEmpty", { fg = muted, italic = true })

  -- Statusline segments.
  H("StatusLineMode", { fg = bg, bg = secondary, bold = true })
  H("StatusLineModeNormal", { fg = bg, bg = green, bold = true })
  H("StatusLineModeInsert", { fg = bg, bg = cyan, bold = true })
  H("StatusLineModeVisual", { fg = bg, bg = warn, bold = true })
  H("StatusLineModeCommand", { fg = bg, bg = secondary, bold = true })
  H("StatusLineModeTerminal", { fg = bg, bg = muted, bold = true })
  H("StatusLineModeReplace", { fg = bg, bg = err, bold = true })
  H("StatusLineFile", { fg = text, bg = surface, bold = true })
  H("StatusLineInfo", { fg = secondary, bg = surface })
  H("StatusLineDiag", { fg = secondary, bg = surface })
  H("StatusLineError", { fg = err, bg = surface, bold = true })
  H("StatusLineWarn", { fg = warn, bg = surface, bold = true })

  -- LSP semantic token links (best-effort).
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.function", { link = "@function" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.method", { link = "@method" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.class", { link = "@type" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.struct", { link = "@type" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.interface", { link = "@type" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.enum", { link = "@type" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.typeParameter", { link = "@type" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.parameter", { link = "@parameter" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.variable", { link = "@variable" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.property", { link = "@property" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.keyword", { link = "@keyword" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.comment", { link = "@comment" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.string", { link = "@string" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.number", { link = "@number" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.operator", { link = "@operator" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.macro", { link = "@macro" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.decorator", { link = "@function" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.type.namespace", { link = "@namespace" })
  pcall(vim.api.nvim_set_hl, 0, "@lsp.mod.deprecated", { fg = muted, strikethrough = true })
end

function M.setup()
  M.apply()
  local group = vim.api.nvim_create_augroup("nvim_config_highlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      M.apply()
    end,
  })
end

return M