local api, lsp, diagnostic = vim.api, vim.lsp, vim.diagnostic
local fnamemodify = vim.fn.fnamemodify
local M = {}

local function esc(s)
  return (tostring(s):gsub('%%', '%%%%'))
end
M.escape = esc

local mode_alias = {
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

function _G.ml_mode()
  local mode = api.nvim_get_mode().mode
  local m = mode_alias[mode] or mode_alias[mode:sub(1, 1)] or 'UNK'
  return m:sub(1, 3):upper()
end

local progress = { clients = {}, seen = nil }

local function latest_token(st)
  for token, text in pairs(st.texts) do
    if text then
      return token
    end
  end
end

local function track(args)
  if not args or args == progress.seen then
    return
  end
  progress.seen = args
  local data = args.data or {}
  local cid = data.client_id
  if cid == nil then
    return
  end

  if args.event == 'LspDetach' then
    local client = lsp.get_client_by_id(cid)
    if
      not client
      or client.is_stopped(client)
      or vim.tbl_count(client.attached_buffers or {}) <= 1
    then
      progress.clients[cid] = nil
    end
    return
  end
  if args.event ~= 'LspProgress' then
    return
  end

  local params = data.params
  local val = params and params.value
  local token = params and params.token
  if type(val) ~= 'table' or token == nil then
    return
  end

  local st = progress.clients[cid]
  if not st then
    st = { titles = {}, texts = {} }
    progress.clients[cid] = st
  end

  if val.kind == 'end' then
    st.titles[token], st.texts[token] = nil, nil
    if st.latest == token then
      st.latest = latest_token(st)
    end
    if next(st.texts) == nil then
      progress.clients[cid] = nil
    end
    return
  end

  st.titles[token] = val.title or st.titles[token]
  local title = st.titles[token]
  local text = false
  if title then
    text = type(val.percentage) == 'number'
        and ('%s %d%%'):format(title, math.floor(val.percentage))
      or title
    st.latest = token
  end
  st.texts[token] = text
end

local function progress_busy()
  return next(progress.clients) ~= nil
end

local function progress_text(cid)
  local st = progress.clients[cid]
  return st and st.latest and st.texts[st.latest] or nil
end

function M.progress()
  local spinner = { '⣶', '⣧', '⣏', '⡟', '⠿', '⢻', '⣹', '⣼' }
  local idx = 0
  return {
    stl = function(_, args)
      if not args then
        return
      end
      if not progress_busy() then
        return ''
      end
      if args.event == 'LspProgress' then
        idx = idx % #spinner + 1
      end
      return spinner[math.max(idx, 1)]
    end,
    prepare = track,
    global = true,
    name = 'LspProgress',
    event = { 'LspProgress', 'LspDetach' },
    attr = { link = 'Type' },
  }
end

function M.lsp()
  return {
    stl = function(buf, args)
      local data = args and args.data or {}
      local detaching = args and args.event == 'LspDetach' and args.buf == buf and data.client_id
        or nil

      local names, root, msg = {}, nil, nil
      for _, client in ipairs(lsp.get_clients({ bufnr = buf })) do
        if client.id ~= detaching then
          root = client.root_dir or root
          names[#names + 1] = ('%d_%s'):format(client.id, client.name)
          msg = msg or progress_text(client.id)
        end
      end
      if #names == 0 then
        return ''
      end
      msg = msg
        or ('[%s:%s]'):format(
          root and fnamemodify(root, ':t') or 'single',
          table.concat(names, ',')
        )
      return '   ' .. esc(msg)
    end,
    prepare = track,
    targets = function(args)
      if args.event ~= 'LspProgress' then
        return { args.buf }
      end
      local client = args.data and lsp.get_client_by_id(args.data.client_id)
      return client and vim.tbl_keys(client.attached_buffers or {}) or {}
    end,
    name = 'Lsp',
    event = { 'LspProgress', 'LspAttach', 'LspDetach' },
  }
end

function M.gitinfo()
  local alias = { 'Head', 'plus', 'delta', 'minus' }
  local signs = { 'Git:', '+', '~', '-' }
  local order = { 'head', 'added', 'changed', 'removed' }

  local default_branch
  local waiters = {}

  local function with_default_branch(cb)
    if default_branch ~= nil then
      return cb(default_branch or nil)
    end
    waiters[#waiters + 1] = cb
    if #waiters > 1 then
      return
    end
    local function finish(branch)
      default_branch = branch or false
      local list = waiters
      waiters = {}
      for _, f in ipairs(list) do
        f(branch)
      end
    end
    local ok = pcall(
      vim.system,
      { 'git', 'config', '--get', 'init.defaultBranch' },
      { text = true },
      function(res)
        local out = res.code == 0 and vim.trim(res.stdout or '') or ''
        vim.schedule(function()
          finish(out ~= '' and out or nil)
        end)
      end
    )
    if not ok then
      finish(nil)
    end
  end

  local function format_git(dict, head)
    local parts = {}
    for i = 1, 4 do
      local v = i == 1 and esc(head) or dict[order[i]]
      if i == 1 or (type(v) == 'number' and v > 0) then
        parts[#parts + 1] = ('%%#@diff.%s#%s%s%%*'):format(alias[i], signs[i], v)
      end
    end
    return ' ' .. table.concat(parts, ' ')
  end

  return {
    stl = function(buf, _, done, guard)
      local dict = vim.b[buf].gitsigns_status_dict
      if type(dict) ~= 'table' or next(dict) == nil then
        return done('')
      end
      if dict.head and dict.head ~= '' then
        return done(format_git(dict, dict.head))
      end
      with_default_branch(guard(function(branch)
        done(format_git(dict, branch or ''))
      end))
    end,
    targets = function(args)
      return { args.data and args.data.buffer or args.buf }
    end,
    async = true,
    name = 'git',
    event = { 'User GitSignsUpdate', 'BufEnter' },
  }
end

function M.diagnostic()
  local names = { 'Error', 'Warn', 'Info' }
  return {
    stl = function(buf, args)
      local detaching = args and args.event == 'LspDetach' and args.data and args.data.client_id
      local has_client = false
      for _, client in ipairs(lsp.get_clients({ bufnr = buf })) do
        if client.id ~= detaching then
          has_client = true
          break
        end
      end
      if not has_client or not diagnostic.is_enabled({ bufnr = buf }) then
        return ''
      end
      local counts = diagnostic.count(buf)
      local t = {}
      for i = 1, 3 do
        t[i] = ('%%#Diagnostic%s#%d%%*'):format(names[i], counts[i] or 0)
      end
      return (' [%s]'):format(table.concat(t, ' '))
    end,
    init = function(refresh)
      local enable = diagnostic.enable
      if type(enable) ~= 'function' then
        return
      end
      diagnostic.enable = function(...)
        local ret = enable(...)
        vim.schedule(refresh)
        return ret
      end
    end,
    label = 'diagnostic',
    event = { 'DiagnosticChanged', 'LspAttach', 'LspDetach' },
  }
end

local function symbol_range(sym)
  return sym.range or (sym.location and sym.location.range)
end

local function find_symbol(symbols, line)
  local best, best_span
  for _, sym in ipairs(symbols) do
    local r = symbol_range(sym)
    if r and line >= r.start.line and line <= r['end'].line then
      local span = r['end'].line - r.start.line
      if not best or span < best_span then
        best, best_span = sym, span
      end
    end
  end
  if best and type(best.children) == 'table' then
    return find_symbol(best.children, line) or best
  end
  return best
end

function M.document_symbol()
  local method = 'textDocument/documentSymbol'
  return {
    stl = function(buf, _, done, guard)
      if #lsp.get_clients({ bufnr = buf, method = method }) == 0 then
        return done('')
      end
      local win = buf == api.nvim_get_current_buf() and api.nvim_get_current_win()
        or vim.fn.bufwinid(buf)
      if win == -1 then
        return
      end
      local line = api.nvim_win_get_cursor(win)[1] - 1
      local params = { textDocument = lsp.util.make_text_document_params(buf) }
      lsp.buf_request_all(
        buf,
        method,
        params,
        guard(function(results)
          if not api.nvim_buf_is_valid(buf) then
            return
          end
          for _, res in pairs(results or {}) do
            local result = res.result
            if not (res.err or res.error) and type(result) == 'table' then
              local sym = find_symbol(result, line)
              if sym then
                return done((' %s '):format(esc(sym.name)))
              end
            end
          end
          done('')
        end)
      )
    end,
    async = true,
    name = 'DocumentSymbol',
    event = { 'CursorHold' },
  }
end
M.doucment_symbol = M.document_symbol

return M
