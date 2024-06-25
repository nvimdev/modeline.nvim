local api, uv, lsp, diagnostic, M = vim.api, vim.uv, vim.lsp, vim.diagnostic, {}
local fnamemodify = vim.fn.fnamemodify

_G.has_lsp = function()
  return #lsp.get_clients({ bufnr = 0 }) > 0
end

local function get_stl_bg()
  local res = api.nvim_get_hl(0, { name = 'StatusLine' })
  if vim.tbl_isempty(res) then
    vim.notify('[WhiskyLine:] colorscheme missing StatusLine config')
    return
  end
  return res.bg
end

local stl_bg = get_stl_bg()
local function stl_attr(group)
  local color = api.nvim_get_hl(0, { name = group, link = false })
  return {
    bg = stl_bg,
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

function M.mode()
  local alias = alias_mode()
  return {
    stl = function()
      local mode = api.nvim_get_mode().mode
      local m = alias[mode] or alias[string.sub(mode, 1, 1)] or 'UNK'
      return m:sub(1, 3):upper()
    end,
    name = 'mode',
    default = 'NOR',
    event = { 'ModeChanged' },
    attr = {
      bg = stl_bg,
      fg = 'black',
      bold = true,
    },
  }
end

function M.fileinfo()
  return {
    stl = [[%{expand('%:t')}]],
    name = 'fileinfo',
    event = { 'BufEnter' },
    attr = {
      bold = true,
      fg = 'black',
      bg = stl_bg,
    },
  }
end

function M.progress()
  local spinner = { '⣶', '⣧', '⣏', '⡟', '⠿', '⢻', '⣹', '⣼' }
  local idx = 1
  return {
    stl = function(args)
      if args.data and args.data.params then
        local val = args.data.params.value
        if val.message and val.kind ~= 'end' then
          idx = idx + 1 > #spinner and 1 or idx + 1
          return ('%s'):format(spinner[idx - 1 > 0 and idx - 1 or 1])
        end
      end
      return ''
    end,
    name = 'LspProgress',
    event = { 'LspProgress' },
    attr = stl_attr('Type'),
  }
end

function M.lsp()
  return {
    stl = function(args)
      local client = lsp.get_clients({ bufnr = 0 })[1]
      if not client then
        return ''
      end
      local msg = client and client.name or ''
      if args.data and args.data.params then
        local val = args.data.params.value
        if not val.message or val.kind == 'end' then
          msg = ('%s:%s'):format(
            client.name,
            client.root_dir and fnamemodify(client.root_dir, ':t') or 'single'
          )
        else
          msg = ('%s %s%s'):format(
            val.title,
            (val.message and val.message .. ' ' or ''),
            (val.percentage and val.percentage .. '%' or '')
          )
        end
      elseif args.event == 'BufEnter' then
        msg = ('%s:%s'):format(
          client.name,
          client.root_dir and fnamemodify(client.root_dir, ':t') or 'single'
        )
      elseif args.event == 'LspDetach' then
        msg = ''
      end
      return '%-20s' .. msg
    end,
    name = 'Lsp',
    event = { 'LspProgress', 'LspAttach', 'LspDetach', 'BufEnter' },
  }
end

local function gitsigns_data(git_t)
  local signs = {
    ['added'] = '+',
    ['changed'] = '~',
    ['removed'] = '-',
    ['head'] = '',
  }
  return function(args)
    local ok, dict = pcall(api.nvim_buf_get_var, args.buf, 'gitsigns_status_dict')
    if
      not ok
      or vim.tbl_isempty(dict)
      or not dict[git_t]
      or (type(dict[git_t]) == 'number' and dict[git_t] <= 0)
    then
      return ''
    end
    if git_t == 'head' and dict[git_t] == '' then
      local obj = vim
        .system({ 'git', 'config', '--get', 'init.defaultBranch' }, { text = true })
        :wait()
      if #obj.stdout > 0 then
        dict[git_t] = vim.trim(obj.stdout)
      end
    end
    return ('%s%s%s'):format(signs[git_t], dict[git_t], ' ')
  end
end

function M.gitinfo(git_t)
  local alias = {
    ['added'] = 'Add',
    ['changed'] = 'Change',
    ['removed'] = 'Delete',
  }
  return {
    stl = gitsigns_data(git_t),
    name = 'git' .. git_t,
    event = { 'User GitSignsUpdate', 'BufEnter' },
    attr = git_t ~= 'head' and stl_attr('GitSigns' .. alias[git_t]) or nil,
  }
end

function M.lnumcol()
  return {
    stl = '   %P (%(%l,%c%))',
    name = 'linecol',
  }
end

local function diagnostic_info()
  return function()
    if not vim.diagnostic.is_enabled({ bufnr = 0 }) or #lsp.get_clients({ bufnr = 0 }) == 0 then
      return ''
    end
    local t = {}
    for i = 1, 3 do
      local count = #diagnostic.get(0, { severity = i })
      t[#t + 1] = ('%%#ModeLine%s#%s%%*'):format(vim.diagnostic.severity[i], count)
    end
    return (' Diagnostic[%s]'):format(table.concat(t, ' '))
  end
end

function M.diagnostic()
  for i = 1, 3 do
    local name = ('Diagnostic%s'):format(diagnostic.severity[i])
    local fg = api.nvim_get_hl(0, { name = name }).fg
    api.nvim_set_hl(0, 'ModeLine' .. diagnostic.severity[i], { fg = fg, bg = stl_bg })
  end
  return {
    stl = diagnostic_info(),
    name = 'Diagnostic',
    event = { 'DiagnosticChanged', 'BufEnter', 'LspAttach' },
  }
end

function M.modified()
  return {
    name = 'modified',
    stl = [[%{(&modified&&&readonly?'%*':(&modified?'**':(&readonly?'%%':'--')))}  ]],
    event = { 'BufModifiedSet' },
  }
end

function M.eol()
  return {
    name = 'eol',
    stl = (not uv.os_uname().sysname:find('Windows')) and ':' or '(Dos)',
    event = { 'BufEnter' },
  }
end

function M.encoding()
  local map = {
    ['utf-8'] = 'U',
    ['utf-16'] = 'U16',
    ['utf-32'] = 'U32',
    ['unix'] = 'U',
    ['linux'] = 'L',
    ['dos'] = 'W',
  }
  return {
    stl = (' %s%s'):format(
      map[vim.o.ff],
      (vim.o.fileencoding and map[vim.o.fileencoding] or map[vim.o.encoding])
    ),
    name = 'filencode',
    event = { 'BufEnter' },
  }
end

return M