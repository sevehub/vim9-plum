vim9script

# plum - entry point: commands, startup. Logic lives in autoload/plum.vim

if exists('g:loaded_plum')
  finish
endif
g:loaded_plum = 1

import autoload 'plum.vim'

def g:PlumComplete(ArgLead: string, CmdLine: string, CursorPos: number): list<string>
  return plum.Names()->filter((_, v) => stridx(v, ArgLead) == 0)
enddef

command! -bang -bar PlumInstall plum.Install(<bang>0)
command! -bang -bar PlumUpdate plum.Update(<bang>0)
command! -bang -bar PlumClean plum.Clean(<bang>0)
command! -bang -bar PlumList plum.List()
command! -nargs=1 -complete=customlist,g:PlumComplete PlumPin plum.Pin(<q-args>)
command! -bar PlumQuit plum.Quit()

plum.Load()

augroup Plum
  autocmd!
  autocmd VimEnter * ++once plum.Check()
augroup END
