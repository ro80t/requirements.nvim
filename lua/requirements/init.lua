local M = {}

local environment = require("requirements.environment")
local version = require("requirements.version")

---@alias Requirements.CommandNode
---| string
---| { version: table<string, Requirements.CommandNode>|nil, arch: table<string, Requirements.CommandNode>|nil }
---@alias Requirements.Spec table<string, table<string, Requirements.CommandNode>>

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

--- Looks up `os_info.version` in `version_table`. Tries an exact key match
--- first; if none is found, falls back to treating keys as version specs
--- (wildcard `"1.0.*"`, caret `"^1.0.0"`, or hyphen range `"1.0.0-2.0.0"`)
--- and returns the first one (in sorted key order, for determinism) that
--- matches. Overlapping specs should be avoided, since only one is picked.
---@param version_table table<string, Requirements.CommandNode>
---@param os_version string
---@return Requirements.CommandNode|nil
local function lookup_version(version_table, os_version)
  local exact = version_table[os_version]
  if exact then
    return exact
  end

  local specs = vim.tbl_keys(version_table)
  table.sort(specs)
  for _, spec in ipairs(specs) do
    if version.matches(spec, os_version) then
      return version_table[spec]
    end
  end

  return nil
end

--- Narrows a `Requirements.CommandNode` down to a plain command string,
--- optionally filtering by OS version and/or CPU architecture. A node is
--- either a command string, or a table with an optional `version` and/or
--- `arch` sub-table (each keyed by the matching identifier, mapping to a
--- nested `Requirements.CommandNode`) — any combination of the two, or
--- neither, is valid. `version` keys may also be specs: a wildcard
--- (`"1.0.*"`), a caret range (`"^1.0.0"`), or a hyphen range
--- (`"1.0.0-2.0.0"`); see `lua/requirements/version.lua`.
---@param node Requirements.CommandNode|nil
---@param os_info Requirements.OSInfo
---@return string|nil
local function resolve_node(node, os_info)
  if type(node) == "string" then
    return node
  end
  if type(node) ~= "table" then
    return nil
  end

  if node.version and os_info.version then
    local matched = lookup_version(node.version, os_info.version)
    if matched then
      local resolved = resolve_node(matched, os_info)
      if resolved then
        return resolved
      end
    end
  end

  if node.arch and os_info.arch and node.arch[os_info.arch] then
    return resolve_node(node.arch[os_info.arch], os_info)
  end

  return nil
end

--- Resolves the install command for `name` on the current environment,
--- trying the exact distro id, then its `ID_LIKE` chain, then the OS family
--- (each of those may be further narrowed by OS version and/or CPU arch).
---@param name string
---@return string|nil
function M.resolve_command(name)
  local commands = M.registry[name]
  if not commands then
    return nil
  end

  local os_info = environment.get_os()

  if os_info.distro and commands[os_info.distro] then
    local resolved = resolve_node(commands[os_info.distro], os_info)
    if resolved then
      return resolved
    end
  end

  if os_info.distro_like then
    for _, id in ipairs(os_info.distro_like) do
      if commands[id] then
        local resolved = resolve_node(commands[id], os_info)
        if resolved then
          return resolved
        end
      end
    end
  end

  return resolve_node(commands[os_info.family], os_info)
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
