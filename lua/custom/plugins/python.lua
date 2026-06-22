-- Python debugging adapter (debugpy via nvim-dap-python).
--
-- kickstart's `kickstart.plugins.debug` loads nvim-dap + dap-ui but only
-- wires Go (delve). This registers the `python` DAP adapter so that both
-- <F5> debugging and neotest's "debug nearest test" (<leader>Td) work.
--
-- Interpreter resolution follows the uv workflow: the project's
-- `.venv/bin/python` (which must contain `debugpy`, e.g. `uv add --dev debugpy`)
-- is used when present, falling back to the system python3 otherwise.

vim.pack.add { 'https://github.com/mfussenegger/nvim-dap-python' }

local function venv_python()
  local venv = vim.fn.getcwd() .. '/.venv/bin/python'
  if vim.fn.executable(venv) == 1 then
    return venv
  end
  return vim.fn.exepath 'python3'
end

local dap_python = require 'dap-python'
dap_python.setup(venv_python())
-- Resolve the debuggee interpreter at launch time (cwd-relative), so opening a
-- different uv project in the same session still targets the right .venv.
dap_python.resolve_python = venv_python
dap_python.test_runner = 'pytest'
