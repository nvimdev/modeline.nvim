local api, uv = vim.api, vim.loop
local pd = {}

pd.initialized = false

function pd.stl_bg()
  return require('whiskyline').bg
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

function pd.lsp()
  local function lsp_stl(event)
    local new_messages = get_progress_messages()
    local msg = ''

    for i, item in ipairs(new_messages) do
      if i == #new_messages then
        msg = item.title
        if item.message then
          msg = msg .. ' ' .. item.message
        end
        if item.percentage then
          msg = msg .. ' ' .. item.percentage .. '%'
        end
      end
    end

    if #msg == 0 and event ~= 'LspDetach' then
      local client = vim.lsp.get_active_clients({ bufnr = 0 })
      if #client ~= 0 then
        msg = client[1].name
      end
    end
    return '%.40{"' .. msg .. '"}'
  end

  local result = {
    stl = lsp_stl,
    name = 'Lsp',
    event = { 'LspProgressUpdate', 'LspAttach', 'LspDetach' },
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
      local res = gitsigns_data('removed')
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
    result.attr = stl_attr('Include')
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
    event = { 'DiagnosticChanged', 'BufEnter' },
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
