vim.opt.clipboard:append("unnamedplus")
vim.opt.cursorline = true  -- Highlight the line
vim.opt.cursorcolumn = true -- Highlight the column

-- Customize the highlight groups for better visibility
-- Slightly lighter background for CursorLine and CursorColumn
vim.api.nvim_set_hl(0, "CursorLine", { bg = "#3a3d41" }) -- Example: Lighter gray background
vim.api.nvim_set_hl(0, "CursorColumn", { bg = "#3a3d41" }) -- Same as line for consistency

-- Customize the search highlight color
vim.api.nvim_set_hl(0, "Search", { bg = "#FFD700", fg = "#000000", bold = true }) -- Example: Gold background, black text


vim.opt.ignorecase = true -- Ignore case in search patterns
vim.opt.smartcase = true  -- Override ignorecase if search pattern contains uppercase letters


local setup = function()
  local nlines = vim.fn.getenv('INPUT_LINE_NUMBER')
  local cur_line = vim.fn.getenv('CURSOR_LINE')
  local cur_column = vim.fn.getenv('CURSOR_COLUMN')
  vim.opt.encoding='utf-8'
  vim.opt.compatible = false
  vim.opt.number = false
  vim.opt.relativenumber = false
  vim.opt.termguicolors = true
  vim.opt.showmode = false
  vim.opt.ruler = false
  vim.opt.laststatus = 0
  vim.opt.showcmd = false
  vim.opt.scrollback = 1000
  local term_buf = vim.api.nvim_create_buf(true, false);
  local term_io = vim.api.nvim_open_term(term_buf, {})
  vim.api.nvim_buf_set_keymap(term_buf, 'n', 'q', '<Cmd>q<CR>', { })
  local group = vim.api.nvim_create_augroup('kitty+page', {})

  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    pattern = '*',
    once = true,
    callback = function(ev)
        local current_win = vim.fn.win_getid()
        for _, line in ipairs(vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)) do
          vim.api.nvim_chan_send(term_io, line)
          vim.api.nvim_chan_send(term_io, '\r\n')
        end
        term_io = false
        vim.api.nvim_create_autocmd('ModeChanged', {
          group = group,
          pattern = "([nN]:[^vV])|([vV]:[^nN])",
          command = 'stopinsert'
        })
        vim.api.nvim_win_set_buf(current_win, term_buf)
        if nlines ~= vim.NIL and cur_line ~= vim.NIL and cur_column ~= vim.NIL then
          vim.api.nvim_win_set_cursor(current_win, {vim.fn.max({1, nlines}) + cur_line, cur_column - 1})
        else
          vim.api.nvim_input([[<C-\><C-n>G]])
        end
        vim.api.nvim_buf_delete(ev.buf, { force = true } )
    end
  })
end
setup()
