local api, lsp, diagnostic, M = vim.api, vim.lsp, vim.diagnostic, {}
local fnamemodify = vim.fn.fnamemodify

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
  local m = mode_alias[mode] or mode_alias[string.sub(mode, 1, 1)] or 'UNK'
  return m:sub(1, 3):upper()
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
    attr = { link = 'Type' },
  }
end

function M.lsp()
  return {
    stl = function(args)
      local clients = lsp.get_clients({ bufnr = 0 })
      if #clients == 0 then
        return ''
      end
      local root_dir = 'single'
      local client_names = vim
        .iter(clients)
        :map(function(client)
          if args.event == 'LspDetach' and client.id == args.data.client_id then
            return nil
          end

          if client.root_dir then
            root_dir = client.root_dir
          end
          return ('%d_%s'):format(client.id, client.name)
        end)
        :totable()

      local msg = ('[%s:%s]'):format(
        root_dir ~= 'single' and fnamemodify(root_dir, ':t') or 'single',
        table.concat(client_names, ',')
      )
      if args.data and args.data.params then
        local val = args.data.params.value
        if val.message and val.kind ~= 'end' then
          msg = ('%s %s'):format(val.title, (val.percentage and val.percentage .. '%' or ''))
        end
      end
      return '   %-20s' .. msg
    end,
    name = 'Lsp',
    event = { 'LspProgress', 'LspAttach', 'LspDetach', 'BufEnter' },
  }
end

function M.gitinfo()
  local alias = { 'Head', 'Add', 'Change', 'Delete' }
  return {
    stl = function()
      return coroutine.create(function(pieces, idx)
        local signs = { 'Git:', '+', '~', '-' }
        local order = { 'head', 'added', 'changed', 'removed' }

        local ok, dict = pcall(api.nvim_buf_get_var, 0, 'gitsigns_status_dict')
        if not ok or vim.tbl_isempty(dict) then
          return ''
        end
        if dict['head'] == '' then
          local co = coroutine.running()
          vim.system(
            { 'git', 'config', '--get', 'init.defaultBranch' },
            { text = true },
            function(result)
              coroutine.resume(co, #result.stdout > 0 and vim.trim(result.stdout) or nil)
            end
          )
          dict['head'] = coroutine.yield()
        end
        local parts = ''
        for i = 1, 4 do
          if i == 1 or (type(dict[order[i]]) == 'number' and dict[order[i]] > 0) then
            parts = ('%s %s'):format(
              parts,
              ('%%#Diff%s#%s%%*'):format(alias[i], signs[i] .. dict[order[i]])
            )
          end
        end
        pieces[idx] = parts
      end)
    end,
    async = true,
    name = 'git',
    event = { 'User GitSignsUpdate', 'BufEnter' },
  }
end

function M.diagnostic()
  return {
    stl = function()
      if not vim.diagnostic.is_enabled({ bufnr = 0 }) or #lsp.get_clients({ bufnr = 0 }) == 0 then
        return ''
      end
      local t = {}
      for i = 1, 3 do
        local count = #diagnostic.get(0, { severity = i })
        t[#t + 1] = ('%%#Diagnostic%s#%s%%*'):format(vim.diagnostic.severity[i], count)
      end
      return (' [%s]'):format(table.concat(t, ' '))
    end,
    cond = function()
      return tonumber(vim.fn.pumvisible()) == 0
    end,
    event = { 'DiagnosticChanged', 'BufEnter', 'LspAttach', 'LspDetach' },
  }
end

---@private
local function binary_search(tbl, line)
  local left = 1
  local right = #tbl
  local mid = 0

  while true do
    mid = bit.rshift(left + right, 1)
    if not tbl[mid] then
      return
    end

    local range = tbl[mid].range or tbl[mid].location.range
    if not range then
      return
    end

    if line >= range.start.line and line <= range['end'].line then
      return mid
    elseif line < range.start.line then
      right = mid - 1
    else
      left = mid + 1
    end
    if left > right then
      return
    end
  end
end

function M.doucment_symbol()
  return {
    stl = function()
      return coroutine.create(function(pieces, idx)
        local params = { textDocument = lsp.util.make_text_document_params() }
        local co = coroutine.running()
        lsp.buf_request(0, 'textDocument/documentSymbol', params, function(err, result, ctx)
          if err or not api.nvim_buf_is_loaded(ctx.bufnr) then
            return
          end
          local lnum = api.nvim_win_get_cursor(0)[1]
          local mid = binary_search(result, lnum)
          if not mid then
            return
          end
          coroutine.resume(co, result[mid])
        end)
        local data = coroutine.yield()
        pieces[idx] = (' %s '):format(data.name)
      end)
    end,
    async = true,
    name = 'DocumentSymbol',
    event = { 'CursorHold' },
  }
end

return M
