local M = {}

---@class snacks.picker
---@field files fun(opts?: snacks.picker.files.Config): snacks.Picker
---@field zoxide fun(opts?: snacks.picker.Config): snacks.Picker

local uv = vim.uv or vim.loop

local commands = {
  rg = { "--files", "--no-messages", "--color", "never", "-g", "!.git" },
  fd = { "--type", "f", "--type", "l", "--color", "never", "-E", ".git" },
  find = { ".", "-type", "f", "-not", "-path", "*/.git/*" },
}

---@param opts snacks.picker.files.Config
---@param filter snacks.picker.Filter
local function get_cmd(opts, filter)
  local cmd, args ---@type string, string[]
  if vim.fn.executable("fd") == 1 then
    cmd, args = "fd", commands.fd
  elseif vim.fn.executable("fdfind") == 1 then
    cmd, args = "fdfind", commands.fd
  elseif vim.fn.executable("rg") == 1 then
    cmd, args = "rg", commands.rg
  elseif vim.fn.executable("find") == 1 and vim.fn.has("win-32") == 0 then
    cmd, args = "find", commands.find
  else
    error("No supported finder found")
  end
  args = vim.deepcopy(args)
  local is_fd, is_fd_rg, is_find, is_rg = cmd == "fd" or cmd == "fdfind", cmd ~= "find", cmd == "find", cmd == "rg"

  -- exclude
  for _, e in ipairs(opts.exclude or {}) do
    if is_fd then
      vim.list_extend(args, { "-E", e })
    elseif is_rg then
      vim.list_extend(args, { "-g", "!" .. e })
    elseif is_find then
      table.insert(args, "-not")
      table.insert(args, "-path")
      table.insert(args, e)
    end
  end

  -- hidden
  if opts.hidden and is_fd_rg then
    table.insert(args, "--hidden")
  elseif not opts.hidden and is_find then
    vim.list_extend(args, { "-not", "-path", "*/.*" })
  end

  -- ignored
  if opts.ignored and is_fd_rg then
    args[#args + 1] = "--no-ignore"
  end

  -- follow
  if opts.follow then
    args[#args + 1] = "-L"
  end

  -- extra args
  vim.list_extend(args, opts.args or {})

  -- file glob
  ---@type string?
  local pattern, pargs = Snacks.picker.util.parse(filter.search)
  vim.list_extend(args, pargs)

  pattern = pattern ~= "" and pattern or nil
  if pattern then
    if is_fd then
      table.insert(args, pattern)
    elseif is_rg then
      table.insert(args, "--glob")
      table.insert(args, pattern)
    elseif is_find then
      table.insert(args, "-name")
      table.insert(args, pattern)
    end
  end

  -- dirs
  local dirs = opts.dirs or {}
  if opts.rtp then
    vim.list_extend(dirs, Snacks.picker.util.rtp())
  end
  if #dirs > 0 then
    dirs = vim.tbl_map(vim.fs.normalize, dirs) ---@type string[]
    if is_fd and not pattern then
      args[#args + 1] = "."
    end
    if is_find then
      table.remove(args, 1)
      for _, d in pairs(dirs) do
        table.insert(args, 1, d)
      end
    else
      vim.list_extend(args, dirs)
    end
  end

  return cmd, args
end

---@param opts snacks.picker.files.Config
---@type snacks.picker.finder
function M.files(opts, ctx)
  local cwd = not (opts.rtp or (opts.dirs and #opts.dirs > 0))
      and vim.fs.normalize(opts and opts.cwd or uv.cwd() or ".")
    or nil
  local cmd, args = get_cmd(opts, ctx.filter)
  return require("snacks.picker.source.proc").proc({
    opts,
    {
      cmd = cmd,
      args = args,
      notify = not opts.live,
      ---@param item snacks.picker.finder.Item
      transform = function(item)
        item.cwd = cwd
        item.file = item.text
      end,
    },
  }, ctx)
end

---@param opts snacks.picker.proc.Config
---@type snacks.picker.finder
function M.zoxide(opts, ctx)
  return require("snacks.picker.source.proc").proc({
    opts,
    {
      cmd = "zoxide",
      args = { "query", "--list" },
      ---@param item snacks.picker.finder.Item
      transform = function(item)
        item.file = item.text
      end,
    },
  }, ctx)
end

return M
