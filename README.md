<p align="center">
  <img src="assets/plum.svg" alt="plum" width="160" height="160">
</p>

<h1 align="center">plum</h1>

<p align="center">Git clones with a pin. A small plugin manager for Vim, written in vim9script.</p>

Plum keeps the whole plugin setup in one small file in the home directory. Every plugin is a full git clone placed in a native package directory, any plugin can optionally be pinned to an exact commit, and the variables of the plugins are kept in the same file. The `.vimrc` needs no plugin lines at all. Plum is part of the SeveTech toolbox ("Tools for Productivity Enthusiasts") and is intended to serve as a compact, readable example of vim9script, since the manager consists of roughly 440 lines.

## Design

Plum wraps the git operations around Vim's native package mechanism: cloning, updating, pinning and removing. The list of plugins is a vim9script file named `.vimplugins` in the home directory. At startup the manager sources this file first and then loads the plugins with `:packadd`, in list order. The clones therefore live in `pack/plum/opt/` and not in `pack/plum/start/`, because Vim loads start plugins in alphabetical order, which can be before the list file has been sourced, and a plugin that reads its variables at load time would not see them. The file can be kept in a dotfiles repository, and a single bootstrap command restores the complete setup on a new machine.

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
| `ft` | Optional filetype or list of filetypes; the plugin is loaded only when a buffer of one of these types appears |

A plain string such as `'tpope/vim-surround'` is the short form of `{url: 'tpope/vim-surround'}`. Invalid entries and duplicate names are reported and ignored. The list is read again before every command, so edits take effect without restarting Vim.

## Plugin variables

The list file is an ordinary script, so the settings of the plugins can be placed in it, above the list. The `.vimrc` then contains no plugin configuration, and the whole plugin setup is restored with the single file.

```vim
vim9script

g:vimhud_keybox_timeout = 3000
g:vimhud_keybox_pos = 'center'

g:plum_plugins = [
  {url: 'tpope/vim-surround'},
  {url: 'sevehub/vimhud'},
]
```

Plum sources the file before any plugin is loaded, so the variables are set when the plugin scripts run. Settings of Plum itself, such as `g:plum_jobs` and `g:plum_root`, can be placed in the file as well. Only `g:plum_file`, which names the file, has to be set in the `.vimrc`.

## Loading by filetype

A plugin that is only useful for some filetypes does not have to be loaded in every session. The `ft` key names the filetypes, and Plum registers a `FileType` autocommand instead of loading the plugin at startup.

```vim
g:plum_plugins = [
  {url: 'tpope/vim-surround'},
  {url: 'vim-python/python-syntax', ft: 'python'},
  {url: 'user/c-helpers', ft: ['c', 'cpp']},
]
```

When the first buffer of a matching type is opened, the plugin is added with `:packadd`, and Vim is then asked to run the filetype plugin, indent and syntax loaders again for that buffer, because they ran before the plugin was on the runtimepath. The autocommand fires once, so the cost is paid at most once per session and only in sessions that need it. Startup time falls with every plugin that is restricted in this way, and plugins that define commands or mappings for a language do not appear in unrelated buffers.

Two rules apply. A plugin that ships its own filetype detection (an `ftdetect` directory) must not use `ft`, because the detection has to be active before any file is opened. Commands that a plugin defines in its `plugin` directory are unavailable until the first matching buffer has been loaded. `:PlumList` shows the filetypes of each plugin.

## Commands

| Command | Effect |
| --- | --- |
| `:PlumInstall` | Clones missing plugins, and aligns pinned plugins with their commit |
| `:PlumUpdate` | Runs `git pull --ff-only` for every unpinned plugin, and for Plum itself |
| `:PlumSelfUpdate` | Updates only Plum itself from its remote repository |
| `:PlumClean` | Removes directories that are not in the list, after a confirmation |
| `:PlumList` | Shows each plugin as installed or missing, and as tracking or pinned |
| `:PlumPin {name}` | Prints the current commit as a ready-made list entry and copies it to the unnamed register |
| `:PlumQuit` | Exits Vim with status 1 after a failed run and 0 otherwise, for batch use |

Inside Vim, `:PlumInstall` and `:PlumUpdate` run in the background and report progress in a popup window, which is closed with `q` or `<Esc>`. Up to four git processes run in parallel. With a bang (`:PlumInstall!`, `:PlumUpdate!`) the command blocks until every plugin is finished and opens no popup, which is the form used in batch calls. With a bang `:PlumClean!` removes without asking. Help tags are generated for every plugin that was cloned or updated, and newly installed plugins are loaded at the next start of Vim.

## Updating Plum itself

Plum is a git clone like the plugins it manages, so it can update itself. `:PlumSelfUpdate` runs `git pull --ff-only` in the directory of the manager, and `:PlumUpdate` does the same as its first task, which is why a normal update keeps the manager current. When the remote repository has new commits, the popup shows the old and the new commit, for example `a1b2c3d -> e4f5a6b, restart Vim`, and a message repeats the advice. The running session continues with the version that was already loaded, and the new version is used at the next start of Vim. The help tags of Plum are regenerated as well.

Self update needs Plum to be a git clone, which is the case when it was installed with the commands of this README. A copy that was extracted from an archive is reported as not being a git clone and is skipped. A local checkout that is used for development should set `g:plum_self_update = 0`, so that `:PlumUpdate` does not pull into the working copy. A pull that cannot be fast-forwarded, for example after local edits, fails with the message of git and changes nothing.

## Pinning

A pin turns the plugin into a fixed snapshot. The workflow is short: `:PlumPin vim-surround` prints `{url: 'tpope/vim-surround', commit: '...'},` and copies the line, which is then pasted over the old entry in `~/.vimplugins`. Afterwards `:PlumUpdate` skips the plugin, and `:PlumInstall` fetches and checks out the commit, which also applies a changed pin. Removing the `commit` key makes the plugin follow its upstream again, and `git switch -` inside the plugin directory returns it from the detached HEAD to its branch before the next update.

## Using plum from the shell

Both shells can drive the manager without opening an interface. The functions below can be placed in `~/.bashrc` or in the PowerShell profile.

### Bash

```sh
plum() {
  local action="${1:-install}"
  [ "$action" = self ] && action=SelfUpdate
  vim -es -N -u NONE -c 'packloadall' -c "Plum${action^}!" -c 'PlumQuit'
}
```

The expansion `${action^}` requires bash 4 or later. Usage: `plum install`, `plum update`, `plum clean`, `plum self`.

### PowerShell

```powershell
function plum {
  param([ValidateSet('install', 'update', 'clean', 'self')][string]$Action = 'install')
  $name = if ($Action -eq 'self') { 'SelfUpdate' } else { $Action.Substring(0, 1).ToUpper() + $Action.Substring(1) }
  $cmd = 'Plum' + $name + '!'
  vim -es -N -u NONE -c "packloadall" -c $cmd -c "PlumQuit"
  if ($LASTEXITCODE -ne 0) { Write-Warning "plum $Action reported failures" }
}
```

Usage: `plum install`, `plum update`, `plum clean`, `plum self`. The batch form starts Vim with `-u NONE`, so options that are set in the `.vimrc` are not seen, while the variables in `~/.vimplugins` are. Only a changed `g:plum_file` has to be set in the `.vimrc`, and `-u NONE` is then replaced with `-u ~/.vimrc` in bash, or `-u "$HOME\.vimrc"` in PowerShell. Vim may print nothing in batch mode, and the exit status is then the reliable result; adding `-V1` to the command line usually makes the messages visible.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `g:plum_file` | `'~/.vimplugins'` | Location of the plugin list |
| `g:plum_root` | `'~/.vim/pack/plum/opt'` | Directory for the clones (`~/vimfiles/...` on Windows) |
| `g:plum_jobs` | `4` | Number of git processes that run in parallel |
| `g:plum_self_update` | `1` | When `0`, `:PlumUpdate` leaves Plum itself alone |

## How it works

At startup `plugin/plum.vim` defines the commands, sources the list, and then loads every installed plugin with `:packadd`, in list order, so that the variables set in the list are visible when the plugin scripts run. Plugins with an `ft` key are loaded later, by a `FileType` autocommand. A message at `VimEnter` reports plugins that are listed but not yet installed. Each plugin becomes a task with a short sequence of git steps: a clone, followed by a checkout when a pin is given, or a fetch and checkout for an existing pinned clone. The steps run through `job_start()` with a callback on exit that starts the next step and refreshes the popup. In batch mode the same engine is polled with `job_status()` inside a loop that sleeps in 20 ms steps, which keeps one code path for both modes. Arguments are passed to git as a list, so no shell quoting is involved, and a `--` separator prevents a URL or a commit from being interpreted as an option.

## Limitations

A removed pin leaves the plugin in a detached HEAD until `git switch -` is run, and `:PlumUpdate` reports a failure for it in the meantime. Only `pack/plum/opt` is managed. Plugins load at startup or on a filetype, but not yet on a command or a key mapping. Re-running the filetype loaders for the current buffer can source a runtime `ftplugin` a second time, which is harmless for scripts that guard against repetition and can duplicate buffer-local mappings for scripts that do not. A custom `g:plum_root` has to be a `pack/*/opt` directory inside `'packpath'`, because `:packadd` is used for loading. The shorthand `user/repo` always means GitHub, which means that a relative local path with exactly one slash has to be written with a leading `./`. Submodules inside a plugin are not initialized. `:PlumClean` removes every directory below the root that is not listed, except the directory named `plum`, and it refuses to run when the list is empty or cannot be loaded.

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
