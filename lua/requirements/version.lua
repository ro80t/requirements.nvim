local M = {}

--- Splits a dot-separated version string into numeric components, e.g.
--- "22.04" -> { 22, 4 }. Non-numeric components parse as 0.
---@param str string
---@return integer[]
local function parse(str)
  local parts = {}
  for part in str:gmatch("[^.]+") do
    table.insert(parts, tonumber(part) or 0)
  end
  return parts
end
M.parse = parse

--- Compares two parsed versions component-wise (missing trailing
--- components are treated as 0, so `1.2` == `1.2.0`).
---@param a integer[]
---@param b integer[]
---@return integer -- -1 if a < b, 0 if a == b, 1 if a > b
local function compare(a, b)
  for i = 1, math.max(#a, #b) do
    local x, y = a[i] or 0, b[i] or 0
    if x ~= y then
      return x < y and -1 or 1
    end
  end
  return 0
end
M.compare = compare

--- Matches `version` against a wildcard spec, e.g. "1.0.*" or "1.*.*".
--- Components before the first `*` must match exactly; `*` (and anything
--- after it) matches any value.
---@param spec string
---@param version string
---@return boolean
local function matches_wildcard(spec, version)
  local version_parts = parse(version)
  local i = 0
  for part in spec:gmatch("[^.]+") do
    i = i + 1
    if part == "*" then
      return true
    end
    if (version_parts[i] or 0) ~= (tonumber(part) or 0) then
      return false
    end
  end
  return true
end

--- Matches `version` against an inclusive hyphen range, e.g.
--- "1.0.0-2.0.0".
---@param lower string
---@param upper string
---@param version string
---@return boolean
local function matches_range(lower, upper, version)
  local v = parse(version)
  return compare(v, parse(lower)) >= 0 and compare(v, parse(upper)) <= 0
end

--- Matches `version` against a caret spec, e.g. "^1.2.3", using npm
--- semantics: compatible with `base`, up to (but excluding) the next
--- version that changes the first non-zero component. `^1.2.3` therefore
--- means `>=1.2.3 <2.0.0`, `^0.2.3` means `>=0.2.3 <0.3.0`, and `^0.0.3`
--- means `>=0.0.3 <0.0.4`.
---@param base string
---@param version string
---@return boolean
local function matches_caret(base, version)
  local base_parts = parse(base)
  local v = parse(version)
  if compare(v, base_parts) < 0 then
    return false
  end

  local bump_index = #base_parts
  for i, n in ipairs(base_parts) do
    if n ~= 0 then
      bump_index = i
      break
    end
  end

  local upper = {}
  for i, n in ipairs(base_parts) do
    upper[i] = i < bump_index and n or (i == bump_index and n + 1 or 0)
  end

  return compare(v, upper) < 0
end

--- Matches `version` against `spec`, which may be:
--- - a plain version string: exact match ("1.2.3")
--- - a wildcard: "1.2.*", "1.*" (trailing components match anything)
--- - a caret range: "^1.2.3" (compatible release, npm semantics)
--- - a hyphen range: "1.0.0-2.0.0" (inclusive on both ends)
---@param spec string
---@param version string
---@return boolean
function M.matches(spec, version)
  if spec == version then
    return true
  end

  if spec:find("*", 1, true) then
    return matches_wildcard(spec, version)
  end

  if spec:sub(1, 1) == "^" then
    return matches_caret(spec:sub(2), version)
  end

  local lower, upper = spec:match("^(%d[%d.]*)%-(%d[%d.]*)$")
  if lower and upper then
    return matches_range(lower, upper, version)
  end

  return false
end

return M
