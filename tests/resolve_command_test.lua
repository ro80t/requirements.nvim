-- Unit tests for requirements.resolve_command()'s spec formats: plain
-- strings (the traditional format), version-only (exact and spec keys:
-- wildcard/caret/range), arch-only, and both version+arch narrowing
-- (nested either order, and as siblings with fallback). Run with:
--   nvim --headless -u NONE -c "luafile tests/resolve_command_test.lua" -c "qa"
local this_file = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fs.dirname(vim.fs.dirname(this_file))
vim.opt.runtimepath:append(repo_root)

local requirements = require("requirements")
local environment = require("requirements.environment")

local failures = 0

---@param cond boolean
---@param msg string
local function check(cond, msg)
  if cond then
    print("ok: " .. msg)
  else
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

-- Stub get_os() so resolution is deterministic regardless of the host OS
-- actually running this test.
environment.get_os = function()
  return {
    family = "linux",
    sysname = "Linux",
    distro = "ubuntu",
    distro_name = "Ubuntu",
    distro_like = { "debian" },
    version = "22.04",
    arch = "x86_64",
  }
end

---@param name string
---@param spec table<string, Requirements.CommandNode>
local function set(name, spec)
  requirements.setup({ [name] = spec })
end

-- ── Traditional: plain command strings, no version/arch narrowing ─────────

set("plain_exact_distro", { ubuntu = "cmd ubuntu", linux = "cmd linux" })
check(
  requirements.resolve_command("plain_exact_distro") == "cmd ubuntu",
  "plain string: exact distro id wins over family"
)

set("plain_distro_like", { debian = "cmd debian", linux = "cmd linux" })
check(
  requirements.resolve_command("plain_distro_like") == "cmd debian",
  "plain string: falls back to distro_like (debian) when exact id absent"
)

set("plain_family_fallback", { linux = "cmd linux family" })
check(
  requirements.resolve_command("plain_family_fallback") == "cmd linux family",
  "plain string: falls back to OS family when no distro/distro_like key"
)

set("plain_unsupported", { windows = "cmd win", macos = "cmd mac" })
check(
  requirements.resolve_command("plain_unsupported") == nil,
  "plain string: no matching key anywhere resolves to nil"
)

-- ── version only ────────────────────────────────────────────────────────

set("version_only_match", { ubuntu = { version = { ["22.04"] = "cmd v2204" } } })
check(requirements.resolve_command("version_only_match") == "cmd v2204", "version-only: matching version resolves")

set("version_only_nomatch", { ubuntu = { version = { ["20.04"] = "cmd v2004" } } })
check(requirements.resolve_command("version_only_nomatch") == nil, "version-only: non-matching version resolves to nil")

set("version_only_distro_like", { debian = { version = { ["22.04"] = "cmd debian v2204" } } })
check(
  requirements.resolve_command("version_only_distro_like") == "cmd debian v2204",
  "version-only: narrowing also applies through the distro_like fallback"
)

-- ── arch only ───────────────────────────────────────────────────────────

set("arch_only_match", { ubuntu = { arch = { x86_64 = "cmd amd64" } } })
check(requirements.resolve_command("arch_only_match") == "cmd amd64", "arch-only: matching arch resolves")

set("arch_only_nomatch", { ubuntu = { arch = { aarch64 = "cmd arm64" } } })
check(requirements.resolve_command("arch_only_nomatch") == nil, "arch-only: non-matching arch resolves to nil")

-- ── both version and arch ──────────────────────────────────────────────

set("both_nested_version_arch_match", {
  ubuntu = { version = { ["22.04"] = { arch = { x86_64 = "cmd v2204+amd64" } } } },
})
check(
  requirements.resolve_command("both_nested_version_arch_match") == "cmd v2204+amd64",
  "version->arch nested: matching both resolves"
)

set("both_nested_version_arch_nomatch", {
  ubuntu = { version = { ["22.04"] = { arch = { aarch64 = "cmd v2204+arm64" } } } },
})
check(
  requirements.resolve_command("both_nested_version_arch_nomatch") == nil,
  "version->arch nested: version matches but arch doesn't resolves to nil"
)

set("both_nested_arch_version_match", {
  ubuntu = { arch = { x86_64 = { version = { ["22.04"] = "cmd amd64+v2204" } } } },
})
check(
  requirements.resolve_command("both_nested_arch_version_match") == "cmd amd64+v2204",
  "arch->version nested (reverse order): matching both resolves"
)

set("both_sibling_version_wins", {
  ubuntu = {
    version = { ["22.04"] = "cmd version branch" },
    arch = { x86_64 = "cmd arch branch" },
  },
})
check(
  requirements.resolve_command("both_sibling_version_wins") == "cmd version branch",
  "version+arch siblings: matching version takes priority over arch"
)

set("both_sibling_falls_back_to_arch", {
  ubuntu = {
    version = { ["20.04"] = "cmd wrong version" },
    arch = { x86_64 = "cmd arch fallback" },
  },
})
check(
  requirements.resolve_command("both_sibling_falls_back_to_arch") == "cmd arch fallback",
  "version+arch siblings: non-matching version falls back to sibling arch"
)

set("both_sibling_neither_matches", {
  ubuntu = {
    version = { ["20.04"] = "cmd wrong version" },
    arch = { aarch64 = "cmd wrong arch" },
  },
})
check(
  requirements.resolve_command("both_sibling_neither_matches") == nil,
  "version+arch siblings: neither matching resolves to nil"
)

-- ── version specs: wildcard / caret / range ────────────────────────────

set("version_wildcard_match", { ubuntu = { version = { ["22.*"] = "cmd wildcard" } } })
check(requirements.resolve_command("version_wildcard_match") == "cmd wildcard", "version wildcard: matches")

set("version_wildcard_nomatch", { ubuntu = { version = { ["23.*"] = "cmd wildcard" } } })
check(requirements.resolve_command("version_wildcard_nomatch") == nil, "version wildcard: non-matching resolves to nil")

set("version_caret_match", { ubuntu = { version = { ["^22.04"] = "cmd caret" } } })
check(requirements.resolve_command("version_caret_match") == "cmd caret", "version caret: matches within range")

set("version_caret_nomatch", { ubuntu = { version = { ["^23.0"] = "cmd caret" } } })
check(requirements.resolve_command("version_caret_nomatch") == nil, "version caret: outside range resolves to nil")

set("version_range_match", { ubuntu = { version = { ["20.04-23.04"] = "cmd range" } } })
check(requirements.resolve_command("version_range_match") == "cmd range", "version range: matches within bounds")

set("version_range_nomatch", { ubuntu = { version = { ["23.04-24.04"] = "cmd range" } } })
check(requirements.resolve_command("version_range_nomatch") == nil, "version range: outside bounds resolves to nil")

set("version_exact_wins_over_spec", {
  ubuntu = {
    version = {
      ["22.04"] = "cmd exact",
      ["22.*"] = "cmd wildcard",
    },
  },
})
check(
  requirements.resolve_command("version_exact_wins_over_spec") == "cmd exact",
  "version specs: exact key match is tried before spec keys"
)

if failures > 0 then
  error(failures .. " resolve_command test(s) failed")
end

print("ALL RESOLVE_COMMAND TESTS OK")
