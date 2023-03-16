local api, uv = vim.api, vim.loop
local pd = {}

pd.initialized = false

function pd.stl_bg()
  return '#2a2a47'
end

local function stl_attr(group, trans)
  local color = api.nvim_get_hl_by_name(group, true)
  trans = trans or false
  return {
    bg = trans and 'NONE' or pd.stl_bg(),
    fg = color.foreground,
  }
end

local function alias_mode()
  return {
    n = 'NORMAL',
    i = 'INSERT',
    niI = 'CTRL-O',
    R = 'REPLAC',
    c = 'C-LINE',
    v = 'VISUAL',
    V = 'V-LINE',
    [''] = 'VBLOCK',
    s = 'SELEKT',
    S = 'S-LINE',
    [''] = 'SBLOCK',
    t = 'TERMNL',
    nt = 'NORM-L',
    ntT = 'C-\\C-O',
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
    event = { 'ModeChanged', 'BufEnter' },
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

local resolve

local function init_devicon()
  if resolve then
    return
  end
  local ok, devicon = pcall(require, 'nvim-web-devicons')
  if not ok then
    return
  end
  resolve = devicon
end

function pd.fileicon()
  if not resolve then
    init_devicon()
  end

  local icon, color = resolve.get_icon_color_by_filetype(vim.bo.filetype, { default = true })
  return {
    stl = function()
      return icon .. ' '
    end,
    name = 'fileicon',
    event = { 'BufEnter' },
    attr = {
      bg = pd.stl_bg(),
      fg = color,
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
    return fname .. '%m'
  end
  local result = {
    stl = stl_file,
    name = 'fileinfo',
    event = { 'BufEnter' },
  }

  if not pd.initialized then
    result.attr = stl_attr('Normal')
  end

  return result
end

local function get_progress_messages()
  local new_messages = {}
  local progress_remove = {}

  for _, client in ipairs(vim.lsp.get_active_clients()) do
    local messages = client.messages
    local data = messages
    for token, ctx in pairs(data.progress) do
      local new_report = {
        name = data.name,
        title = ctx.title or 'empty title',
        message = ctx.message,
        percentage = ctx.percentage,
        done = ctx.done,
        progress = true,
      }
      table.insert(new_messages, new_report)

      if ctx.done then
        table.insert(progress_remove, { client = client, token = token })
      end
    end
  end

  if not vim.tbl_isempty(progress_remove) then
    for _, item in ipairs(progress_remove) do
      item.client.messages.progress[item.token] = nil
    end
    return {}
  end

  return new_messages
end

local index = 1
function pd.lsp()
  local function lsp_stl()
    local new_messages = get_progress_messages()
    local res = {}
    local spinner = { '🌖', '🌗', '🌘', '🌑', '🌒', '🌓', '🌔' }

    if not vim.tbl_isempty(new_messages) then
      table.insert(res, spinner[index] .. ' Waiting')
      index = index + 1 > #spinner and 1 or index + 1
    end

    if #res == 0 then
      local client = vim.lsp.get_active_clients({ bufnr = 0 })
      if #client ~= 0 then
        table.insert(res, client[1].name)
      end
    end
    return '%.20{"' .. table.concat(res, '') .. '"}'
  end

  local result = {
    stl = lsp_stl,
    name = 'Lsp',
    event = { 'LspProgressUpdate', 'LspAttach' },
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
    event = { 'GitSignsUpdate' },
  }
  if not pd.initialized then
    result.attr = stl_attr('diffAdded')
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
    event = { 'GitSignsUpdate' },
  }

  if not pd.initialized then
    result.attr = stl_attr('diffChanged')
  end
  return result
end

function pd.gitdelete()
  local result = {
    stl = function()
      local res = gitsigns_data('deleted')
      return #res > 0 and git_icons('deleted') .. res or ''
    end,
    name = 'gitdelete',
    event = { 'GitSignsUpdate' },
  }

  if not pd.initialized then
    result.attr = stl_attr('diffRemoved')
  end
  return result
end

function pd.branch()
  local result = {
    stl = function()
      local icon = ' '
      local res = gitsigns_data('head')
      return #res > 0 and icon .. res or 'UNKOWN'
    end,
    name = 'gitbranch',
    event = { 'GitSignsUpdate' },
  }
  if not pd.initialized then
    result.attr = stl_attr('@parameter')
    result.attr.bold = true
  end
  return result
end

function pd.pad()
  return {
    stl = '%=',
    name = 'pad',
    attr = {
      background = 'NONE',
      foreground = 'NONE',
    },
  }
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

  local signs = {
    ' ',
    ' ',
    ' ',
    ' ',
  }
  local count = #vim.diagnostic.get(0, { severity = severity })
  return count == 0 and '' or signs[severity] .. tostring(count) .. ' '
end

function pd.diagError()
  local result = {
    stl = function()
      return diagnostic_info(1)
    end,
    name = 'diagError',
    event = { 'DiagnosticChanged' },
  }
  if not pd.initialized then
    result.attr = stl_attr('DiagnosticError', true)
  end
  return result
end

function pd.diagWarn()
  local result = {
    stl = function()
      return diagnostic_info(2)
    end,
    name = 'diagWarn',
    event = { 'DiagnosticChanged', 'BufEnter' },
  }
  if not pd.initialized then
    result.attr = stl_attr('DiagnosticWarn', true)
  end
  return result
end

function pd.diagInfo()
  local result = {
    stl = function()
      return diagnostic_info(3)
    end,
    name = 'diaginfo',
    event = { 'DiagnosticChanged', 'BufEnter' },
  }
  if not pd.initialized then
    result.attr = stl_attr('DiagnosticInfo', true)
  end
  return result
end

function pd.diagHint()
  local result = {
    stl = function()
      return diagnostic_info(4)
    end,
    name = 'diaghint',
    event = { 'DiagnosticChanged', 'BufEnter' },
  }
  if not pd.initialized then
    result.attr = stl_attr('DiagnosticHint', true)
  end
  return result
end

function pd.encoding()
  local result = {
    stl = '%{&fileencoding?&fileencoding:&encoding}',
    name = 'filencode',
    event = { 'BufEnter' },
  }
  if not pd.initialized then
    result.attr = stl_attr('Type')
  end
  return result
end

return pd
