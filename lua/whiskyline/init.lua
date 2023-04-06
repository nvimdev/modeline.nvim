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
  local s = require('whiskyline.seperator')
  return {
    --
    s.l_left,
    p.mode,
    s.l_right,
    --
    s.sep,
    --
    s.l_left,
    p.fileicon,
    p.fileinfo,
    s.l_right,
    --
    s.sep,
    --
    s.l_left,
    p.lnumcol,
    s.l_right,
    --
    s.sep,
    --
    p.pad,
    p.diagError,
    p.diagWarn,
    p.diagInfo,
    p.diagHint,
    p.pad,
    --
    s.sep,
    --
    s.r_left,
    p.lsp,
    s.r_right,
    s.sep,
    --
    s.r_left,
    p.gitadd,
    p.gitchange,
    p.gitdelete,
    p.branch,
    s.r_right,
    --
    s.sep,
    --
    s.r_left,
    p.encoding,
    s.r_right,
  }
end

local function whk_init(event, pieces)
  whk.cache = {}
  for i, e in ipairs(whk.elements) do
    local res = e()
    if type(res.stl) == 'string' then
      pieces[#pieces + 1] = stl_format(res.name, res.stl)
    else
      if res.event and vim.tbl_contains(res.event, event) then
        local val = type(res.stl) == 'function' and res.stl() or res.stl
        pieces[#pieces + 1] = stl_format(res.name, val)
      else
        pieces[#pieces + 1] = stl_format(res.name, '')
      end
    end
    if res.attr then
      stl_hl(res.name, res.attr)
    end
    whk.cache[i] = {
      event = res.event,
      name = res.name,
      stl = res.stl,
    }
  end
  require('whiskyline.provider').initialized = true
  return table.concat(pieces, '')
end

local stl_render = co.create(function(event)
  local pieces = {}
  while true do
    if not whk.cache then
      whk_init(event, pieces)
    else
      for i, item in ipairs(whk.cache) do
        if item.event and vim.tbl_contains(item.event, event) and type(item.stl) == 'function' then
          local comp = whk.elements[i]
          local res = comp()
          if res.attr then
            stl_hl(item.name, res.attr)
          end
          pieces[i] = stl_format(item.name, res.stl())
        end
      end
    end
    vim.opt.stl = table.concat(pieces)
    event = co.yield()
  end
end)

function whk.setup(param)
  param = param or { bg = '#01394a' }
  whk.bg = param.bg
  whk.elements = default()

  api.nvim_create_autocmd({ 'User' }, {
    pattern = { 'LspProgressUpdate', 'GitSignsUpdate' },
    callback = function(opt)
      if opt.event == 'User' then
        opt.event = opt.match
      end
      vim.schedule(function()
        co.resume(stl_render, opt.event)
      end)
    end,
  })

  local events = { 'DiagnosticChanged', 'ModeChanged', 'BufEnter', 'BufWritePost', 'LspAttach' }
  api.nvim_create_autocmd(events, {
    callback = function(opt)
      vim.schedule(function()
        co.resume(stl_render, opt.event)
      end)
    end,
  })
end

return whk
