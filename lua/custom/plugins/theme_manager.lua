-- ============================================================================
-- JSON-driven theme manager
--
-- Themes are flat base16 palettes stored as JSON under:
--     ~/.config/nvim/themes/dark/<name>.json     (background = dark)
--     ~/.config/nvim/themes/light/<name>.json    (background = light)
-- The folder is the source of truth for `background`.
--
-- Each file holds base00..base0F (#rrggbb). Optional non-palette keys:
--     "name"        -> display name (defaults to the file name)
--     "highlights"  -> nvim-only overrides applied after the base16 scheme,
--                      e.g. { "Comment": { "italic": true } }  (ignored by
--                      other programs, since they only read the base colors)
--
-- `:Theme <name>` applies the palette to:
--   1. Neovim  -> via mini.base16 (full highlight-group coverage) + overrides
--   2. Tabby   -> rewrites terminal.colorScheme in its config.yaml; Tabby
--                 watches the file and hot-reloads, so the terminal re-themes
--   3. Export  -> ~/.config/themes/current.{sh,json} for any other tool
-- and persists the choice so the next nvim launch restores it.
-- ============================================================================

local M = {}

local themes_root = vim.fs.joinpath(vim.fn.stdpath 'config', 'themes')
local state_file = vim.fs.joinpath(vim.fn.stdpath 'state', 'last_theme.json')
local export_dir = vim.fn.expand '~/.config/themes'
local tabby_cfg = vim.fn.expand '~/Library/Application Support/tabby/config.yaml'

local BASE_KEYS = {
  'base00', 'base01', 'base02', 'base03', 'base04', 'base05', 'base06', 'base07',
  'base08', 'base09', 'base0A', 'base0B', 'base0C', 'base0D', 'base0E', 'base0F',
}

-- base16 -> 16 ANSI slots (0..15), the standard base16 terminal mapping.
local ANSI = {
  'base00', 'base08', 'base0B', 'base0A', 'base0D', 'base0E', 'base0C', 'base05',
  'base03', 'base08', 'base0B', 'base0A', 'base0D', 'base0E', 'base0C', 'base07',
}

-- ── helpers ────────────────────────────────────────────────────────────────
local function read_json(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  local ok2, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok2 then
    return nil
  end
  return decoded
end

local function warn(msg)
  vim.notify('[Theme] ' .. msg, vim.log.levels.ERROR)
end

local function is_hex(v)
  return type(v) == 'string' and v:match '^#%x%x%x%x%x%x$' ~= nil
end

-- ── color math (for converting between the two theme formats) ────────────────
local function hex_rgb(h)
  return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
end

local function rgb_hex(r, g, b)
  return string.format('#%02x%02x%02x', r, g, b)
end

-- Linear blend between two hex colors; t=0 -> a, t=1 -> b.
local function mix(a, b, t)
  local ar, ag, ab = hex_rgb(a)
  local br, bg, bb = hex_rgb(b)
  return rgb_hex(
    math.floor(ar + (br - ar) * t + 0.5),
    math.floor(ag + (bg - ag) * t + 0.5),
    math.floor(ab + (bb - ab) * t + 0.5)
  )
end

-- A terminal palette: { name, foreground, background, cursor, colors[1..16] }
-- (colors[1] = ANSI color0 ... colors[16] = ANSI color15)

-- base16 palette -> terminal palette (standard base16 ANSI projection).
local function base16_to_term(p, name)
  local colors = {}
  for _, key in ipairs(ANSI) do
    colors[#colors + 1] = p[key]
  end
  return { name = name, foreground = p.base05, background = p.base00, cursor = p.base05, colors = colors }
end

-- terminal palette -> base16 palette. Accents come from the real ANSI colors;
-- the base00..07 gray ramp is interpolated between background and foreground.
-- Approximate (terminal palettes aren't base16), but coherent for mini.base16.
local function term_to_base16(t)
  local c, bg, fg = t.colors, t.background, t.foreground
  return {
    base00 = bg,
    base01 = mix(bg, fg, 0.10),
    base02 = mix(bg, fg, 0.20),
    base03 = c[9], -- ANSI bright black -> comments
    base04 = mix(bg, fg, 0.70),
    base05 = fg,
    base06 = mix(bg, fg, 0.90),
    base07 = c[16], -- ANSI bright white
    base08 = c[2], -- red
    base09 = c[10], -- (orange) bright red
    base0A = c[4], -- yellow
    base0B = c[3], -- green
    base0C = c[7], -- cyan
    base0D = c[5], -- blue
    base0E = c[6], -- magenta
    base0F = c[8], -- ANSI white (misc/brown slot)
  }
end

-- Resolve a theme name to a normalized spec with BOTH representations, so each
-- consumer gets its ideal input. Returns spec or nil + error message.
--   spec = { name, background, base16 = {...}, term = {...}, highlights }
local function resolve(name)
  for _, bg in ipairs { 'dark', 'light' } do
    local path = vim.fs.joinpath(themes_root, bg, name .. '.json')
    local data = read_json(path)
    if data then
      local spec = { name = data.name or name, background = bg, highlights = data.highlights }

      if type(data.colors) == 'table' and #data.colors == 16 then
        -- Terminal-palette format (e.g. imported from Tabby).
        for _, field in ipairs { 'foreground', 'background' } do
          if not is_hex(data[field]) then
            return nil, ('%s: %s must be a "#rrggbb" hex'):format(name, field)
          end
        end
        for i, v in ipairs(data.colors) do
          if not is_hex(v) then
            return nil, ('%s: colors[%d] must be a "#rrggbb" hex'):format(name, i)
          end
        end
        spec.term = {
          name = spec.name,
          foreground = data.foreground,
          background = data.background,
          cursor = (is_hex(data.cursor) and data.cursor) or data.foreground,
          colors = data.colors,
        }
        spec.base16 = term_to_base16(spec.term)
      else
        -- base16 format.
        local palette = {}
        for _, k in ipairs(BASE_KEYS) do
          if not is_hex(data[k]) then
            return nil, ('%s: %s must be a "#rrggbb" hex (got %s)'):format(name, k, vim.inspect(data[k]))
          end
          palette[k] = data[k]
        end
        spec.base16 = palette
        spec.term = base16_to_term(palette, spec.name)
      end

      return spec
    end
  end
  return nil, 'theme not found: ' .. name
end

-- List available theme names (across both folders).
local function list_names(prefix)
  local names = {}
  for _, bg in ipairs { 'dark', 'light' } do
    local dir = vim.fs.joinpath(themes_root, bg)
    local ok, iter = pcall(vim.fs.dir, dir)
    if ok then
      for fname, ftype in iter do
        if ftype == 'file' and fname:match '%.json$' then
          local n = fname:gsub('%.json$', '')
          if not prefix or n:find(prefix, 1, true) == 1 then
            table.insert(names, n)
          end
        end
      end
    end
  end
  table.sort(names)
  return names
end

-- ── appliers ───────────────────────────────────────────────────────────────
local function apply_nvim(spec)
  vim.o.background = spec.background
  require('mini.base16').setup { palette = spec.base16, use_cterm = true }
  vim.g.colors_name = spec.name
  if type(spec.highlights) == 'table' then
    for group, hl in pairs(spec.highlights) do
      pcall(vim.api.nvim_set_hl, 0, group, hl)
    end
  end
end

-- Build the replacement `colorScheme:` YAML block from a terminal palette,
-- matching Tabby's indentation. Single-quote the name (may contain spaces/-).
local function tabby_block(term, indent)
  local sp = string.rep(' ', indent)
  local sp2 = string.rep(' ', indent + 2)
  local sp3 = string.rep(' ', indent + 4)
  local out = {
    sp .. 'colorScheme:',
    sp2 .. "name: '" .. term.name:gsub("'", "''") .. "'",
    sp2 .. "foreground: '" .. term.foreground .. "'",
    sp2 .. "background: '" .. term.background .. "'",
    sp2 .. "cursor: '" .. term.cursor .. "'",
    sp2 .. 'colors:',
  }
  for _, c in ipairs(term.colors) do
    table.insert(out, sp3 .. "- '" .. c .. "'")
  end
  return out
end

-- Replace the `terminal.colorScheme` block in Tabby's config.yaml in place,
-- preserving everything else. Returns ok, err.
local function apply_tabby(spec)
  if vim.fn.filereadable(tabby_cfg) == 0 then
    return false, 'config not found'
  end
  local lines = vim.fn.readfile(tabby_cfg)

  local start_idx, indent
  for i, l in ipairs(lines) do
    local lead = l:match '^(%s*)colorScheme:%s*$'
    if lead then
      start_idx, indent = i, #lead
      break
    end
  end
  if not start_idx then
    return false, 'colorScheme key not found'
  end

  -- Block ends at the next non-blank line indented at or below colorScheme's level.
  local stop_idx = #lines + 1
  for i = start_idx + 1, #lines do
    local l = lines[i]
    if l:match '%S' and #(l:match '^(%s*)') <= indent then
      stop_idx = i
      break
    end
  end

  local out = {}
  for i = 1, start_idx - 1 do
    table.insert(out, lines[i])
  end
  vim.list_extend(out, tabby_block(spec.term, indent))
  for i = stop_idx, #lines do
    table.insert(out, lines[i])
  end

  -- Keep a one-time pristine backup before the first modification.
  local orig = tabby_cfg .. '.orig'
  if vim.fn.filereadable(orig) == 0 then
    vim.fn.writefile(lines, orig)
  end
  -- Atomic-ish write via temp + rename.
  local tmp = tabby_cfg .. '.tmp'
  vim.fn.writefile(out, tmp)
  local ok = (vim.uv or vim.loop).fs_rename(tmp, tabby_cfg)
  if not ok then
    return false, 'failed to write config'
  end
  return true
end

local function apply_export(spec)
  vim.fn.mkdir(export_dir, 'p')
  local p, term = spec.base16, spec.term

  local sh = {
    '# Generated by :Theme — active palette. Do not edit by hand.',
    "export THEME_NAME='" .. spec.name .. "'",
    "export THEME_BACKGROUND='" .. spec.background .. "'",
  }
  for _, k in ipairs(BASE_KEYS) do
    table.insert(sh, 'export ' .. k:upper() .. "='" .. p[k] .. "'")
  end
  for i, c in ipairs(term.colors) do
    table.insert(sh, 'export ANSI' .. (i - 1) .. "='" .. c .. "'")
  end
  table.insert(sh, "export FOREGROUND='" .. term.foreground .. "'")
  table.insert(sh, "export BACKGROUND='" .. term.background .. "'")
  vim.fn.writefile(sh, vim.fs.joinpath(export_dir, 'current.sh'))

  local json = {
    name = spec.name,
    background = spec.background,
    palette = p,
    ansi = term.colors,
    foreground = term.foreground,
    background_color = term.background,
    cursor = term.cursor,
  }
  vim.fn.writefile({ vim.json.encode(json) }, vim.fs.joinpath(export_dir, 'current.json'))
end

local function persist(name)
  vim.fn.mkdir(vim.fn.stdpath 'state', 'p')
  vim.fn.writefile({ vim.json.encode { name = name } }, state_file)
end

-- ── public API ───────────────────────────────────────────────────────────────
-- opts: { nvim_only = bool, silent = bool, no_persist = bool }
function M.apply(name, opts)
  opts = opts or {}
  local theme, err = resolve(name)
  if not theme then
    warn(err)
    return false
  end

  apply_nvim(theme)

  if not opts.nvim_only then
    local ok, terr = apply_tabby(theme)
    if not ok then
      vim.notify('[Theme] Tabby skipped: ' .. terr, vim.log.levels.WARN)
    end
    pcall(apply_export, theme)
  end

  if not opts.no_persist then
    persist(name)
  end

  if not opts.silent then
    vim.notify(('[Theme] %s (%s)'):format(theme.name, theme.background))
  end
  return true
end

-- ── commands / keymaps ───────────────────────────────────────────────────────
vim.api.nvim_create_user_command('Theme', function(o)
  M.apply(o.args)
end, {
  nargs = 1,
  complete = function(arglead)
    return list_names(arglead ~= '' and arglead or nil)
  end,
  desc = 'Apply a theme to Neovim + Tabby + export',
})

vim.api.nvim_create_user_command('Themes', function()
  local names = list_names()
  if #names == 0 then
    warn('no themes found under ' .. themes_root)
    return
  end
  vim.notify('[Theme] available: ' .. table.concat(names, ', '))
end, { desc = 'List available themes' })

-- Fuzzy theme picker (uses telescope-ui-select via vim.ui.select).
vim.keymap.set('n', '<leader>ut', function()
  vim.ui.select(list_names(), { prompt = 'Theme' }, function(choice)
    if choice then
      M.apply(choice)
    end
  end)
end, { desc = 'Pick [u]I [t]heme' })

-- ── restore persisted theme on startup ───────────────────────────────────────
-- Deferred so it runs after init.lua's default colorscheme, overriding it.
-- nvim_only: Tabby/export already reflect the last :Theme; no need to rewrite
-- them on every launch (avoids thrash when several nvim instances start).
vim.schedule(function()
  local data = read_json(state_file)
  if data and data.name then
    M.apply(data.name, { nvim_only = true, silent = true, no_persist = true })
  end
end)

return M
