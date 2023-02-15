local pd = require('whiskyline.provider')
local sp = {}

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
      foreground = pd.stl_bg(),
    },
  }
end

function sp.l_right()
  return {
    stl = '',
    name = 'sepleft',
    attr = {
      background = 'NONE',
      foreground = pd.stl_bg(),
    },
  }
end

function sp.r_left()
  return {
    stl = '',
    name = 'sepleft',
    attr = {
      background = 'NONE',
      foreground = pd.stl_bg(),
    },
  }
end

function sp.r_right()
  return {
    stl = '',
    name = 'sepleft',
    attr = {
      background = 'NONE',
      foreground = pd.stl_bg(),
    },
  }
end

return sp
