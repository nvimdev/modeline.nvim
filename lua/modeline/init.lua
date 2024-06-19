local co, api, iter = coroutine, vim.api, vim.iter

local function stl_format(name, val)
  return '%#ModeLine' .. name .. '#' .. val .. '%*'
end

local function default()
  local p = require('modeline.provider')
  local pad = '%='
  local space = ' '
  local comps = {
    p.mode(),
    space,
    p.encoding(),
    p.eol(),
    p.modified(),
    space,
    space,
    --
    p.fileinfo(),
    space,
    p.lnumcol(),
    space,
    space,
    p.gitinfo('head'),
    p.gitinfo('added'),
    p.gitinfo('changed'),
    p.gitinfo('removed'),
    space,
    pad,
    p.diagnostic(vim.diagnostic.severity.E),
    p.diagnostic(vim.diagnostic.severity.W),
    p.diagnostic(vim.diagnostic.severity.I),
    p.diagnostic(vim.diagnostic.severity.N),
    p.progress(),
    space,
    p.lsp(),
    pad,
  }
  local e, pieces = {}, {}
  iter(ipairs(comps))
    :map(function(key, item)
      if type(item) == 'string' then
        pieces[#pieces + 1] = stl_format('Padding', item)
      elseif type(item.stl) == 'string' then
        pieces[#pieces + 1] = stl_format(item.name, item.stl)
      else
        pieces[#pieces + 1] = item.default and stl_format(item.name, item.default) or ''
        for _, event in ipairs({ unpack(item.event or {}) }) do
          if not e[event] then
            e[event] = {}
          end
          e[event][#e[event] + 1] = key
        end
      end
      if item.attr and item.name then
        api.nvim_set_hl(0, ('ModeLine%s'):format(item.name), item.attr)
      end
    end)
    :totable()
  return comps, e, pieces
end

local function render(comps, events, pieces)
  return co.create(function(args)
    while true do
      local event = args.event == 'User' and args.event .. ' ' .. args.match or args.event
      for _, idx in ipairs(events[event]) do
        pieces[idx] = stl_format(comps[idx].name, comps[idx].stl(args))
      end
      vim.opt.stl = table.concat(pieces)
      args = co.yield()
    end
  end)
end

return {
  setup = function()
    --move to next event loop
    --that mean must lazyload this plugin
    vim.defer_fn(function()
      local comps, events, pieces = default()
      local stl_render = render(comps, events, pieces)
      for _, e in ipairs(vim.tbl_keys(events)) do
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
        })
      end
    end, 0)
  end,
}
