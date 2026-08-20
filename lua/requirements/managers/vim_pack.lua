local M = {}

--- Registers a `PackChanged` autocmd that installs `spec`'s external
--- dependencies right before `plugin_name` is loaded for the first time.
--- Must be called BEFORE the corresponding `vim.pack.add()` call, since
--- `vim.pack` only fires `PackChanged` for autocmds set up ahead of it.
---@param plugin_name string
---@param spec Requirements.Spec
---@param opts Requirements.EnsureOpts|nil
---@return number autocmd id
function M.watch(plugin_name, spec, opts)
  return vim.api.nvim_create_autocmd("PackChanged", {
    callback = function(ev)
      if ev.data.kind == "install" and ev.data.spec.name == plugin_name then
        local requirements = require("requirements")
        requirements.setup(spec)
        requirements.ensure(vim.tbl_keys(spec), opts)
      end
    end,
  })
end

return M
