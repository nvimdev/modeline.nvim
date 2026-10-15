local api = vim.api
local p = require('modeline.provider')

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

local enc_mnemonic = coding_mnemonic(vim.o.encoding)

local function coding_system(buf)
  local bo = vim.bo[buf]
  local fenc, ff = bo.fileencoding, bo.fileformat
  local eol = ff == 'dos' and '\\' or ff == 'mac' and '/' or ':'
  return (fenc ~= '' and coding_mnemonic(fenc) or enc_mnemonic) .. enc_mnemonic .. eol
end

_G.modeline = _G.modeline or {}

function _G.modeline.coding_system()
  return coding_system(0)
end

local function stl_format(name, val)
  return ('%%#ModeLine%s#%s%%*'):format(name, val)
end

local function coding()
  return {
    stl = function(buf)
      return ' ' .. coding_system(buf)
    end,
    targets = function(args)
      return { args.event == 'OptionSet' and api.nvim_get_current_buf() or args.buf }
    end,
    event = {
      'BufReadPost', -- 包括 :e ++enc=xxx 重读
      'BufWritePost',
      'OptionSet fileencoding,fileformat',
    },
    label = 'coding',
  }
end

local function default()
  local comps = {
    -- [[%#ModeLineMode#%{v:lua.ml_mode()}%*]],
    coding(),
    "%{&readonly?(&modified?'%*':'%%'):(&modified?'**':'--')}-",
    '  T%{tabpagenr()} %#ModeLineFileName#%t%*',
    '  %P  L%-5lC%-5c    ',
    p.gitinfo(),
    ' %=',
    [[%{(bufname() !=# '' && &bt !=# 'terminal' ? '(' : '')}]],
    "%{( &ft ==# 'cpp' ? 'C++' : toupper(strpart(&ft, 0, 1)) . strpart(&ft, 1)) }",
    p.diagnostic(),
    [[%{(bufname() !=# '' && &bt !=# 'terminal' ? ')' : '')}]],
    p.progress(),
    p.lsp(),
    '%=%=',
  }

  local events = {}
  for idx, item in ipairs(comps) do
    if type(item) == 'table' then
      for _, event in ipairs(item.event or {}) do
        events[event] = events[event] or {}
        table.insert(events[event], idx)
      end
    end
  end
  return comps, events
end

local function apply_highlights(comps)
  for _, item in ipairs(comps) do
    if type(item) == 'table' and item.attr and item.name then
      api.nvim_set_hl(
        0,
        'ModeLine' .. item.name,
        vim.tbl_extend('force', { default = true }, item.attr)
      )
    end
  end
end

--- 状态：组件值按 buffer 缓存（global 组件共用一份），
--- 每个窗口渲染时取自己 buffer 的结果，所以多窗口时各显示各的。
local function make_modeline(comps, events)
  local global, bufs = {}, {} -- 已格式化的组件值：global[idx]、bufs[buf][idx]
  local defaults = {}
  local filled, filling = {}, {} -- 已初始化 / 等待初始化的 buffer
  local cache_str, cache_ver = {}, {} -- 每个 buffer 拼好的整串
  local global_ver = 0
  local gen, failed = {}, {}
  local pending = false
  local ls3 = vim.o.laststatus == 3
  local last_win

  local function label(idx)
    return comps[idx].name or comps[idx].label or ('#' .. idx)
  end

  local function report(name, err)
    if failed[name] then
      return
    end
    failed[name] = true
    vim.schedule(function()
      vim.notify(('[ModeLine] %s failed: %s'):format(name, err), vim.log.levels.ERROR)
    end)
  end

  local function format(idx, val)
    local name = comps[idx].name
    return (name and val ~= '') and stl_format(name, val) or val
  end

  for idx, item in ipairs(comps) do
    if type(item) == 'table' and item.default then
      defaults[idx] = format(idx, item.default)
    end
  end

  local function redraw()
    local mode = api.nvim_get_mode().mode
    if mode:sub(1, 1) == 'r' or vim.fn.pumvisible() == 1 then
      vim.defer_fn(redraw, 100)
      return
    end
    pending = false
    pcall(vim.cmd.redrawstatus, { bang = true })
  end

  local function request_redraw()
    if not pending then
      pending = true
      vim.schedule(redraw)
    end
  end

  local function update(idx, buf, val)
    if val == nil then
      return
    end
    local s = format(idx, val)
    if buf == nil then
      if global[idx] == s then
        return
      end
      global[idx] = s
      global_ver = global_ver + 1
    else
      if not filled[buf] then
        return
      end
      local vals = bufs[buf]
      if not vals then
        vals = {}
        bufs[buf] = vals
      end
      if vals[idx] == s then
        return
      end
      vals[idx] = s
      cache_str[buf] = nil
    end
    request_redraw()
  end

  local function guard(name, fn)
    return function(...)
      local ok, err = pcall(fn, ...)
      if not ok then
        report(name, err)
      end
    end
  end

  local function run(idx, buf, args)
    local c = comps[idx]
    if not c.async then
      return update(idx, buf, c.stl(buf, args))
    end
    local g = gen[idx] or {}
    gen[idx] = g
    local key = buf or 0
    local id = (g[key] or 0) + 1
    g[key] = id
    c.stl(buf, args, function(val)
      if g[key] == id then
        update(idx, buf, val)
      end
    end, function(fn)
      return guard(label(idx), fn)
    end)
  end

  local function safe_run(idx, buf, args)
    local ok, err = pcall(run, idx, buf, args)
    if not ok then
      report(label(idx), err)
    end
  end

  local function refresh(only_idx, only_buf)
    for idx, c in ipairs(comps) do
      if type(c) == 'table' and (only_idx == nil or only_idx == idx) then
        if c.global then
          if only_buf == nil then
            safe_run(idx, nil, nil)
          end
        elseif only_buf then
          if filled[only_buf] then
            safe_run(idx, only_buf, nil)
          end
        else
          for buf in pairs(filled) do
            safe_run(idx, buf, nil)
          end
        end
      end
    end
  end

  local function dispatch(idx, args)
    local c = comps[idx]
    if c.prepare then
      c.prepare(args)
    end
    if c.cond and c.cond(args) == false then
      return
    end
    if c.global then
      return run(idx, nil, args)
    end
    for _, buf in ipairs(c.targets and c.targets(args) or { args.buf }) do
      if filled[buf] then
        run(idx, buf, args)
      end
    end
  end

  local function on_event(key, args)
    for _, idx in ipairs(events[key] or {}) do
      local ok, err = pcall(dispatch, idx, args)
      if not ok then
        report(label(idx), err)
      end
    end
  end

  local function fill(buf)
    if filled[buf] or filling[buf] then
      return
    end
    filling[buf] = true
    vim.schedule(function()
      filling[buf] = nil
      if api.nvim_buf_is_valid(buf) then
        filled[buf] = true
        refresh(nil, buf)
      end
    end)
  end

  local function target_buf()
    if ls3 then
      local win = api.nvim_get_current_win()
      if
        win ~= last_win
        and last_win
        and api.nvim_win_is_valid(last_win)
        and api.nvim_win_get_config(win).relative ~= ''
      then
        return api.nvim_win_get_buf(last_win)
      end
    end
    return api.nvim_get_current_buf()
  end

  local function build(buf)
    local vals = bufs[buf] or {}
    local out = {}
    for idx, item in ipairs(comps) do
      if type(item) == 'string' then
        out[idx] = item
      elseif item.global then
        out[idx] = global[idx] or defaults[idx] or ''
      else
        out[idx] = vals[idx] or defaults[idx] or ''
      end
    end
    return table.concat(out)
  end

  local function render()
    local buf = target_buf()
    fill(buf)
    if cache_str[buf] and cache_ver[buf] == global_ver then
      return cache_str[buf]
    end
    local s = build(buf)
    cache_str[buf], cache_ver[buf] = s, global_ver
    return s
  end

  local fallback = build(-1)

  return {
    on_event = on_event,
    refresh = refresh,
    render = function()
      local ok, res = pcall(render)
      if ok then
        return res
      end
      report('render', res)
      return fallback
    end,
    cleanup = function(buf)
      bufs[buf], filled[buf], filling[buf] = nil, nil, nil
      cache_str[buf], cache_ver[buf] = nil, nil
      for _, g in pairs(gen) do
        g[buf] = nil
      end
    end,
    set_laststatus = function(v)
      ls3 = v == 3
    end,
    win_enter = function()
      local win = api.nvim_get_current_win()
      if api.nvim_win_get_config(win).relative == '' then
        last_win = win
      end
    end,
  }
end

return {
  setup = function()
    if did_setup then
      return
    end
    did_setup = true

    local comps, events = default()
    local ml = make_modeline(comps, events)
    local group = api.nvim_create_augroup('ModeLine', { clear = true })

    local function autocmd(event, opts)
      opts.group = group
      api.nvim_create_autocmd(event, opts)
    end

    apply_highlights(comps)
    autocmd('ColorScheme', {
      callback = function()
        apply_highlights(comps)
      end,
      desc = '[ModeLine] restore highlights',
    })
    autocmd('OptionSet', {
      pattern = 'laststatus',
      callback = function()
        ml.set_laststatus(vim.o.laststatus)
      end,
      desc = '[ModeLine] track laststatus',
    })
    autocmd('WinEnter', {
      callback = function()
        ml.win_enter()
      end,
      desc = '[ModeLine] track last normal window',
    })
    autocmd('BufWipeout', {
      callback = function(args)
        ml.cleanup(args.buf)
      end,
      desc = '[ModeLine] cleanup',
    })

    for key in pairs(events) do
      local event, pattern = key:match('^(%S+)%s+(%S+)$')
      autocmd(event or key, {
        pattern = pattern and vim.split(pattern, ',') or nil,
        callback = function(args)
          ml.on_event(key, args)
        end,
        desc = '[ModeLine] update',
      })
    end

    for idx, item in ipairs(comps) do
      if type(item) == 'table' and item.init then
        item.init(function(buf)
          ml.refresh(idx, buf)
        end)
      end
    end

    ml.win_enter()
    _G.modeline.render = ml.render
    vim.g.ModelineRender = ml.render
    vim.go.statusline = '%{%g:ModelineRender()%}'
  end,
}
