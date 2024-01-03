local api, uv, lsp = vim.api, vim.uv, vim.lsp
local pd = {}

local function get_stl_bg()
  local res = api.nvim_get_hl(0, { name = 'StatusLine' })
  if vim.tbl_isempty(res) then
    vim.notify('[Whisky] colorschem missing StatusLine config')
    return
  end
  return res.bg
end

local stl_bg
if not stl_bg then
  stl_bg = get_stl_bg()
end

local function stl_attr(group, trans)
  local color = api.nvim_get_hl(0, { name = group, link = false })
  trans = trans or false
  return {
    bg = trans and 'NONE' or stl_bg,
    fg = color.fg,
  }
end

local function alias_mode()
  return {
    --Normal
    ['n'] = 'Normal',
    ['no'] = 'O-Pending',
    ['nov'] = 'O-Pending',
    ['noV'] = 'O-Pending',
    ['no\x16'] = 'O-Pending',
    ['niI'] = 'Normal',
    ['niR'] = 'Normal',
    ['niV'] = 'Normal',
    ['nt'] = 'Normal',
    ['ntT'] = 'Normal',
    ['v'] = 'Visual',
    ['vs'] = 'Visual',
    ['V'] = 'V-Line',
    ['Vs'] = 'V-Line',
    ['\x16'] = 'V-Block',
    ['\x16s'] = 'V-Block',
    ['s'] = 'Select',
    ['S'] = 'S-Line',
    ['\x13'] = 'S-Block',
    ['i'] = 'Insert',
    ['ic'] = 'Insert',
    ['ix'] = 'Insert',
    ['R'] = 'Replace',
    ['Rc'] = 'Replace',
    ['Rx'] = 'Replace',
    ['Rv'] = 'V-Replace',
    ['Rvc'] = 'V-Replace',
    ['Rvx'] = 'V-Replace',
    ['c'] = 'Command',
    ['cv'] = 'Ex',
    ['ce'] = 'Ex',
    ['r'] = 'Replace',
    ['rm'] = 'More',
    ['r?'] = 'Confirm',
    ['!'] = 'Shell',
    ['t'] = 'Terminal',
  }
end

function pd.mode()
  local alias = alias_mode()
  local color = api.nvim_get_hl(0, { name = 'PreProc' })
  local result = {
    stl = function()
      local mode = api.nvim_get_mode().mode
      local m = alias[mode] or alias[string.sub(mode, 1, 1)] or 'UNK'
      return m:sub(1, 3):upper()
    end,
    name = 'mode',
    default = 'NOR',
    event = { 'ModeChanged' },
    attr = {
      bg = color.fg,
      fg = 'black',
      bold = true,
    },
  }
  return result
end

local function path_sep()
  return uv.os_uname().sysname == 'Windows_NT' and '\\' or '/'
end

function pd.fileinfo()
  local result = {
    stl = '%f %P',
    name = 'fileinfo',
    event = { 'BufEnter' },
  }

  return result
end

function pd.lsp()
  local function lsp_stl(args)
    local client = lsp.get_client_by_id(args.data.client_id)
    local msg = client and client.name or ''
    if args.data.result then
      local val = args.data.result.value
      msg = val.title
        .. ' '
        .. (val.message and val.message .. ' ' or '')
        .. (val.percentage and val.percentage .. '%' or '')
      if not val.message or val.kind == 'end' then
        ---@diagnostic disable-next-line: need-check-nil
        msg = client.name
      end
    elseif args.event == 'LspDetach' then
      msg = ''
    end
    return '%.40{"' .. msg .. '"}'
  end

  local result = {
    stl = lsp_stl,
    name = 'Lsp',
    event = { 'LspProgress', 'LspAttach', 'LspDetach' },
    attr = stl_attr('Function'),
  }

  return result
end

local function gitsigns_data(bufnr, type)
  local ok, dict = pcall(api.nvim_buf_get_var, bufnr, 'gitsigns_status_dict')
  if not ok or vim.tbl_isempty(dict) or not dict[type] then
    return 0
  end

  return dict[type]
end

local function git_icons(type)
  local tbl = {
    ['added'] = '+',
    ['changed'] = '~',
    ['deleted'] = '-',
  }
  return tbl[type]
end

function pd.gitadd()
  local sign = git_icons('added')
  local result = {
    stl = function(args)
      local res = gitsigns_data(args.buf, 'added')
      return res > 0 and ('%s%s%s'):format(sign, res, ' ') or ''
    end,
    name = 'gitadd',
    event = { 'User GitSignsUpdate', 'BufEnter' },
    attr = stl_attr('DiffAdd'),
  }

  return result
end

function pd.gitchange()
  local sign = git_icons('changed')
  local result = {
    stl = function(args)
      local res = gitsigns_data(args.buf, 'changed')
      return res > 0 and ('%s%s%s'):format(sign, res, ' ') or ''
    end,
    name = 'gitchange',
    event = { 'User GitSignsUpdate', 'BufEnter' },
    attr = stl_attr('DiffChange'),
  }

  return result
end

function pd.gitdelete()
  local sign = git_icons('deleted')
  local result = {
    stl = function(args)
      local res = gitsigns_data(args.buf, 'removed')
      return res > 0 and ('%s%s'):format(sign, res) or ''
    end,
    name = 'gitdelete',
    event = { 'User GitSignsUpdate', 'BufEnter' },
    attr = stl_attr('DiffDelete'),
  }

  return result
end

function pd.branch()
  local icon = '  '
  local result = {
    stl = function(args)
      local res = gitsigns_data(args.buf, 'head')
      return res and icon .. res or ' UNKNOWN'
    end,
    name = 'gitbranch',
    event = { 'User GitSignsUpdate' },
    attr = stl_attr('Include'),
  }
  return result
end

function pd.lnumcol()
  local result = {
    stl = '%-4.(L%l:C%c%)',
    name = 'linecol',
    event = { 'CursorHold' },
  }

  return result
end

local function diagnostic_info(severity)
  return function()
    if vim.diagnostic.is_disabled(0) then
      return ''
    end

    local ns = api.nvim_get_namespaces()
    local key = vim.iter(ns):find(function(k)
      return k:find('diagnostic/signs')
    end)
    if not key then
      return ''
    end
    local signs = api.nvim_buf_get_extmarks(0, ns[key], 0, -1, { details = true, type = 'sign' })
    local t = vim.iter(signs):find(function(k)
      local text = (vim.diagnostic.severity[severity]):lower()
      return (k[4].sign_hl_group):lower():find(text)
    end)
    local count = vim.diagnostic.get(0, { severity = severity })
    return t and t[4].sign_text .. count or ''
  end
end

function pd.diagError()
  local f = diagnostic_info(vim.diagnostic.severity.E)
  local result = {
    stl = function()
      return f()
    end,
    name = 'diagError',
    event = { 'DiagnosticChanged', 'BufEnter' },
    attr = stl_attr('DiagnosticError'),
  }
  return result
end

function pd.diagWarn()
  local f = diagnostic_info(vim.diagnostic.severity.W)
  local result = {
    stl = function()
      return f()
    end,
    name = 'diagWarn',
    event = { 'DiagnosticChanged', 'BufEnter' },
    attr = stl_attr('DiagnosticWarn'),
  }
  return result
end

function pd.diagInfo()
  local f = diagnostic_info(vim.diagnostic.severity.I)
  local result = {
    stl = function()
      return f()
    end,
    name = 'diaginfo',
    event = { 'DiagnosticChanged', 'BufEnter' },
    attr = stl_attr('DiagnosticInfo'),
  }
  return result
end

function pd.diagHint()
  local f = diagnostic_info(vim.diagnostic.severity.HINT)
  local result = {
    stl = function()
      return f()
    end,
    name = 'diaghint',
    event = { 'DiagnosticChanged', 'BufEnter' },
    attr = stl_attr('DiagnosticHint'),
  }
  return result
end

function pd.modified()
  return {
    name = 'modified',
    stl = '%{&modified?"**":"--"}',
    event = { 'BufModifiedSet' },
  }
end

function pd.eol()
  return {
    name = 'eol',
    stl = path_sep() == '/' and ':' or '(Dos)',
    event = { 'BufEnter' },
    attr = {
      bold = true,
      bg = stl_bg,
    },
  }
end

function pd.encoding()
  local map = {
    ['utf-8'] = 'U',
    ['utf-16'] = 'U16',
    ['utf-32'] = 'U32',
    ['unix'] = 'U',
    ['linux'] = 'L',
    ['dos'] = 'W',
  }
  local result = {
    stl = map[vim.o.ff] .. (vim.o.fileencoding and map[vim.o.fileencoding] or map[vim.o.encoding]),
    name = 'filencode',
    event = { 'BufEnter' },
  }
  return result
end

function pd.pad()
  return {
    stl = '%=',
    name = 'pad',
  }
end

function pd.space()
  return {
    stl = ' ',
    name = 'space',
  }
end

return pd
