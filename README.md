<p align="center">
  <img src="assets/plum.svg" alt="plum" width="160" height="160">
</p>

<h1 align="center">plum</h1>

<p align="center">Chubby git clones with a pin. A small plugin manager for Vim, written in vim9script.</p>

Plum keeps the whole plugin setup in one small file in the home directory. Every plugin is a full git clone placed in the native package directory, so Vim loads it without any configuration, and any plugin can optionally be pinned to an exact commit. The `.vimrc` needs no lines at all. Plum is part of the SeveTech toolbox ("Tools for Productivity Enthusiasts") and is intended to serve as a compact, readable example of vim9script, since the manager consists of roughly 440 lines.

## Design

Vim already loads everything below `pack/*/start/` at startup, which means that a plugin manager does not have to load anything. Plum only wraps the git operations around that mechanism: cloning, updating, pinning and removing. The list of plugins is a vim9script file named `.vimplugins` in the home directory, which is sourced by the manager at startup. The file can be kept in a dotfiles repository, and a single bootstrap command restores the complete setup on a new machine.

Full clones are used instead of shallow clones because a pin to an arbitrary commit requires the history to be present. Submodules were considered and rejected, since they add a detached HEAD after every update, a multi-step removal, and the need to remember the recurse flag on every clone.

## Requirements

Vim 9.0 or later and git are required. Neovim is not supported, because it does not implement vim9script. The `vim` that is used for batch runs must be the console binary (`vim.exe` on Windows, not `gvim.exe`).

## Installation

Plum installs itself like any other package. The directory is `~/.vim/pack/plum/start/plum` on Linux and macOS, and `~/vimfiles/pack/plum/start/plum` on Windows.

### Bash

```sh
git clone https://github.com/sevehub/vim9-plum ~/.vim/pack/plum/start/plum

cat > ~/.vimplugins <<'EOF'
vim9script
g:plum_plugins = [
  {url: 'tpope/vim-surround'},
  {url: 'junegunn/fzf.vim', commit: 'a1b2c3d4e5f6'},
  {url: 'sevehub/vimhud'},
]
EOF

vim -es -N -u NONE -c 'packloadall' -c 'PlumInstall!' -c 'PlumQuit'
```

### PowerShell

```powershell
git clone https://github.com/sevehub/vim9-plum "$HOME\vimfiles\pack\plum\start\plum"

$list = @'
vim9script
g:plum_plugins = [
  {url: 'tpope/vim-surround'},
  {url: 'junegunn/fzf.vim', commit: 'a1b2c3d4e5f6'},
  {url: 'sevehub/vimhud'},
]
'@
[System.IO.File]::WriteAllText("$HOME\.vimplugins", $list)

vim -es -N -u NONE -c "packloadall" -c "PlumInstall!" -c "PlumQuit"
```

The file is written with `WriteAllText` because Windows PowerShell 5.1 would otherwise add a byte order mark, and a mark in front of `vim9script` prevents the first line from being recognized. The exit status of the batch call is 0 when every plugin succeeded and 1 otherwise, so `$LASTEXITCODE` in PowerShell and `$?` in bash can be used in scripts.

## The plugin list

The file `~/.vimplugins` is an ordinary script that has to set `g:plum_plugins` to a list. Both the vim9script form shown above and the legacy form `let g:plum_plugins = [...]` are accepted. An entry is either a string or a dictionary.

| Key | Meaning |
| --- | --- |
| `url` | `user/repo` for GitHub, or any URL or path understood by `git clone` |
| `commit` | Optional pin: a commit hash, tag or branch to which the plugin is checked out |
| `name` | Optional directory name, derived from the last part of the URL by default |

A plain string such as `'tpope/vim-surround'` is the short form of `{url: 'tpope/vim-surround'}`. Invalid entries and duplicate names are reported and ignored. The list is read again before every command, so edits take effect without restarting Vim.

## Commands

| Command | Effect |
| --- | --- |
| `:PlumInstall` | Clones missing plugins, and aligns pinned plugins with their commit |
| `:PlumUpdate` | Runs `git pull --ff-only` for every unpinned plugin |
| `:PlumClean` | Removes directories that are not in the list, after a confirmation |
| `:PlumList` | Shows each plugin as installed or missing, and as tracking or pinned |
| `:PlumPin {name}` | Prints the current commit as a ready-made list entry and copies it to the unnamed register |
| `:PlumQuit` | Exits Vim with status 1 after a failed run and 0 otherwise, for batch use |

Inside Vim, `:PlumInstall` and `:PlumUpdate` run in the background and report progress in a popup window, which is closed with `q` or `<Esc>`. Up to four git processes run in parallel. With a bang (`:PlumInstall!`, `:PlumUpdate!`) the command blocks until every plugin is finished and opens no popup, which is the form used in batch calls. With a bang `:PlumClean!` removes without asking. Help tags are generated for every plugin that was cloned or updated, and newly installed plugins are loaded at the next start of Vim.

## Pinning

A pin turns the plugin into a fixed snapshot. The workflow is short: `:PlumPin vim-surround` prints `{url: 'tpope/vim-surround', commit: '...'},` and copies the line, which is then pasted over the old entry in `~/.vimplugins`. Afterwards `:PlumUpdate` skips the plugin, and `:PlumInstall` fetches and checks out the commit, which also applies a changed pin. Removing the `commit` key makes the plugin follow its upstream again, and `git switch -` inside the plugin directory returns it from the detached HEAD to its branch before the next update.

## Using plum from the shell

Both shells can drive the manager without opening an interface. The functions below can be placed in `~/.bashrc` or in the PowerShell profile.

### Bash

```sh
plum() {
  local action="${1:-install}"
  vim -es -N -u NONE -c 'packloadall' -c "Plum${action^}!" -c 'PlumQuit'
}
```

The expansion `${action^}` requires bash 4 or later. Usage: `plum install`, `plum update`, `plum clean`.

### PowerShell

```powershell
function plum {
  param([ValidateSet('install', 'update', 'clean')][string]$Action = 'install')
  $cmd = 'Plum' + $Action.Substring(0, 1).ToUpper() + $Action.Substring(1) + '!'
  vim -es -N -u NONE -c "packloadall" -c $cmd -c "PlumQuit"
  if ($LASTEXITCODE -ne 0) { Write-Warning "plum $Action reported failures" }
}
```

Usage: `plum install`, `plum update`, `plum clean`. The batch form starts Vim with `-u NONE`, so options that are set in the `.vimrc` are not seen. When `g:plum_root` or `g:plum_file` is configured there, `-u NONE` is replaced with `-u ~/.vimrc` in bash, or `-u "$HOME\.vimrc"` in PowerShell. Vim may print nothing in batch mode, and the exit status is then the reliable result; adding `-V1` to the command line usually makes the messages visible.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `g:plum_file` | `'~/.vimplugins'` | Location of the plugin list |
| `g:plum_root` | `'~/.vim/pack/plum/start'` | Directory for the clones (`~/vimfiles/...` on Windows) |
| `g:plum_jobs` | `4` | Number of git processes that run in parallel |

## How it works

At startup `plugin/plum.vim` defines the commands and sources the list. A message at `VimEnter` reports plugins that are listed but not yet installed. Each plugin becomes a task with a short sequence of git steps: a clone, followed by a checkout when a pin is given, or a fetch and checkout for an existing pinned clone. The steps run through `job_start()` with a callback on exit that starts the next step and refreshes the popup. In batch mode the same engine is polled with `job_status()` inside a loop that sleeps in 20 ms steps, which keeps one code path for both modes. Arguments are passed to git as a list, so no shell quoting is involved, and a `--` separator prevents a URL or a commit from being interpreted as an option.

## Limitations

A removed pin leaves the plugin in a detached HEAD until `git switch -` is run, and `:PlumUpdate` reports a failure for it in the meantime. Only `pack/plum/start` is managed, so plugins that should load on demand through `:packadd` are not supported yet. The shorthand `user/repo` always means GitHub, which means that a relative local path with exactly one slash has to be written with a leading `./`. Submodules inside a plugin are not initialized. `:PlumClean` removes every directory below the root that is not listed, except the directory named `plum`, and it refuses to run when the list is empty or cannot be loaded.

## Repository layout

```
plugin/plum.vim      commands, startup, VimEnter check
autoload/plum.vim    list handling, task engine, popup, commands
doc/plum.txt         help file, available through :help plum
assets/plum.svg      logo
```

After installation, `:helptags ALL` generates the tags of the plum help file.

## License

MIT.
