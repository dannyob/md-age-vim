" Tests for frontmatter parsing

function! s:TestPluginLoads()
  call testify#assert#equals(exists('g:loaded_md_age'), 0)
endfunction
call testify#it('plugin not loaded in test context', function('s:TestPluginLoads'))
