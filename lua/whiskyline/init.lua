local co, api = coroutine, vim.api
local whk = {}

local function stl_format(name, val)
  return '%#Whisky' .. name .. '#' .. val .. '%*'
end

local function stl_hl(name, attr)
  api.nvim_set_hl(0, 'Whisky' .. name, attr)
end

local function default()
  local p = require('whiskyline.provider')
  local s = require('whiskyline.separator')
  local comps = {
    -- p.mode(),
    s.space(),
    p.encoding(),
    p.eol(),
    p.modified(),
    s.space(),
    --
    p.fileicon(),
    p.fileinfo(),
    s.space(),
    p.lnumcol(),
    s.pad(),
    p.diagError(),
    p.diagWarn(),
    p.diagInfo(),
    p.diagHint(),
    s.pad(),
    --
    p.lsp(),
    s.space(),
    p.gitadd(),
    p.gitchange(),
    p.gitdelete(),
    p.branch(),
    --
  }
  local e, pieces = {}, {}
  vim.iter(comps):map(function(item)
    if type(item.stl) == 'string' then
      pieces[#pieces + 1] = stl_format(item.name, item.stl)
    else
      pieces[#pieces + 1] = item.default and stl_format(item.name, item.default) or ''
    end
    if item.attr and item.name then
      stl_hl(item.name, item.attr)
    end

    for _, event in ipairs({ unpack(item.event or {}) }) do
      e[#e + 1] = not vim.tbl_contains(e, event) and event or nil
    end
  end)
  return comps, e, pieces
end

local function render(comps, pieces)
  return co.create(function(args)
    while true do
      for i, item in ipairs(comps) do
        if
          item.event
          and vim.tbl_contains(
            item.event,
            (args.event == 'User' and args.event .. ' ' .. args.match or args.event)
          )
          and type(item.stl) == 'function'
        then
          pieces[i] = stl_format(item.name, item.stl(args))
        end
      end
      vim.opt.stl = table.concat(pieces)
      args = co.yield()
    end
  end)
end

function whk.setup()
  vim.defer_fn(function()
    local comps, events, pieces = default()
    local stl_render = render(comps, pieces)
    for _, e in ipairs(events) do
      local tmp = e
      local pattern
      if e:find('User') then
        pattern = vim.split(e, '%s')[2]
      end

      api.nvim_create_autocmd(tmp, {
        pattern = pattern,
        callback = function(args)
          vim.schedule(function()
            local ok, res = co.resume(stl_render, args)
            if not ok then
              vim.notify('[Whisky] render failed ' .. res, vim.log.levels.ERROR)
            end
          end)
        end,
      })
    end
  end, 0)
end

return whk
