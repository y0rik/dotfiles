-- ~/.config/nvim/init.lua: a link to ~/.dotfiles/modules/neovim/files/init.lua.
-- A small starting point: plain options, no plugins yet. Grow it here.

vim.g.mapleader = " "

local o = vim.opt
o.number = true
o.relativenumber = true
o.mouse = "a"
o.clipboard = "unnamedplus"
o.ignorecase = true
o.smartcase = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.undofile = true
o.signcolumn = "yes"
o.splitright = true
o.splitbelow = true
o.scrolloff = 8
