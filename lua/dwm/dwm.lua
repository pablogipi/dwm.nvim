local function isBlank(x)
  return not not tostring(x):find "^%s*$"
end

local M = {
  resetwins = true,
  floatwin = -1,
  curwin = -1,
  cur_float_win = -1,
  nerdtree_win = -1,
  nerdtree_win_pos = { 0, 0 },
}

function M:pre_win_op()
  -- Operations to do BEFORE any window operation is performed.
  -- This assumes get_wins() has been called and our spacial flags are ready

  -- If there is a nerdtree window then toggle it to close
  -- print "In PRE"
  if self.nerdtree_win >= 0 then
    -- print("Close NERDTree window")
    vim.api.nvim_command "NERDTreeClose"
  end
  self.resetwins = false
end
function M:post_win_op()
  -- print "In POST"
  -- Operations to do AFTER any window operation is performed.
  -- This assumes get_wins() has been called and our spacial flags are ready
  local curwin = vim.api.nvim_get_current_win()

  -- If there is a floating window then restore focus to it
  if self.cur_float_win >= 0 then
    -- print(string.format("Switch focus to current floating window: %d", self.cur_float_win))
    -- Restore focus to current floating window
    if vim.api.nvim_win_is_valid(self.cur_float_win) then
      -- print "Set floating window as current"
      vim.api.nvim_set_current_win(self.cur_float_win)
      self.resetwins = true
      return
    end
  end
  -- If there is a nerdtree window then restore focus to it
  --[[ if self.nerdtree_win >= 0 then 
    local curwin = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(self.nerdtree_win)
    self:wincmd "H"
    vim.api.nvim_set_current_win(curwin)
  end ]]
  -- If there is a nerdtree window then toggle it to close
  -- print ( "Nerdtree window in M!: %d", self.nerdtree_win )
  if self.nerdtree_win >= 0 then
    -- print("Restore NERDTree window")
    vim.api.nvim_command "NERDTree"
  end
  self.nerdtree_win = -1
  vim.api.nvim_set_current_win(curwin)
  self.resetwins = true
end

--- Open a new window
-- The master pane move to the top of stacks, and a new window appears.
-- before:          after:
--   ┌────┬────┬────┐    ┌────┬────┬─────┐
--   │    │    │ S1 │    │    │    │ S1  │
--   │    │    │    │    │    │    ├─────┤
--   │    │    ├────┤    │    │    │ S2  │
--   │ M1 │ M2 │ S2 │    │ M1 │ M2 ├─────┤
--   │    │    │    │    │    │    │ S3  │
--   │    │    ├────┤    │    │    ├─────┤
--   │    │    │ S3 │    │    │    │ S4  │
--   └────┴────┴────┘    └────┴────┴─────┘
function M:new()
  self:stack()
  vim.cmd [[topleft new]]
  self:reset()
end

--- Move the current master pane to the stack
-- The layout should be the followings.
--
--   ┌────────┐
--   │   M1   │
--   ├────────┤
--   │   M2   │
--   ├────────┤
--   │   S1   │
--   ├────────┤
--   │   S2   │
--   ├────────┤
--   │   S3   │
--   └────────┘
function M:stack()
  local wins = self:get_wins()
  if #wins == 1 then
    return
  end
  for i = math.min(self.master_pane_count, #wins), 1, -1 do
    vim.api.nvim_set_current_win(wins[i])
    self:wincmd "K"
  end
end

--- Move the current window to the master pane.
-- The previous master window is added to the top of the stack. If the current
-- window is in the master pane already, it is moved to the top of the stack.
function M:focus()
  local wins = self:get_wins()
  if #wins == 1 then
    return
  end
  local current = vim.api.nvim_get_current_win()
  if wins[1] == current then
    self:wincmd "w"
    current = vim.api.nvim_get_current_win()
  end
  self:stack()
  if current ~= vim.api.nvim_get_current_win() then
    vim.api.nvim_set_current_win(current)
  end
  self:wincmd "H"
  self:reset()
end

--- Handler for BufWinEnter autocmd
-- Recreate layout broken by the new window
function M:buf_win_enter()
  if
    #self:get_wins() == 1
    or vim.w.dwm_disabled
    or vim.b.dwm_disabled
    or not vim.opt.buflisted:get()
    or vim.opt.filetype:get() == ""
    or vim.opt.filetype:get() == "help"
    or vim.opt.buftype:get() == "quickfix"
    or vim.opt.buftype:get() == "qf"
    or vim.opt.buftype:get() == "nerdtree"
  then
    return
  end

  self:wincmd "K" -- Move the new window to the top of the stack
  self:focus() -- Focus the new window (twice :)
  self:focus()
end

--- Close the current window
function M:close()
  vim.api.nvim_win_close(0, false)
  if self:get_wins()[1] == vim.api.nvim_get_current_win() then
    self:wincmd "H"
    self:stack()
    self:reset()
  end
end

--- Resize the master pane
function M:resize(diff)
  local wins = self:get_wins()
  local current = vim.api.nvim_get_current_win()
  local size = vim.api.nvim_win_get_width(current)
  local direction = wins[1] == current and 1 or -1
  local width = size + diff * direction
  vim.api.nvim_win_set_width(current, width)
  self.master_pane_width = width
end

--- Rotate windows
-- @param left Bool value to rotate left. Default: false
function M:rotate(left)
  -- self.resetwins = true
  local wins = self:get_wins()
  -- self.resetwins = false
  self:pre_win_op()
  self:stack()
  if left then
    vim.api.nvim_set_current_win(wins[1])
    self:wincmd "J"
  else
    vim.api.nvim_set_current_win(wins[#wins])
    self:wincmd "K"
  end
  self:reset()
  -- self:post_win_op()
end

--- Reset height and width of the windows
-- This should be run after calling stack().
function M:reset()
  -- print "In reset()"
  -- self.resetwins = true
  local wins = self:get_wins()
  -- self.resetwins = false
  if #wins == 1 then
    return
  end
  self:pre_win_op()

  -- PRE
  -- If there is a nerdtree window then toggle it to close
  -- if self.nerdtree_win >= 0 then
  --   vim.api.nvim_command "NERDTreeToggle"
  -- end

  local width = self:calculate_width()
  if width * self.master_pane_count > vim.o.columns then
    self:warn "invalid width. use defaults"
    width = self:default_master_pane_width()
  end

  if #wins <= self.master_pane_count then
    for i = self.master_pane_count, 1, -1 do
      vim.api.nvim_set_current_win(wins[i])
      self:wincmd "H"
      if i ~= 1 then
        vim.api.nvim_win_set_width(wins[i], width)
      end
      vim.api.nvim_win_set_option(wins[i], "winfixwidth", true)
    end
    return
  end

  for i = self.master_pane_count, 1, -1 do
    vim.api.nvim_set_current_win(wins[i])
    self:wincmd "H"
  end
  for _, w in ipairs(wins) do
    vim.api.nvim_win_set_option(w, "winfixwidth", false)
  end
  for i = 1, self.master_pane_count do
    vim.api.nvim_win_set_width(wins[i], width)
    vim.api.nvim_win_set_option(wins[i], "winfixwidth", true)
  end

  -- POST
  --[[ -- If there is a floating window then restore focus to it
  if self.cur_float_win >= 0 then
    -- print(string.format("Switch focus to current floating window: %d", self.cur_float_win))
    -- Restore focus to current floating window
    if vim.api.nvim_win_is_valid(self.cur_float_win) then
      vim.api.nvim_set_current_win(self.cur_float_win)
    end
  end
  -- If there is a nerdtree window then toggle it to close
  local curwin = vim.api.nvim_get_current_win()
  if self.nerdtree_win >= 0 then
    vim.api.nvim_command "NERDTreeToggle"
  end
  self.nerdtree_win = -1
  vim.api.nvim_set_current_win(curwin) ]]
  self:post_win_op()
end

function M:parse_percentage(v) -- luacheck: ignore 212
  return tonumber(v:match "^(%d+)%%$")
end

function M:calculate_width()
  if type(self.master_pane_width) == "number" then
    return self.master_pane_width
  elseif type(self.master_pane_width) == "string" then
    local percentage = self:parse_percentage(self.master_pane_width)
    return math.floor(vim.o.columns * percentage / 100)
  end
  return self:default_master_pane_width()
end

function M:default_master_pane_width()
  return math.floor(vim.o.columns / (self.master_pane_count + 1))
end

function M:get_wins() -- luacheck: ignore 212
  -- Init window indexes and flags if needed
  -- print "Reset windows state"
  -- print(self.resetwins)
  if self.resetwins then
    self.floatwin = -1 -- Init local win index
    self.cur_float_win = -1 -- Init cur floating window
    self.nerdtree_win = -1 -- Init nerdtree win
    self.curwin = vim.api.nvim_get_current_win()
  end
  local wins = {}
  -- print("Current window: %d", self.curwin)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    -- print(_, w)
    local is_float = vim.api.nvim_win_get_config(w).relative ~= ""
    local is_nerdtree = false
    -- local is_external = vim.api.nvim_win_get_config(w).external == 1
    if self.resetwins then
      -- If windows states needs to be reset, detect all out spacial cases
      local buf = vim.api.nvim_win_get_buf(w)
      local ft = vim.api.nvim_buf_get_option(buf, "filetype")
      if ft == "nerdtree" then
        self.nerdtree_win_pos = vim.api.nvim_win_get_position(w)
        self.nerdtree_win = w
        -- print ( "Nerdtree window found!: %d", self.nerdtree_win )
        is_nerdtree = true
      end
      if is_float and not isBlank(buf) then
        -- print(string.format("Found floating window with index: %d", w))
        self.floatwin = w -- Init local win index
        if self.curwin == w then
          -- print "Floating window is current window!!!"
          self.cur_float_win = w
        end
      end
    end
    if not is_float and not is_nerdtree then
      table.insert(wins, w)
    end
  end
  return wins
end

function M:wincmd(cmd)
  vim.cmd("wincmd " .. cmd)
end -- luacheck: ignore 212

function M:map(lhs, f)
  if vim.keymap then
    vim.keymap.set("n", lhs, f, { silent = true })
    return
  end
  local rhs
  if type(f) == "function" then
    if not _G[self.func_var_name] then
      _G[self.func_var_name] = self.funcs
    end
    self.funcs[#self.funcs + 1] = f
    rhs = ([[<Cmd>lua %s[%d]()<CR>]]):format(self.func_var_name, #self.funcs)
  else
    rhs = f
  end
  vim.api.nvim_set_keymap("n", lhs, rhs, { noremap = true, silent = true })
end

function M:warn(msg) -- luacheck: ignore 212
  vim.api.nvim_echo({ { msg, "WarningMsg" } }, true, {})
end

return (function()
  local self = {
    func_var_name = ("__dwm_funcs_%d__"):format(vim.loop.now()),
    funcs = {},
    master_pane_count = 1,
  }
  return setmetatable(self, { __index = M })
end)()
