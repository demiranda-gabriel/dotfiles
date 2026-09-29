return {
  cmd = { "pylsp" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
  settings = {
    pylsp = {
      plugins = {
        -- Defer linting+formatting to ruff
        pycodestyle = { enabled = false },
        pyflakes = { enabled = false },
        mccabe = { enabled = false },
        pylint = { enabled = false },
        flake8 = { enabled = false },
        autopep8 = { enabled = false },
        yapf = { enabled = false },
        black = { enabled = false },
        -- Keep navigation + completion
        jedi_completion = { enabled = true, fuzzy = true },
        jedi_definition = { enabled = true },
        jedi_hover = { enabled = true },
        jedi_references = { enabled = true },
        jedi_signature_help = { enabled = true },
        jedi_symbols = { enabled = true, all_scopes = true },
      },
    },
  },
}
