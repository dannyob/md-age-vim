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

function! s:TestParseFrontmatter()
  let lines = ['---', 'title: Test', 'age-encrypt: yes', '---', 'body']
  let result = mdage#ParseFrontmatter(lines)
  call testify#assert#equals(result.end_line, 3)
  call testify#assert#equals(result.fields['age-encrypt'], 'yes')
  call testify#assert#equals(result.fields['title'], 'Test')
endfunction
call testify#it('parses frontmatter fields', function('s:TestParseFrontmatter'))

function! s:TestParseFrontmatterPreservesAll()
  let lines = ['---', 'title: My Doc', 'date: 2025-01-07', 'age-encrypt: yes', '---', 'body']
  let result = mdage#ParseFrontmatter(lines)
  call testify#assert#equals(len(result.fields), 3)
endfunction
call testify#it('preserves all frontmatter fields', function('s:TestParseFrontmatterPreservesAll'))
