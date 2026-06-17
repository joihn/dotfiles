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
}
