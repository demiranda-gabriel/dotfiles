return {
  cmd = { "bash-language-server", "start" },
  filetypes = { "sh", "bash" },
  root_markers = { ".git" },
  settings = {
    bashIde = {
      -- Uses shellcheck on PATH
      shellcheckPath = "shellcheck",
      shfmt = {
        path = "shfmt",
      },
    },
  },
}
