-- Unit tests for requirements.version's spec matching: exact, wildcard,
-- caret, and hyphen range. Run with:
--   nvim --headless -u NONE -c "luafile tests/version_test.lua" -c "qa"
local this_file = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fs.dirname(vim.fs.dirname(this_file))
vim.opt.runtimepath:append(repo_root)

local version = require("requirements.version")

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

-- ── compare ─────────────────────────────────────────────────────────────

check(version.compare(version.parse("1.2.3"), version.parse("1.2.3")) == 0, "compare: equal versions")
check(version.compare(version.parse("1.2.3"), version.parse("1.2.4")) == -1, "compare: lesser patch")
check(version.compare(version.parse("1.3.0"), version.parse("1.2.9")) == 1, "compare: greater minor wins over patch")
check(version.compare(version.parse("1.2"), version.parse("1.2.0")) == 0, "compare: missing components count as 0")

-- ── exact ───────────────────────────────────────────────────────────────

check(version.matches("1.2.3", "1.2.3"), "exact: identical strings match")
check(not version.matches("1.2.3", "1.2.4"), "exact: different strings don't match")

-- ── wildcard ────────────────────────────────────────────────────────────

check(version.matches("1.0.*", "1.0.5"), "wildcard: trailing * matches any patch")
check(not version.matches("1.0.*", "1.1.0"), "wildcard: leading components must still match")
check(version.matches("1.*", "1.9.9"), "wildcard: * short-circuits remaining components")
check(version.matches("*", "9.9.9"), "wildcard: bare * matches anything")
check(version.matches("24.*", "24.04"), "wildcard: matches OS-style major.minor version")

-- ── caret ───────────────────────────────────────────────────────────────

check(version.matches("^1.0.0", "1.0.0"), "caret: matches base version itself")
check(version.matches("^1.0.0", "1.9.9"), "caret: matches within same major")
check(not version.matches("^1.0.0", "2.0.0"), "caret: excludes next major")
check(not version.matches("^1.2.3", "1.2.2"), "caret: excludes versions below base")
check(version.matches("^0.2.3", "0.2.9"), "caret: pre-1.0 bumps at first non-zero (minor)")
check(not version.matches("^0.2.3", "0.3.0"), "caret: pre-1.0 excludes next minor when major is 0")
check(version.matches("^0.0.3", "0.0.3"), "caret: 0.0.x bumps at patch")
check(not version.matches("^0.0.3", "0.0.4"), "caret: 0.0.x excludes next patch")
check(version.matches("^22.04", "22.04"), "caret: works with 2-component OS-style versions")
check(not version.matches("^22.04", "23.0"), "caret: excludes next major for 2-component versions")

-- ── range ───────────────────────────────────────────────────────────────

check(version.matches("1.0.0-2.0.0", "1.0.0"), "range: matches lower bound (inclusive)")
check(version.matches("1.0.0-2.0.0", "2.0.0"), "range: matches upper bound (inclusive)")
check(version.matches("1.0.0-2.0.0", "1.5.3"), "range: matches within bounds")
check(not version.matches("1.0.0-2.0.0", "2.0.1"), "range: excludes above upper bound")
check(not version.matches("1.0.0-2.0.0", "0.9.9"), "range: excludes below lower bound")
check(version.matches("18.04-20.04", "18.04"), "range: works with OS-style versions")

if failures > 0 then
  error(failures .. " version test(s) failed")
end

print("ALL VERSION TESTS OK")
