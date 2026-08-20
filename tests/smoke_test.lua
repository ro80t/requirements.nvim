-- Run with: nvim --headless -u NONE -c "luafile tests/smoke_test.lua" -c "qa"
local this_file = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fs.dirname(vim.fs.dirname(this_file))
vim.opt.runtimepath:append(repo_root)

local requirements = require("requirements")
local environment = require("requirements.environment")

local os_info = environment.get_os()
print("os family: " .. os_info.family)
print("os distro: " .. tostring(os_info.distro))

assert(os_info.family ~= "unknown", "expected a recognized OS family in CI")

-- managers/* must at least load without error
assert(type(require("requirements.managers.mini_deps").hooks) == "function")
assert(type(require("requirements.managers.vim_pack").watch) == "function")

local is_windows = environment.is_windows()

requirements.setup({
  fake_dep_a = {
    windows = "cmd /c exit 0",
    linux = "sh -c 'sleep 0.2; exit 0'",
    macos = "sh -c 'sleep 0.2; exit 0'",
  },
  fake_dep_b = {
    windows = "cmd /c exit 0",
    linux = "sh -c 'sleep 0.3; exit 0'",
    macos = "sh -c 'sleep 0.3; exit 0'",
  },
  fake_dep_c_fail = {
    windows = "cmd /c exit 1",
    linux = "sh -c 'exit 1'",
    macos = "sh -c 'exit 1'",
  },
  fake_dep_d_unsupported = {
    plan9 = "echo unreachable",
  },
})

local cmd = requirements.resolve_command("fake_dep_a")
print("resolved fake_dep_a: " .. tostring(cmd))
assert(cmd ~= nil, "expected a resolved command for fake_dep_a")

local start = vim.uv.hrtime()
local results = requirements.ensure({
  "fake_dep_a",
  "fake_dep_b",
  "fake_dep_c_fail",
  "fake_dep_d_unsupported",
  "nvim", -- already installed (this binary)
}, { notify = false, timeout = 5000 })
local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

print(("elapsed: %.1fms"):format(elapsed_ms))
for _, r in ipairs(results) do
  print(("%s -> %s (code=%s)"):format(r.name, r.status, tostring(r.code)))
end

local by_name = {}
for _, r in ipairs(results) do
  by_name[r.name] = r
end

assert(by_name.fake_dep_a.status == "installed", "fake_dep_a should install")
assert(by_name.fake_dep_b.status == "installed", "fake_dep_b should install")
assert(by_name.fake_dep_c_fail.status == "failed", "fake_dep_c_fail should fail")
assert(by_name.fake_dep_d_unsupported.status == "unsupported", "fake_dep_d_unsupported should be unsupported")
assert(by_name.nvim.status == "already_installed", "nvim should already be installed")

-- a (~200ms) and b (~300ms) run concurrently, so total should be well under
-- their serial sum (~500ms). Not meaningful on windows, where both commands
-- are effectively instant.
if not is_windows then
  assert(elapsed_ms < 480, "expected concurrent execution, took " .. elapsed_ms .. "ms")
end

print("ALL OK")
