-- ~/.config/nvim/init.lua  (tracked in ~/dotfiles/config/nvim, symlinked by bootstrap.sh)
-- Minimal kickstart for nvim 0.12+ (vim.pack)

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Plugins (nvim 0.12+ native package manager)
vim.pack.add({
  { src = "https://github.com/projekt0n/github-nvim-theme", name = "github-nvim-theme" },
  { src = "https://github.com/MeanderingProgrammer/render-markdown.nvim", name = "render-markdown.nvim" },
})

require("github-theme").setup({})
vim.cmd.colorscheme("github_dark_dimmed")

-- In-buffer markdown rendering. Uses the markdown / markdown_inline treesitter
-- parsers bundled with nvim 0.12; no nvim-treesitter needed.
-- Toggle per buffer with :RenderMarkdown toggle (mapped to <leader>m below).
require("render-markdown").setup({
  completions = { lsp = { enabled = true } },
  -- Optional parsers nvim does not bundle; off so :checkhealth stays clean.
  html = { enabled = false },
  -- LaTeX: converted to unicode by pylatexenc. Single-line formulas render
  -- in place (position = 'center'); multi-line blocks render as virtual
  -- lines above. Needs the latex treesitter parser, which nvim does not
  -- bundle. Both the parser and the converter come from
  -- ~/dotfiles/install/install-nvim.sh: the converter lives in a pinned venv
  -- (~/.local/share/nvim-latex/venv), symlinked to ~/.local/bin/latex2text so
  -- no project env can shadow it.
  latex = { enabled = true },
  yaml = { enabled = false },
  -- Nerd Font glyphs are the upstream default. If headings, bullets or
  -- checkboxes show up as empty boxes, the terminal font lacks them: swap the
  -- two blocks below for the ASCII fallback.
  -- heading = { icons = { "# ", "## ", "### ", "#### ", "##### ", "###### " } },
  -- bullet  = { icons = { "-", "*", "+" } },
  -- checkbox = { unchecked = { icon = "[ ]" }, checked = { icon = "[x]" } },
})

local o = vim.opt
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true
o.wrap = false
o.scrolloff = 8
o.sidescrolloff = 8
o.ignorecase = true
o.smartcase = true
o.termguicolors = true
o.undofile = true
o.updatetime = 250
o.timeoutlen = 400
o.splitbelow = true
o.splitright = true
o.mouse = "a"
o.clipboard = "unnamedplus"

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "sh", "bash" },
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
  end,
})

local map = vim.keymap.set
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
map("n", "<leader>e", "<cmd>Explore<cr>", { desc = "File explorer" })
map("n", "<leader>m", "<cmd>RenderMarkdown toggle<cr>", { desc = "Toggle markdown rendering" })
map("n", "<esc>", "<cmd>nohlsearch<cr>")

-- Ctrl-j / Ctrl-k move the cursor 10 lines at a time. scrolloff = 8 keeps the
-- cursor off the edge, so the view follows. Swap "10j"/"10k" for "10<C-e>"/"10<C-y>"
-- to scroll the window and leave the cursor where it is.
map({ "n", "x" }, "<C-j>", "10j", { desc = "Down 10 lines" })
map({ "n", "x" }, "<C-k>", "10k", { desc = "Up 10 lines" })
map("n", "<leader>ff", ":find **/", { desc = "Find file" })
map("n", "<leader>fg", ":vimgrep //j **/*<left><left><left><left><left><left><left>", { desc = "Grep" })
map("n", "<leader>f", function() vim.lsp.buf.format({ async = false }) end, { desc = "Format buffer" })

vim.lsp.enable({ "pylsp", "ruff", "bashls" })

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local b = { buffer = ev.buf }
    map("n", "gd", vim.lsp.buf.definition, b)
    map("n", "gD", vim.lsp.buf.declaration, b)
    map("n", "gr", vim.lsp.buf.references, b)
    map("n", "gi", vim.lsp.buf.implementation, b)
    map("n", "K", vim.lsp.buf.hover, b)
    map("n", "<leader>rn", vim.lsp.buf.rename, b)
    map("n", "<leader>ca", vim.lsp.buf.code_action, b)
    map("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, b)
    map("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, b)

    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
  end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.py" },
  callback = function() vim.lsp.buf.format({ async = false, name = "ruff" }) end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "*.sh", "*.bash" },
  callback = function()
    local file = vim.fn.expand("%:p")
    vim.fn.system({ "shfmt", "-i", "2", "-ci", "-w", file })
    vim.cmd("edit!")
  end,
})

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})
