-- Neovim config (dotfiles/config/nvim/init.lua), aimed at Python work.
--
-- Plugins come from nvim 0.12's built-in manager (vim.pack); the pinned
-- revisions live in nvim-pack-lock.json beside this file. First start clones
-- them into ~/.local/share/nvim/site/pack/core/opt. :lua vim.pack.update()
-- upgrades them.
--
-- External tools, installed by install/install-nvim-python.sh:
--   basedpyright  language server: definition, references, hover, types
--   ruff          lint + format, also served over LSP
--   tree-sitter   parser compiler for nvim-treesitter (gcc shim on old glibc)
--   rg, fzf       fuzzy finder backends for fzf-lua
--   latex2text    render-markdown's LaTeX-to-unicode converter

-- A dead $XDG_RUNTIME_DIR (logind deletes /run/user/$UID on ALCF login nodes;
-- see shell/05-xdg-runtime.sh) breaks serverstart(), which fzf-lua needs.
-- Repair it here too, for nvim started from an older shell or lf session.
do
  local rt = vim.env.XDG_RUNTIME_DIR
  if not rt or not vim.uv.fs_stat(rt) then
    local fallback = '/tmp/xdg-' .. vim.uv.getuid()
    vim.fn.mkdir(fallback, 'p', tonumber('700', 8))
    vim.env.XDG_RUNTIME_DIR = fallback
  end
end

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- ---------------------------------------------------------------- options --
local o = vim.opt
o.number = true
o.relativenumber = true
o.signcolumn = 'yes'
o.cursorline = true
o.termguicolors = true
o.mouse = 'a'
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.softtabstop = 4
o.smartindent = true
o.ignorecase = true
o.smartcase = true
o.undofile = true
o.splitright = true
o.splitbelow = true
o.scrolloff = 8
o.updatetime = 250
o.list = true
o.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- ---------------------------------------------------------------- plugins --
vim.pack.add({
  { src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
  'https://github.com/neovim/nvim-lspconfig',
  { src = 'https://github.com/saghen/blink.cmp', version = vim.version.range('1.*') },
  'https://github.com/ibhagwan/fzf-lua',
  'https://github.com/projekt0n/github-nvim-theme',
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
}, { confirm = false }) -- the list above is the approval; no install prompt

require('github-theme').setup({})
vim.cmd.colorscheme('github_dark_dimmed')

-- -------------------------------------------------------------- treesitter --
-- Parsers compile once, asynchronously, on first start (a few seconds each).
local ts_langs = {
  'python', 'lua', 'bash', 'json', 'yaml', 'toml', 'markdown',
  'markdown_inline', 'vim', 'vimdoc', 'query', 'regex', 'rst',
  'latex', -- needs `tree-sitter generate`; see install/tree-sitter-shim
}
require('nvim-treesitter').install(ts_langs)

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('user_treesitter', { clear = true }),
  callback = function(args)
    local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
    if not lang or not pcall(vim.treesitter.start, args.buf, lang) then
      return -- no parser (yet): legacy syntax highlighting stays on
    end
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo.foldlevel = 99
    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
})

-- --------------------------------------------------------------------- lsp --
-- Nearest .venv above the file wins, so a subpackage with its own
-- pyproject.toml (e.g. software/nequiph/) still resolves imports through the
-- repository-level uv environment. $VIRTUAL_ENV overrides.
local function find_python(start)
  if vim.env.VIRTUAL_ENV then
    return vim.env.VIRTUAL_ENV .. '/bin/python'
  end
  local venv = vim.fs.find('.venv', { upward = true, path = start, type = 'directory' })[1]
  if venv and vim.uv.fs_stat(venv .. '/bin/python') then
    return venv .. '/bin/python'
  end
end

vim.lsp.config('basedpyright', {
  before_init = function(_, config)
    local py = find_python(config.root_dir or vim.fn.getcwd())
    if py then
      -- Mutate in place: the client already holds a reference to this table
      -- and answers workspace/configuration from it; a new table is ignored.
      config.settings = config.settings or {}
      config.settings.python = config.settings.python or {}
      config.settings.python.pythonPath = py
    end
  end,
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = 'standard', -- basedpyright's default 'recommended' is very noisy
        diagnosticMode = 'openFilesOnly',
        autoImportCompletions = true,
      },
    },
  },
})

vim.lsp.config('ruff', {
  on_attach = function(client)
    client.server_capabilities.hoverProvider = false -- basedpyright's hover is richer
  end,
})

vim.lsp.enable({ 'basedpyright', 'ruff' })

vim.diagnostic.config({
  virtual_text = { spacing = 2, source = 'if_many' },
  severity_sort = true,
  float = { border = 'rounded', source = true },
})

-- nvim 0.12 already maps: K hover, grn rename, gra code action, grr references,
-- gri implementation, grt type definition, gO document symbols, <C-s>
-- signature help, [d / ]d diagnostics. Added here:
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('user_lsp', { clear = true }),
  callback = function(args)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = args.buf, desc = desc })
    end
    map('gd', vim.lsp.buf.definition, 'Go to definition')
    map('gD', vim.lsp.buf.declaration, 'Go to declaration')
    map('<leader>e', vim.diagnostic.open_float, 'Line diagnostics')
    map('<leader>cf', function() vim.lsp.buf.format({ name = 'ruff' }) end, 'Format with ruff')
    map('<leader>co', function()
      vim.lsp.buf.code_action({ context = { only = { 'source.organizeImports' } }, apply = true })
    end, 'Organize imports')
  end,
})

-- ------------------------------------------------------------- completion --
require('blink.cmp').setup({
  keymap = { preset = 'default' },  -- <C-space> open, <C-y> accept, <C-n>/<C-p> move
  completion = { documentation = { auto_show = true } },
  signature = { enabled = true },
  sources = { default = { 'lsp', 'path', 'buffer' } },
  -- Pure-Lua matcher: skips the prebuilt Rust library, whose glibc floor
  -- would break on older clusters (the same reason tree-sitter needs a shim).
  fuzzy = { implementation = 'lua' },
})

-- -------------------------------------------------------- markdown view --
-- In-buffer markdown rendering, ported from the FASRC setup (main, ad5f0da).
-- Headings, tables, code blocks and checkboxes render in place; the raw text
-- comes back on the cursor line. Equations: markdown_inline injects `latex`
-- into every $...$ block, and render-markdown converts that tree to unicode
-- with latex2text (install-nvim-python.sh). Single-line formulas render in
-- place, multi-line blocks as virtual lines above. <leader>m toggles.
require('render-markdown').setup({
  completions = { lsp = { enabled = true } },
  html = { enabled = false }, -- optional parsers nvim lacks; keeps :checkhealth clean
  latex = { enabled = true },
  yaml = { enabled = false },
  -- Nerd Font glyphs are the default. If headings, bullets or checkboxes show
  -- as empty boxes, the terminal font lacks them: use the ASCII fallback.
  -- heading = { icons = { '# ', '## ', '### ', '#### ', '##### ', '###### ' } },
  -- bullet  = { icons = { '-', '*', '+' } },
  -- checkbox = { unchecked = { icon = '[ ]' }, checked = { icon = '[x]' } },
})
vim.keymap.set('n', '<leader>m', '<cmd>RenderMarkdown toggle<cr>', { desc = 'Toggle markdown rendering' })

-- ---------------------------------------------------------------- fuzzy ----
local fzf = require('fzf-lua')
fzf.setup({})
vim.keymap.set('n', '<leader>ff', fzf.files, { desc = 'Find files' })
vim.keymap.set('n', '<leader>fg', fzf.live_grep, { desc = 'Live grep' })
vim.keymap.set('n', '<leader>fw', fzf.grep_cword, { desc = 'Grep word under cursor' })
vim.keymap.set('n', '<leader>fb', fzf.buffers, { desc = 'Buffers' })
vim.keymap.set('n', '<leader>fs', fzf.lsp_document_symbols, { desc = 'Document symbols' })
vim.keymap.set('n', '<leader>fS', fzf.lsp_live_workspace_symbols, { desc = 'Workspace symbols' })
vim.keymap.set('n', '<leader>fr', fzf.lsp_references, { desc = 'References' })
vim.keymap.set('n', '<leader>fd', fzf.diagnostics_document, { desc = 'Diagnostics' })
vim.keymap.set('n', '<leader>fh', fzf.helptags, { desc = 'Help tags' })

-- ------------------------------------------------------------------ misc ---
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function() vim.hl.on_yank() end,
})
