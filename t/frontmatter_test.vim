" Tests for frontmatter parsing

function! s:TestPluginLoads()
  call testify#assert#equals(exists('g:loaded_md_age'), 0)
endfunction
call testify#it('plugin not loaded in test context', function('s:TestPluginLoads'))

function! s:TestHasFrontmatter()
  let lines = ['---', 'title: Test', '---', 'body']
  call testify#assert#equals(mdage#HasFrontmatter(lines), 1)
endfunction
call testify#it('detects frontmatter', function('s:TestHasFrontmatter'))

function! s:TestNoFrontmatter()
  let lines = ['# Just a heading', 'body']
  call testify#assert#equals(mdage#HasFrontmatter(lines), 0)
endfunction
call testify#it('detects missing frontmatter', function('s:TestNoFrontmatter'))

function! s:TestEmptyFile()
  let lines = []
  call testify#assert#equals(mdage#HasFrontmatter(lines), 0)
endfunction
call testify#it('handles empty file', function('s:TestEmptyFile'))
