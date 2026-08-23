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
-- or
require("requirements").ensureAll()
```

`setup()` only registers commands (safe to call many times, from many
plugins). `ensure()` is what actually checks `executable()` for each name,
launches install commands for whatever is missing **in parallel**, and
blocks until they have all finished (or `opts.timeout` elapses) before
returning. `ensure_all()` is a shorthand for `ensure()` with no `names`,
i.e. it installs everything that has been registered via `setup()`.

## Command resolution

For a dependency name, the key looked up in its table is, in order:

1. The current distro id (`/etc/os-release` `ID`, e.g. `"ubuntu"`)
2. Each id in `ID_LIKE` (e.g. `"debian"` for Ubuntu)
3. The OS family: `"windows"`, `"macos"`, `"linux"`, or `"bsd"`

See `lua/requirements/environment.lua` for the underlying OS/distro
detection (`require("requirements.environment").get_os()`).

### Narrowing by OS version / CPU architecture

The value for a distro/family key doesn't have to be a plain command
string — it can also be a table with an optional `version` and/or `arch`
sub-table, to further narrow the command down. Both are optional and
independent: use only `version`, only `arch`, both nested together, or
neither (a plain string), whatever a given dependency needs.

```lua
require("requirements").setup({
  somepkg = {
    ubuntu = {
      version = {
        ["22.04"] = {
          arch = {
            x86_64 = "sudo apt install -y somepkg-amd64",
            aarch64 = "sudo apt install -y somepkg-arm64",
          },
        },
        ["20.04"] = "sudo apt install -y somepkg-legacy", -- any arch
      },
      -- fallback for any other ubuntu version: match by arch only
      arch = {
        x86_64 = "sudo apt install -y somepkg-amd64",
      },
    },
  },
})
```

`version` is matched against the distro's `VERSION_ID` (from
`/etc/os-release`) on Linux/BSD, or the OS release string elsewhere.
`arch` is matched against `uname`'s `machine` field (e.g. `"x86_64"`,
`"arm64"`, `"aarch64"`). If `version` is present but doesn't match the
current OS version, resolution falls back to a sibling `arch` table (as
above) before giving up as unsupported.

#### Version specs (wildcard / caret / range)

A `version` key doesn't have to be an exact string — it can also be an
npm-style spec, checked (in this order after an exact match fails) as a
wildcard, a caret range, or a hyphen range:

```lua
require("requirements").setup({
  somepkg = {
    ubuntu = {
      version = {
        ["24.*"] = "sudo apt install -y somepkg-new", -- wildcard: any 24.x
        ["^22.04"] = "sudo apt install -y somepkg", -- caret: 22.04 <= v < 23.0
        ["18.04-20.04"] = "sudo apt install -y somepkg-old", -- range: 18.04 <= v <= 20.04
      },
    },
  },
})
```

- **Wildcard** (`"1.0.*"`, `"1.*"`) — components before the `*` must match
  exactly; the `*` (and anything after it) matches any value.
- **Caret** (`"^1.0.0"`) — npm semantics: compatible with the given
  version, up to (but excluding) the next version that changes the first
  non-zero component. `^1.2.3` means `>=1.2.3 <2.0.0`, `^0.2.3` means
  `>=0.2.3 <0.3.0`, `^0.0.3` means `>=0.0.3 <0.0.4`.
- **Range** (`"1.0.0-2.0.0"`) — inclusive on both ends.

Versions are compared component-by-component as dot-separated numbers
(missing trailing components count as `0`, so `1.2` == `1.2.0`). If more
than one `version` key would match, which one wins is unspecified — keep
specs non-overlapping.

## Plugin manager integration

Every manager ultimately just needs to call `require("requirements").ensure(...)`
at some point before your plugin's dependents rely on the external tool.
**mini.deps** and **vim.pack** can run code before the plugin is first
loaded (a true "preinstall" hook), so requirements.nvim ships helpers that
wire this up automatically. **No other manager supports a real preinstall
hook** — lazy.nvim, packer.nvim, vim-plug, and paq-nvim only expose a
post-install build/run hook, which runs *after* the plugin's files are
already on disk, not before. For those (and for setups with no plugin
manager at all), the spec is just given as an argument from wherever your
code first has a chance to run — a build/run hook, or your own `init.lua`.

### git submodule / no plugin manager

Without a plugin manager, there's no install/build hook at all, so call
`setup()` and `ensure()` (or `ensure_all()`) yourself, after the plugin has
been added to `runtimepath`. Add requirements.nvim (and the plugin that
needs it) as git submodules, e.g.:

```sh
git submodule add https://github.com/ro80t/requirements.nvim pack/vendor/start/requirements.nvim
git submodule add https://github.com/author/plugin pack/vendor/start/plugin
```

Then, from your `init.lua`, after the submodules are on `runtimepath`
(native packages under `pack/*/start/` are loaded automatically):

```lua
require("requirements").setup({
  deno = {
    windows = "winget install -e --id DenoLand.Deno",
    macos = "brew install deno",
    ubuntu = "sudo apt install -y deno",
    arch = "sudo pacman -S --noconfirm deno",
    freebsd = "sudo pkg install -y deno",
  },
})

require("requirements").ensure_all()
```

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
- `require("requirements").ensure_all(opts?)` — shorthand for
  `ensure(nil, opts)`; installs everything registered.
- `require("requirements").is_installed(name)` — `executable(name) == 1`.
- `require("requirements").resolve_command(name)` — the install command
  that would be used for `name` on the current environment, or `nil`.
