local M = {}

--- Builds a `hooks` table for `MiniDeps.add({ hooks = ... })` that installs
--- `spec`'s external dependencies right after the plugin's files are fetched
--- but before it gets `:packadd`-ed.
---@param spec Requirements.Spec
---@param opts Requirements.EnsureOpts|nil
---@return table
function M.hooks(spec, opts)
  return {
    post_install = function()
      local requirements = require("requirements")
      requirements.setup(spec)
      requirements.ensure(vim.tbl_keys(spec), opts)
    end,
  }
end

return M
