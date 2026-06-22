-- In-editor pytest runner (JetBrains-style test running).
--
-- This kickstart uses `vim.pack` (not lazy.nvim), so we add plugins
-- imperatively with full git URLs and configure them inline — the same
-- style as `lua/kickstart/plugins/debug.lua`.

vim.pack.add {
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/antoinemadec/FixCursorHold.nvim',
  'https://github.com/nvim-neotest/neotest',
  'https://github.com/nvim-neotest/neotest-python',
}

require('neotest').setup {
  adapters = {
    require 'neotest-python' {
      runner = 'pytest',
      -- Debug tests through nvim-dap (adapter registered in python.lua).
      -- justMyCode = false lets you step into library code too.
      dap = { justMyCode = false },
    },
  },
}

local nt = require 'neotest'

-- Tests live under <leader>T ([T]est). <leader>t is kickstart's [T]oggle group.
require('which-key').add { { '<leader>T', group = '[T]est' } }

vim.keymap.set('n', '<leader>Tr', function() nt.run.run() end, { desc = '[T]est: [R]un nearest' })
vim.keymap.set('n', '<leader>Tf', function() nt.run.run(vim.fn.expand '%') end, { desc = '[T]est: run [F]ile' })
vim.keymap.set('n', '<leader>Td', function() nt.run.run { strategy = 'dap' } end, { desc = '[T]est: [D]ebug nearest' })
vim.keymap.set('n', '<leader>Ts', function() nt.summary.toggle() end, { desc = '[T]est: [S]ummary panel' })
vim.keymap.set('n', '<leader>To', function() nt.output.open { enter = true } end, { desc = '[T]est: [O]utput' })
vim.keymap.set('n', '<leader>TS', function() nt.run.stop() end, { desc = '[T]est: [S]top' })
