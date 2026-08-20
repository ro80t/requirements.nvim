# requirements.nvim

Declare the external (non-Neovim) tools your plugin needs, with a different
install command per OS/distro, and let requirements.nvim install whatever is
missing — in parallel, and blocking until everything finishes.

```lua
require("requirements").setup({
  deno = {
    windows = "winget install -e --id DenoLand.Deno",
    macos = "brew install deno",
    ubuntu = "sudo apt install -y deno", -- distro id (/etc/os-release ID)
    arch = "sudo pacman -S --noconfirm deno",
    freebsd = "sudo pkg install -y deno",
  },
})

require("requirements").ensure({ "deno" })
```

`setup()` only registers commands (safe to call many times, from many
plugins). `ensure()` is what actually checks `executable()` for each name,
launches install commands for whatever is missing **in parallel**, and
blocks until they have all finished (or `opts.timeout` elapses) before
returning.

## Command resolution

For a dependency name, the key looked up in its table is, in order:

1. The current distro id (`/etc/os-release` `ID`, e.g. `"ubuntu"`)
2. Each id in `ID_LIKE` (e.g. `"debian"` for Ubuntu)
3. The OS family: `"windows"`, `"macos"`, `"linux"`, or `"bsd"`

See `lua/requirements/environment.lua` for the underlying OS/distro
detection (`require("requirements.environment").get_os()`).

## Plugin manager integration

Every manager ultimately just needs to call `require("requirements").ensure(...)`
at some point before your plugin's dependents rely on the external tool.
**mini.deps** and **vim.pack** can run code before the plugin is first
loaded (a true "preinstall" hook), so requirements.nvim ships helpers that
wire this up automatically. Managers that only offer a post-install
build/run hook are just given the spec as an argument, from that hook.

### mini.deps (automatic, pre-load)

```lua
local spec = { deno = { ... } }

MiniDeps.add({
  source = "author/plugin",
  hooks = require("requirements.managers.mini_deps").hooks(spec),
})
```

### vim.pack (automatic, pre-load)

Register the watcher **before** calling `vim.pack.add()`:

```lua
local spec = { deno = { ... } }

require("requirements.managers.vim_pack").watch("plugin", spec)

vim.pack.add({ { src = "https://github.com/author/plugin", name = "plugin" } })
```

### lazy.nvim (post-install)

```lua
{
  "author/plugin",
  build = function()
    require("requirements").setup(spec)
    require("requirements").ensure(vim.tbl_keys(spec))
  end,
}
```

### packer.nvim (post-install)

```lua
use({
  "author/plugin",
  run = function()
    require("requirements").setup(spec)
    require("requirements").ensure(vim.tbl_keys(spec))
  end,
})
```

### vim-plug (post-install)

```vim
Plug 'author/plugin', { 'do': ':lua require("requirements").setup(spec); require("requirements").ensure(vim.tbl_keys(spec))' }
```

### paq-nvim (post-install)

```lua
{
  "author/plugin",
  build = function()
    require("requirements").setup(spec)
    require("requirements").ensure(vim.tbl_keys(spec))
  end,
}
```

## API

- `require("requirements").setup(spec)` — merge `spec` into the registry.
- `require("requirements").ensure(names?, opts?)` — install whatever in
  `names` (default: everything registered) isn't already on `PATH`, in
  parallel, blocking until done. Returns a list of
  `{ name, status, code?, stderr? }`, where `status` is one of
  `"already_installed"`, `"installed"`, `"failed"`, `"unsupported"`, or
  `"timeout"`.
  - `opts.timeout` — max time to wait, in ms (default `300000`, 5 min).
  - `opts.notify` — whether to `vim.notify` the outcome (default `true`).
- `require("requirements").is_installed(name)` — `executable(name) == 1`.
- `require("requirements").resolve_command(name)` — the install command
  that would be used for `name` on the current environment, or `nil`.
