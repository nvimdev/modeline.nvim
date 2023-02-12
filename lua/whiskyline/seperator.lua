local sp = {}
local fg = '#363646'

function sp.sep()
  return {
    stl = ' ',
    name = 'sep',
    attr = {
      background = 'NONE',
      foreground = 'NONE',
    },
  }
end

function sp.l_left()
  return {
    stl = '',
    name = 'sepleft',
    attr = {
      background = 'NONE',
      foreground = fg,
    },
  }
end

function sp.l_right()
  return {
    stl = '',
    name = 'sepleft',
    attr = {
      background = 'NONE',
      foreground = fg,
    },
  }
end

function sp.r_left()
  return {
    stl = '',
    name = 'sepleft',
    attr = {
      background = 'NONE',
      foreground = fg,
    },
  }
end

function sp.r_right()
  return {
    stl = '',
    name = 'sepleft',
    attr = {
      background = 'NONE',
      foreground = fg,
    },
  }
end

return sp
