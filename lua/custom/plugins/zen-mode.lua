-- Distraction-free editing (folke/zen-mode.nvim).
-- Centers the buffer in a clean window and hides UI chrome — handy for prose
-- (markdown) and focused coding. Toggle with <leader>z.

vim.pack.add { 'https://github.com/folke/zen-mode.nvim' }

require('zen-mode').setup {
  window = {
    backdrop = 0.95, -- dim everything behind the zen window (0-1)
    width = 90, -- columns; comfortable for prose and code
    height = 1, -- full height
    options = {
      number = true, -- keep line numbers in zen mode
      relativenumber = true, -- hybrid relative numbers in zen mode too
      signcolumn = 'no',
      cursorline = false,
      foldcolumn = '0',
      list = false,
    },
  },
  plugins = {
    -- Disable some global UI while zen is active; restored on exit.
    options = { enabled = true, ruler = false, showcmd = false, laststatus = 0 },
    gitsigns = { enabled = false }, -- hide git signs in the gutter
  },
}

vim.keymap.set('n', '<leader>z', '<cmd>ZenMode<cr>', { desc = 'Toggle [Z]en Mode' })
