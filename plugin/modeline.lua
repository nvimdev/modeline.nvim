if vim.g.loaded_modeline then
  return
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'BufNewFile' }, {
  callback = function()
    require('modeline').setup()
  end,
})
