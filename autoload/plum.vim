vim9script

# plum - small plugin manager: full git clones, optional commit pins, plugin
# list in ~/.vimplugins. Requires Vim 9.0 or later. See :help plum

# ---------------------------------------------------------------- constants

const MARKS: dict<string> = {pending: ' ', running: '~', ok: '+', skip: '=', fail: '!'}

# Directory of the manager itself, which :PlumClean never removes.
const SELF_DIR = tr(resolve(fnamemodify(expand('<script>:p'), ':h:h')), '\', '/')

# -------------------------------------------------------------------- state

var plugins: list<dict<any>> = []
var tasks: list<dict<any>> = []
var running = 0
var failed = 0
var sync_mode = false
var popup_id = 0
var run_title = ''
var self_updated = false

# ------------------------------------------------------------------ helpers

def IsSelf(path: string): bool
  const p = substitute(tr(resolve(fnamemodify(path, ':p')), '\', '/'), '/$', '', '')
  return p == substitute(SELF_DIR, '/$', '', '')
enddef

def Opt(name: string, fallback: any): any
  return get(g:, 'plum_' .. name, fallback)
enddef

def Warn(msg: string)
  echohl WarningMsg
  echomsg 'plum: ' .. msg
  echohl None
enddef

def Root(): string
  const custom: string = Opt('root', '')
  const base = custom != '' ? custom : (has('win32') ? '~/vimfiles' : '~/.vim') .. '/pack/plum/opt'
  return tr(expand(base), '\', '/')
enddef

# Turns one entry of g:plum_plugins into {name, spec, url, commit, dir}.
# Returns an empty dictionary for an invalid entry.
def Normalize(item: any): dict<any>
  var spec: dict<any> = {}
  if type(item) == v:t_string
    spec.url = item
  elseif type(item) == v:t_dict
    spec = copy(item)
  else
    return {}
  endif

  var url = ''
  const u = get(spec, 'url', '')
  if type(u) == v:t_string
    url = u
  endif
  if url == '' || url =~# '^-'
    return {}
  endif

  var name = ''
  const n = get(spec, 'name', '')
  if type(n) == v:t_string && n != ''
    name = n
  else
    name = fnamemodify(substitute(url, '\(\.git\)\=/\=$', '', ''), ':t')
  endif
  if name == '' || name =~# '[/\\]' || name =~# '^[.-]'
    return {}
  endif

  var commit = ''
  const c = get(spec, 'commit', '')
  if type(c) == v:t_string
    commit = c
  endif
  if commit =~# '^-'
    return {}
  endif

  var fts: list<string> = []
  const f = get(spec, 'ft', [])
  if type(f) == v:t_string
    fts = [f]
  elseif type(f) == v:t_list
    fts = filter(copy(f), (_, x) => type(x) == v:t_string)
  endif
  if !empty(filter(copy(fts), (_, x) => x !~# '^[A-Za-z0-9_.-]\+$'))
    return {}
  endif

  const github = url =~# '^[A-Za-z0-9_.-]\+/[A-Za-z0-9_.-]\+$'
  return {
    name: name,
    spec: url,
    url: github ? 'https://github.com/' .. url : url,
    commit: commit,
    ft: fts,
    dir: Root() .. '/' .. name,
  }
enddef

# Sources the plugin list file and normalizes g:plum_plugins.
export def Load()
  plugins = []
  const file = expand(Opt('file', '~/.vimplugins'))
  if !filereadable(file)
    return
  endif
  unlet! g:plum_plugins
  try
    execute 'source' fnameescape(file)
  catch
    Warn($'cannot source {file}: {v:exception}')
    return
  endtry
  const raw = get(g:, 'plum_plugins', [])
  if type(raw) != v:t_list
    Warn('g:plum_plugins must be a list')
    return
  endif
  var seen: list<string> = []
  for item in raw
    const e = Normalize(item)
    if empty(e)
      Warn($'ignored invalid entry {string(item)}')
    elseif index(seen, e.name) >= 0
      Warn($'duplicate name {e.name} ignored')
    else
      seen->add(e.name)
      plugins->add(e)
    endif
  endfor
enddef

export def Check()
  const missing = plugins->copy()->filter((_, p) => !isdirectory(p.dir))
  if !empty(missing)
    Warn($'{len(missing)} plugin(s) not installed, run :PlumInstall')
  endif
enddef

def LoadNow(name: string)
  try
    execute 'packadd' fnameescape(name)
  catch
    Warn($'cannot load {name}: {v:exception}')
  endtry
enddef

# Loads a plugin on the first matching FileType event. The loaders for
# filetype plugins, indent and syntax already ran for the current buffer
# before the plugin was on the runtimepath, so they are run again.
def LoadForFiletype(name: string)
  LoadNow(name)
  unlet! b:did_ftplugin b:did_indent
  for group in ['filetypeplugin', 'filetypeindent', 'syntaxset']
    if exists($'#{group}#FileType')
      execute $'silent! doautocmd <nomodeline> {group} FileType'
    endif
  endfor
enddef

# Loads every installed plugin in list order, except plugins with an ft key,
# which are loaded when a buffer of that filetype appears. This runs at startup, after the
# list file has been sourced, so variables set in that file are visible when
# the plugin scripts run.
export def Activate()
  augroup PlumFiletype
    autocmd!
  augroup END
  for p in plugins
    if !isdirectory(p.dir)
      continue
    endif
    if empty(p.ft)
      LoadNow(p.name)
    else
      augroup PlumFiletype
        execute $'autocmd FileType {join(p.ft, ",")} ++once LoadForFiletype({string(p.name)})'
      augroup END
    endif
  endfor
enddef

export def Names(): list<string>
  return plugins->mapnew((_, p) => p.name)
enddef

# ------------------------------------------------------------------- popup

def PopupFilter(id: number, key: string): bool
  if key == 'q' || key == "\<Esc>"
    popup_close(id)
    return true
  endif
  return false
enddef

def PopupClosed(id: number, result: any)
  popup_id = 0
enddef

def OpenPopup()
  if popup_id != 0
    popup_close(popup_id)
  endif
  popup_id = popup_create([' starting...'], {
    title: $' {run_title} ',
    pos: 'center',
    minwidth: 48,
    maxheight: 20,
    padding: [0, 1, 0, 1],
    border: [],
    filter: PopupFilter,
    callback: PopupClosed,
    mapping: false,
  })
enddef

def AllDone(): bool
  for t in tasks
    if t.state == 'pending' || t.state == 'running'
      return false
    endif
  endfor
  return true
enddef

def Lines(): list<string>
  var out: list<string> = []
  var counts: dict<number> = {pending: 0, running: 0, ok: 0, skip: 0, fail: 0}
  for t in tasks
    counts[t.state] += 1
    if t.state != 'skip'
      out->add($' {MARKS[t.state]} {t.p.name}  {t.msg}')
    endif
  endfor
  if empty(out)
    out->add(' nothing to do')
  endif
  if AllDone()
    out->add('')
    out->add($' {counts.ok} done, {counts.skip} unchanged, {counts.fail} failed   (q closes)')
  endif
  return out
enddef

def Render()
  if sync_mode || popup_id == 0
    return
  endif
  popup_settext(popup_id, Lines())
enddef

# ------------------------------------------------------------------- engine

# Reads the commit that HEAD points to without starting a process.
def ReadHead(dir: string): string
  const head = dir .. '/.git/HEAD'
  if !filereadable(head)
    return ''
  endif
  const first = readfile(head, '', 1)
  if empty(first)
    return ''
  endif
  if first[0] !~# '^ref: '
    return first[0]
  endif
  const ref = first[0][5 :]
  const loose = dir .. '/.git/' .. ref
  if filereadable(loose)
    const l = readfile(loose, '', 1)
    return empty(l) ? '' : l[0]
  endif
  const packed = dir .. '/.git/packed-refs'
  if filereadable(packed)
    for line in readfile(packed)
      const m = matchlist(line, '^\(\x\+\) \(.*\)$')
      if !empty(m) && m[2] == ref
        return m[1]
      endif
    endfor
  endif
  return ''
enddef

# Pseudo plugin that stands for the manager itself.
def SelfEntry(): dict<any>
  return {name: 'plum (self)', spec: '', url: '', commit: '', ft: [], dir: SELF_DIR, self: true}
enddef

def MakeTask(p: dict<any>, action: string): dict<any>
  var steps: list<list<string>> = []
  var msg = ''
  if get(p, 'self', false)
    if isdirectory(p.dir .. '/.git')
      steps->add(['git', '-C', p.dir, 'pull', '--ff-only', '--quiet'])
    else
      msg = 'not a git clone'
    endif
  elseif !isdirectory(p.dir)
    steps->add(['git', 'clone', '--quiet', '--', p.url, p.dir])
    if p.commit != ''
      steps->add(['git', '-C', p.dir, 'checkout', '--quiet', p.commit, '--'])
    endif
  elseif p.commit != ''
    if action == 'install'
      steps->add(['git', '-C', p.dir, 'fetch', '--quiet'])
      steps->add(['git', '-C', p.dir, 'checkout', '--quiet', p.commit, '--'])
    else
      msg = 'pinned'
    endif
  elseif action == 'update'
    steps->add(['git', '-C', p.dir, 'pull', '--ff-only', '--quiet'])
  else
    msg = 'installed'
  endif
  return {
    p: p,
    steps: steps,
    step: 0,
    state: empty(steps) ? 'skip' : 'pending',
    msg: msg,
    err: [],
    job: v:null,
    before: get(p, 'self', false) ? ReadHead(p.dir) : '',
  }
enddef

def Finish()
  var nok = 0
  var nskip = 0
  failed = 0
  for t in tasks
    if t.state == 'fail'
      failed += 1
    elseif t.state == 'skip'
      nskip += 1
    else
      nok += 1
      if isdirectory(t.p.dir .. '/doc')
        silent! execute 'helptags' fnameescape(t.p.dir .. '/doc')
      endif
    endif
  endfor
  Render()
  if sync_mode
    for t in tasks
      if t.state == 'fail'
        echomsg $'plum: {t.p.name}: {t.msg}'
      endif
    endfor
  endif
  echomsg $'plum: {nok} done, {nskip} unchanged, {failed} failed'
  if self_updated
    echomsg 'plum: Plum itself was updated, restart Vim to use the new version'
  endif
enddef

def StepDone(t: dict<any>, status: number)
  running -= 1
  if status != 0
    t.state = 'fail'
    t.msg = empty(t.err) ? $'git exited with {status}' : t.err[-1]
  elseif t.step + 1 < len(t.steps)
    t.step += 1
    t.state = 'pending'
  else
    t.state = 'ok'
    if get(t.p, 'self', false)
      const after = ReadHead(t.p.dir)
      if t.before != '' && after != '' && after != t.before
        t.msg = $'{t.before[0 : 6]} -> {after[0 : 6]}, restart Vim'
        self_updated = true
      else
        t.msg = 'up to date'
      endif
    endif
  endif
  Pump()
enddef

def StartStep(t: dict<any>)
  const argv: list<string> = t.steps[t.step]
  t.state = 'running'
  t.err = []
  t.job = job_start(argv, {
    in_io: 'null',
    out_io: 'null',
    err_mode: 'nl',
    err_cb: (ch, msg) => add(t.err, msg),
    exit_cb: (j, status) => StepDone(t, status),
  })
  if job_status(t.job) == 'fail'
    t.state = 'fail'
    t.msg = 'could not start git'
  else
    running += 1
  endif
enddef

def Pump()
  const limit: number = max([1, Opt('jobs', 4)])
  for t in tasks
    if running >= limit
      break
    endif
    if t.state == 'pending'
      StartStep(t)
    endif
  endfor
  Render()
  if !sync_mode && running == 0 && AllDone()
    Finish()
  endif
enddef

def Begin(action: string, sync: bool)
  if running > 0
    Warn('a run is already in progress')
    return
  endif
  Load()
  if action != 'self' && empty(plugins)
    Warn($'no plugins found, check {Opt("file", "~/.vimplugins")} and g:plum_plugins')
    return
  endif
  if !executable('git')
    Warn('git was not found in the path')
    return
  endif
  var list: list<dict<any>> = []
  if action == 'self'
    list = [MakeTask(SelfEntry(), 'update')]
  else
    mkdir(Root(), 'p')
    if action == 'update' && Opt('self_update', 1) != 0
      list->add(MakeTask(SelfEntry(), 'update'))
    endif
    list->extend(plugins->mapnew((_, p) => MakeTask(p, action)))
  endif
  tasks = list
  self_updated = false
  failed = 0
  sync_mode = sync
  run_title = 'Plum ' .. action
  if !sync
    OpenPopup()
  endif
  Pump()
  if sync
    while !AllDone()
      for t in tasks
        if t.state == 'running'
          job_status(t.job)
        endif
      endfor
      sleep 20m
    endwhile
    Finish()
  endif
enddef

# ----------------------------------------------------------------- commands

export def Install(sync: bool)
  Begin('install', sync)
enddef

export def Update(sync: bool)
  Begin('update', sync)
enddef

export def SelfUpdate(sync: bool)
  Begin('self', sync)
enddef

export def Clean(force: bool)
  Load()
  if empty(plugins)
    Warn('plugin list is empty or could not be loaded, refusing to clean')
    return
  endif
  const root = Root()
  const known = Names()
  var stale: list<string> = []
  for path in glob(root .. '/*', true, true)
    const name = fnamemodify(path, ':t')
    if isdirectory(path) && name != 'plum' && !IsSelf(path) && index(known, name) < 0
      stale->add(path)
    endif
  endfor
  if empty(stale)
    echomsg 'plum: nothing to clean'
    return
  endif
  const names = stale->mapnew((_, s) => fnamemodify(s, ':t'))
  if !force
    const noun = len(stale) == 1 ? 'directory' : 'directories'
    const answer = confirm($"Remove {len(stale)} {noun} from {root}?\n" .. join(names, "\n"), "&Yes\n&No", 2)
    if answer != 1
      return
    endif
  endif
  for path in stale
    delete(path, 'rf')
  endfor
  echomsg $'plum: removed {join(names, ", ")}'
enddef

export def List()
  Load()
  if empty(plugins)
    Warn('no plugins found')
    return
  endif
  for p in plugins
    const state = isdirectory(p.dir) ? 'installed' : 'missing'
    const pin = p.commit == '' ? 'tracking' : 'pin ' .. p.commit[0 : 11]
    const on = empty(p.ft) ? '' : 'ft=' .. join(p.ft, ',')
    echo printf('%-26s %-10s %-20s %s', p.name, state, pin, on)
  endfor
enddef

def PinDone(p: dict<any>, out: list<string>)
  if empty(out)
    Warn($'could not read the commit of {p.name}')
    return
  endif
  const on = empty(p.ft) ? '' : ', ft: ' .. string(p.ft)
  const line = "{url: '" .. p.spec .. "', commit: '" .. out[0] .. "'" .. on .. "},"
  setreg('"', line)
  echomsg 'plum: ' .. line .. '  (copied to the unnamed register)'
enddef

export def Pin(name: string)
  Load()
  const idx = index(Names(), name)
  if idx < 0
    Warn($'{name} is not in the plugin list')
    return
  endif
  const p = plugins[idx]
  if !isdirectory(p.dir)
    Warn($'{name} is not installed')
    return
  endif
  var out: list<string> = []
  job_start(['git', '-C', p.dir, 'rev-parse', '--short=12', 'HEAD'], {
    in_io: 'null',
    err_io: 'null',
    out_cb: (ch, msg) => add(out, msg),
    close_cb: (ch) => PinDone(p, out),
  })
enddef

# Exits Vim with status 1 when the last run had failures, otherwise 0.
export def Quit()
  if failed > 0
    cquit
  else
    qall!
  endif
enddef
