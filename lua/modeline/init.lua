local co, api, iter = coroutine, vim.api, vim.iter
local p, hl = require('modeline.provider'), api.nvim_set_hl
local did_setup = false
local coding_alias = {
  ['utf-8'] = 'U',
  ['utf8'] = 'U',
  ['latin1'] = '1',
  ['iso-8859-1'] = '1',
}

local function coding_mnemonic(encoding)
  return coding_alias[(encoding or ''):lower()] or '-'
end

_G.modeline = _G.modeline or {}

function _G.modeline.coding_system()
  local fenc = vim.bo.fileencoding
  local enc = vim.o.encoding
  local ff = vim.bo.fileformat
  local file_mnemonic = coding_mnemonic(fenc ~= '' and fenc or enc)
  local process_mnemonic = coding_mnemonic(enc)
  local eol = ff == 'dos' and '\\' or ff == 'mac' and '/' or ':'
  return file_mnemonic .. process_mnemonic .. eol
end

local function stl_format(name, val)
  return ('%%#ModeLine%s#%s%%*'):format(name, val)
end

local function default()
  local comps = {
    -- [[%#ModeLineMode#%{v:lua.ml_mode()}%*]],
    ' %{v:lua.modeline.coding_system()}',
    "%{&readonly?(&modified?'%*':'%%'):(&modified?'**':'--')}-",
    '  T%{tabpagenr()} %#ModeLineFileName#%t%*',
    "  %P  %{printf('L%-5dC%-5d', line('.'), col('.'))}    ",
    p.gitinfo(),
    ' %=',
    [[%{(bufname() !=# '' && &bt != 'terminal' ? '(' : '')}]],
    "%{( &ft == 'cpp' ? 'C++' : toupper(strpart(&ft, 0, 1)) . strpart(&ft, 1)) }",
    p.diagnostic(),
    [[%{(bufname() !=# '' && &bt != 'terminal' ? ')' : '')}]],
    p.progress(),
    p.lsp(),
    '%=%=',
  }

  local e, pieces = {}, {}
  iter(ipairs(comps))
    :map(function(key, item)
      if type(item) == 'string' then
        pieces[#pieces + 1] = item
      else
        pieces[#pieces + 1] = item.default and item.name and stl_format(item.name, item.default)
          or ''
        for _, event in ipairs({ unpack(item.event or {}) }) do
          e[event] = e[event] or {}
          e[event][#e[event] + 1] = key
        end
      end
      if item.attr and item.name then
        hl(0, ('ModeLine%s'):format(item.name), item.attr)
      end
    end)
    :totable()
  return comps, e, pieces
end

local function render(comps, events, pieces)
  return co.create(function(args)
    while true do
      local event = args.event == 'User' and ('%s %s'):format(args.event, args.match) or args.event
      for _, idx in ipairs(events[event]) do
        if comps[idx].cond and comps[idx].cond() == false then
          goto continue
        end
        if comps[idx].async then
          local child = comps[idx].stl()
          coroutine.resume(child, pieces, idx)
        else
          pieces[idx] = stl_format(comps[idx].name, comps[idx].stl(args))
        end
        ::continue::
      end
      vim.opt.stl = table.concat(pieces)
      args = co.yield()
    end
  end)
end

return {
  setup = function()
    if did_setup then
      return
    end
    did_setup = true
    local comps, events, pieces = default()
    local stl_render = render(comps, events, pieces)
    iter(vim.tbl_keys(events)):map(function(e)
      local tmp = e
      local pattern
      if e:find('User') then
        pattern = vim.split(e, '%s')[2]
        tmp = 'User'
      end
      api.nvim_create_autocmd(tmp, {
        pattern = pattern,
        callback = function(args)
          vim.schedule(function()
            local ok, res = co.resume(stl_render, args)
            if not ok then
              vim.notify('[ModeLine] render failed ' .. res, vim.log.levels.ERROR)
            end
          end)
        end,
        desc = '[ModeLine] update',
      })
    end)
  end,
}
