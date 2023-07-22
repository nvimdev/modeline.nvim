local api, uv, lsp = vim.api, vim.uv, vim.lsp
local pd = {}

local function get_stl_bg()
  local res = api.nvim_get_hl_by_name('StatusLine', true)
  if vim.tbl_count(res) == 0 then
    vim.notify('[Whisky] colorschem missing StatusLine config')
    return
  end
  return res.background
end

local stl_bg
if not stl_bg then
  stl_bg = get_stl_bg()
end

local function stl_attr(group, trans)
  local color = api.nvim_get_hl_by_name(group, true)
  trans = trans or false
  return {
    bg = trans and 'NONE' or stl_bg,
    fg = color.foreground,
  }
end

local function alias_mode()
  return {
    --Normal
    ['n'] = 'N-',
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
  local result = {
    stl = function()
      local mode = api.nvim_get_mode().mode
      return alias[mode] or alias[string.sub(mode, 1, 1)] or 'UNK'
    end,
    name = 'mode',
    default = 'Normal',
    event = { 'ModeChanged' },
  }

  if not pd.initialized then
    result.attr = stl_attr('@keyword')
    result.attr.bold = true
  end

  return result
end

local function path_sep()
  return uv.os_uname().sysname == 'Windows_NT' and '\\' or '/'
end

function pd.fileicon()
  local ok, devicon = pcall(require, 'nvim-web-devicons')
  local icon, color

  return {
    stl = function()
      if ok then
        icon, color = devicon.get_icon_color_by_filetype(vim.bo.filetype, { default = true })
        api.nvim_set_hl(0, 'Whiskyfileicon', { bg = stl_bg, fg = color })
        return icon .. ' '
      end
      return ''
    end,
    name = 'fileicon',
    event = { 'BufEnter' },
    attr = {
      bg = stl_bg,
    },
  }
end

function pd.fileinfo()
  local function stl_file()
    local fname = api.nvim_buf_get_name(0)
    local sep = path_sep()
    local parts = vim.split(fname, sep, { trimempty = true })
    local index = #parts - 1 <= 0 and 1 or #parts - 1
    fname = table.concat({ unpack(parts, index) }, sep)
    if #fname == 0 then
      fname = 'UNKNOWN'
    end
    return fname
  end

  local result = {
    stl = stl_file,
    name = 'fileinfo',
    event = { 'BufEnter' },
    attr = {
      bg = stl_bg,
    },
  }

  return result
end

function pd.lsp()
  local function lsp_stl(args)
    local client = lsp.get_client_by_id(args.data.client_id)
    local msg = ''
    if args.data.result then
      local val = args.data.result.value
      msg = val.title
        .. ' '
        .. (val.message and val.message .. ' ' or '')
        .. (val.percentage and val.percentage .. '%' or '')
      if not val.message or val.kind == 'end' then
        msg = client.name
      end
    elseif args.event == 'LspDetach' then
      msg = ''
    else
      msg = client.name
    end
    return '%.40{"' .. msg .. '"}'
  end

  local result = {
    stl = lsp_stl,
    name = 'Lsp',
    event = { 'LspProgress', 'LspAttach', 'LspDetach' },
  }

  if not pd.initialized then
    result.attr = stl_attr('Function')
    result.attr.bold = true
  end
  return result
end

local function gitsigns_data(type)
  if not vim.b.gitsigns_status_dict then
    return ''
  end

  local val = vim.b.gitsigns_status_dict[type]
  val = (val == 0 or not val) and '' or tostring(val) .. (type == 'head' and '' or ' ')
  return val
end

local function git_icons(type)
  local tbl = {
    ['added'] = ' ',
    ['changed'] = ' ',
    ['deleted'] = ' ',
  }
  return tbl[type]
end

function pd.gitadd()
  local result = {
    stl = function()
      local res = gitsigns_data('added')
      return #res > 0 and git_icons('added') .. res or ''
    end,
    name = 'gitadd',
    event = { 'User GitSignsUpdate' },
  }
  if not pd.initialized then
    result.attr = stl_attr('DiffAdd')
  end
  return result
end

function pd.gitchange()
  local result = {
    stl = function()
      local res = gitsigns_data('changed')
      return #res > 0 and git_icons('changed') .. res or ''
    end,
    name = 'gitchange',
    event = { 'User GitSignsUpdate' },
  }

  if not pd.initialized then
    result.attr = stl_attr('DiffChange')
  end
  return result
end

function pd.gitdelete()
  local result = {
    stl = function()
      local res = gitsigns_data('removed')
      return #res > 0 and git_icons('deleted') .. res or ''
    end,
    name = 'gitdelete',
    event = { 'User GitSignsUpdate' },
  }

  if not pd.initialized then
    result.attr = stl_attr('DiffDelete')
  end
  return result
end

function pd.branch()
  local icon = ' '
  local result = {
    stl = function()
      local res = gitsigns_data('head')
      return #res > 0 and icon .. res or 'UNKOWN'
    end,
    name = 'gitbranch',
    event = { 'User GitSignsUpdate' },
  }
  if not pd.initialized then
    result.attr = stl_attr('Include')
    result.attr.bold = true
  end
  return result
end

function pd.lnumcol()
  local result = {
    stl = '%-4.(%l:%c%) %P',
    name = 'linecol',
    event = { 'CursorHold' },
  }

  if not pd.initialized then
    result.attr = stl_attr('Label')
  end
  return result
end

local function diagnostic_info(severity)
  if vim.diagnostic.is_disabled(0) then
    return ''
  end
  local count = #vim.diagnostic.get(0, { severity = severity })
  return count == 0 and '' or '●' .. tostring(count) .. ' '
end

function pd.diagError()
  local result = {
    stl = function()
      return diagnostic_info(1)
    end,
    name = 'diagError',
    event = { 'DiagnosticChanged', 'BufEnter' },
    attr = stl_attr('DiagnosticError'),
  }
  return result
end

function pd.diagWarn()
  local result = {
    stl = function()
      return diagnostic_info(2)
    end,
    name = 'diagWarn',
    event = { 'DiagnosticChanged', 'BufEnter' },
    attr = stl_attr('DiagnosticWarn'),
  }
  return result
end

function pd.diagInfo()
  local result = {
    stl = function()
      return diagnostic_info(3)
    end,
    name = 'diaginfo',
    event = { 'DiagnosticChanged', 'BufEnter' },
    attr = stl_attr('DiagnosticInfo'),
  }
  return result
end

function pd.diagHint()
  local result = {
    stl = function()
      return diagnostic_info(4)
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
    stl = '%{&modified?"∗∗":"--"}',
    event = { 'BufModifiedSet' },
    attr = {
      bold = true,
      bg = stl_bg,
    },
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
    attr = {
      bold = true,
      bg = stl_bg,
    },
  }
  return result
end

return pd
