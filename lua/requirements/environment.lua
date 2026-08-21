local M = {}

local uv = vim.uv or vim.loop

---@type table<string, boolean>
local BSD_SYSNAMES = {
  FreeBSD = true,
  OpenBSD = true,
  NetBSD = true,
  DragonFly = true,
}

---@param path string
---@return string|nil
local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  return content
end

---@param content string
---@return table<string, string>
local function parse_os_release(content)
  local fields = {}
  for line in content:gmatch("[^\r\n]+") do
    local key, value = line:match("^([%w_]+)=(.*)$")
    if key then
      value = value:gsub('^"(.*)"$', "%1")
      value = value:gsub("^'(.*)'$", "%1")
      fields[key] = value
    end
  end
  return fields
end

--- Reads /etc/os-release (or /usr/lib/os-release) for distro info.
--- Present on virtually all Linux distros; some BSDs ship one too.
---@return string|nil id, string|nil name, string[]|nil id_like, string|nil version_id
local function detect_os_release()
  local content = read_file("/etc/os-release") or read_file("/usr/lib/os-release")
  if not content then
    return nil
  end

  local fields = parse_os_release(content)

  local id_like = nil
  if fields.ID_LIKE then
    id_like = {}
    for id in fields.ID_LIKE:gmatch("%S+") do
      table.insert(id_like, id)
    end
  end

  return fields.ID, fields.NAME or fields.PRETTY_NAME, id_like, fields.VERSION_ID
end

---@class Requirements.OSInfo
---@field family "windows"|"macos"|"linux"|"bsd"|"unknown"
---@field sysname string
---@field distro string|nil          -- e.g. "ubuntu", "arch", "freebsd"
---@field distro_name string|nil     -- e.g. "Ubuntu", "Arch Linux"
---@field distro_like string[]|nil   -- e.g. { "debian" } for Ubuntu
---@field version string|nil         -- e.g. "22.04" (os-release VERSION_ID, or OS release string)
---@field arch string|nil            -- e.g. "x86_64", "arm64" (uname machine)

---@type Requirements.OSInfo|nil
local cached

--- Detects the current OS family, and for Linux/BSD also the distro.
---@return Requirements.OSInfo
function M.get_os()
  if cached then
    return cached
  end

  local uname = uv.os_uname()
  local sysname = uname.sysname

  ---@type Requirements.OSInfo
  local info = {
    family = "unknown",
    sysname = sysname,
    distro = nil,
    distro_name = nil,
    distro_like = nil,
    version = uname.release,
    arch = uname.machine,
  }

  if sysname == "Windows_NT" then
    info.family = "windows"
  elseif sysname == "Darwin" then
    info.family = "macos"
  elseif sysname == "Linux" then
    info.family = "linux"
  elseif BSD_SYSNAMES[sysname] then
    info.family = "bsd"
  end

  if info.family == "linux" or info.family == "bsd" then
    local id, name, id_like, version_id = detect_os_release()
    if id then
      info.distro = id
      info.distro_name = name
      info.distro_like = id_like
      info.version = version_id or info.version
    elseif info.family == "bsd" then
      -- Most BSDs don't ship /etc/os-release; fall back to uname.
      info.distro = sysname:lower()
      info.distro_name = sysname
    end
  end

  cached = info
  return info
end

---@return boolean
function M.is_windows()
  return M.get_os().family == "windows"
end

---@return boolean
function M.is_macos()
  return M.get_os().family == "macos"
end

---@return boolean
function M.is_linux()
  return M.get_os().family == "linux"
end

---@return boolean
function M.is_bsd()
  return M.get_os().family == "bsd"
end

return M
