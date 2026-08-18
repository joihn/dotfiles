-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      lazygit = { enabled = true },
    },
    keys = {
      { '<leader>gg', function() Snacks.lazygit() end, desc = 'Open Lazy[G]it' },
      { '<leader>gl', function() Snacks.lazygit.log() end, desc = 'Lazygit [L]og (cwd)' },
      { '<leader>gf', function() Snacks.lazygit.log_file() end, desc = 'Lazygit current [F]ile history' },
    },
  },
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'nvim-mini/mini.nvim',
    },
    opts = {
      heading = { enabled = false },
      paragraph = { enabled = false },
      code = { enabled = false },
      dash = { enabled = false },
      document = { enabled = false },
      bullet = { enabled = false },
      checkbox = { enabled = false },
      quote = { enabled = false },
      link = { enabled = false },
      sign = { enabled = false },
      inline_highlight = { enabled = false },
      indent = { enabled = false },
      html = { enabled = false },
      latex = { enabled = false },
      yaml = { enabled = false },
      pipe_table = {
        cell = 'padded',
      },
    },
    keys = {
      {
        '<leader>mt',
        '<cmd>RenderMarkdown buf_toggle<cr>',
        desc = '[M]arkdown [T]oggle rendering',
      },
    },
  },
}
