local M = {}

local environment = require("requirements.environment")

---@alias Requirements.Spec table<string, table<string, string>>

---@type Requirements.Spec
M.registry = {}

--- Registers (merges) dependency install commands, keyed by OS family or
--- distro id. Safe to call multiple times / from multiple plugins.
---@param spec Requirements.Spec
---@return Requirements.Spec
function M.setup(spec)
  M.registry = vim.tbl_deep_extend("force", M.registry, spec or {})
  return M.registry
end

---@param name string
---@return boolean
function M.is_installed(name)
  return vim.fn.executable(name) == 1
end

--- Resolves the install command for `name` on the current environment,
--- trying the exact distro id, then its `ID_LIKE` chain, then the OS family.
---@param name string
---@return string|nil
function M.resolve_command(name)
  local commands = M.registry[name]
  if not commands then
    return nil
  end

  local os_info = environment.get_os()

  if os_info.distro and commands[os_info.distro] then
    return commands[os_info.distro]
  end

  if os_info.distro_like then
    for _, id in ipairs(os_info.distro_like) do
      if commands[id] then
        return commands[id]
      end
    end
  end

  return commands[os_info.family]
end

---@param cmd string
---@return string[]
local function shell_argv(cmd)
  if environment.is_windows() then
    return { "cmd", "/d", "/c", cmd }
  end
  return { "sh", "-c", cmd }
end

---@param results Requirements.EnsureResult[]
local function notify_results(results)
  for _, result in ipairs(results) do
    if result.status == "installed" then
      vim.notify(("[requirements.nvim] installed: %s"):format(result.name), vim.log.levels.INFO)
    elseif result.status == "failed" then
      local msg = ("[requirements.nvim] failed to install: %s"):format(result.name)
      if result.stderr and result.stderr ~= "" then
        msg = msg .. "\n" .. result.stderr
      end
      vim.notify(msg, vim.log.levels.ERROR)
    elseif result.status == "timeout" then
      vim.notify(("[requirements.nvim] timed out installing: %s"):format(result.name), vim.log.levels.WARN)
    elseif result.status == "unsupported" then
      vim.notify(
        ("[requirements.nvim] no install command for '%s' on this environment"):format(result.name),
        vim.log.levels.WARN
      )
    end
  end
end

---@class Requirements.EnsureOpts
---@field timeout number|nil  -- ms, default 300000 (5 min)
---@field notify boolean|nil  -- default true

---@class Requirements.EnsureResult
---@field name string
---@field status "already_installed"|"installed"|"failed"|"unsupported"|"timeout"
---@field code number|nil
---@field stderr string|nil

--- Installs every missing dependency in `names` (default: everything
--- registered via `setup`) in parallel, then blocks until all of them have
--- finished (or `opts.timeout` elapses) before returning.
---@param names string[]|nil
---@param opts Requirements.EnsureOpts|nil
---@return Requirements.EnsureResult[]
function M.ensure(names, opts)
  opts = opts or {}
  local timeout = opts.timeout or 300000
  local notify = opts.notify
  if notify == nil then
    notify = true
  end

  names = names or vim.tbl_keys(M.registry)

  ---@type Requirements.EnsureResult[]
  local results = {}
  local pending = 0

  for _, name in ipairs(names) do
    if M.is_installed(name) then
      table.insert(results, { name = name, status = "already_installed" })
    else
      local cmd = M.resolve_command(name)
      if not cmd then
        table.insert(results, { name = name, status = "unsupported" })
      else
        pending = pending + 1
        ---@type Requirements.EnsureResult
        local result = { name = name, status = "failed" }
        table.insert(results, result)

        vim.system(shell_argv(cmd), { text = true }, function(obj)
          result.code = obj.code
          result.stderr = obj.stderr
          result.status = (obj.code == 0) and "installed" or "failed"
          pending = pending - 1
        end)
      end
    end
  end

  if pending > 0 then
    local completed = vim.wait(timeout, function()
      return pending == 0
    end, 50)

    if not completed then
      for _, result in ipairs(results) do
        if result.status == "failed" and result.code == nil then
          result.status = "timeout"
        end
      end
    end
  end

  if notify then
    notify_results(results)
  end

  return results
end

--- Installs every dependency registered via `setup`. Equivalent to
--- `M.ensure(nil, opts)`.
---@param opts Requirements.EnsureOpts|nil
---@return Requirements.EnsureResult[]
function M.ensure_all(opts)
  return M.ensure(nil, opts)
end

return M
