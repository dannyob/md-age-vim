" Tests for frontmatter parsing

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

function! s:TestShouldEncryptYes()
  let parsed = {'fields': {'age-encrypt': 'yes'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt: yes', function('s:TestShouldEncryptYes'))

function! s:TestShouldEncryptNo()
  let parsed = {'fields': {'age-encrypt': 'no'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 0)
endfunction
call testify#it('should not encrypt when age-encrypt: no', function('s:TestShouldEncryptNo'))

function! s:TestShouldEncryptMissing()
  let parsed = {'fields': {'title': 'Test'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 0)
endfunction
call testify#it('should not encrypt when age-encrypt missing', function('s:TestShouldEncryptMissing'))

function! s:TestShouldEncryptNoFrontmatter()
  let parsed = {'fields': {}, 'end_line': -1}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 0)
endfunction
call testify#it('should not encrypt with no frontmatter', function('s:TestShouldEncryptNoFrontmatter'))

" Tests for flexible YAML parsing (issue: frontmatter parsing too strict)
function! s:TestShouldEncryptSingleQuoted()
  let parsed = {'fields': {'age-encrypt': "'yes'"}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt: single quoted yes', function('s:TestShouldEncryptSingleQuoted'))

function! s:TestShouldEncryptDoubleQuoted()
  let parsed = {'fields': {'age-encrypt': '"yes"'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt: double quoted yes', function('s:TestShouldEncryptDoubleQuoted'))

function! s:TestShouldEncryptExtraWhitespace()
  let parsed = {'fields': {'age-encrypt': ' yes'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt has extra whitespace', function('s:TestShouldEncryptExtraWhitespace'))

function! s:TestShouldEncryptTrue()
  let parsed = {'fields': {'age-encrypt': 'true'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt: true', function('s:TestShouldEncryptTrue'))

" YAML 1.1 boolean case variants
function! s:TestShouldEncryptYesUppercase()
  let parsed = {'fields': {'age-encrypt': 'YES'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt: YES', function('s:TestShouldEncryptYesUppercase'))

function! s:TestShouldEncryptOn()
  let parsed = {'fields': {'age-encrypt': 'on'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt: on', function('s:TestShouldEncryptOn'))

function! s:TestShouldEncryptTrueMixedCase()
  let parsed = {'fields': {'age-encrypt': 'True'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt: True', function('s:TestShouldEncryptTrueMixedCase'))

" Explicit false values
function! s:TestShouldNotEncryptFalse()
  let parsed = {'fields': {'age-encrypt': 'false'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 0)
endfunction
call testify#it('should not encrypt when age-encrypt: false', function('s:TestShouldNotEncryptFalse'))

function! s:TestShouldNotEncryptOff()
  let parsed = {'fields': {'age-encrypt': 'off'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 0)
endfunction
call testify#it('should not encrypt when age-encrypt: off', function('s:TestShouldNotEncryptOff'))

" Validate unrecognized values
function! s:TestValidateEncryptValueRecognized()
  call testify#assert#equals(mdage#ValidateEncryptValue('yes'), 1)
  call testify#assert#equals(mdage#ValidateEncryptValue('no'), 1)
  call testify#assert#equals(mdage#ValidateEncryptValue('true'), 1)
  call testify#assert#equals(mdage#ValidateEncryptValue('false'), 1)
  call testify#assert#equals(mdage#ValidateEncryptValue('on'), 1)
  call testify#assert#equals(mdage#ValidateEncryptValue('off'), 1)
  call testify#assert#equals(mdage#ValidateEncryptValue('YES'), 1)
  call testify#assert#equals(mdage#ValidateEncryptValue("'yes'"), 1)
endfunction
call testify#it('validates recognized age-encrypt values', function('s:TestValidateEncryptValueRecognized'))

function! s:TestValidateEncryptValueUnrecognized()
  call testify#assert#equals(mdage#ValidateEncryptValue('yess'), 0)
  call testify#assert#equals(mdage#ValidateEncryptValue('1'), 0)
  call testify#assert#equals(mdage#ValidateEncryptValue('enabled'), 0)
  call testify#assert#equals(mdage#ValidateEncryptValue(''), 0)
endfunction
call testify#it('rejects unrecognized age-encrypt values', function('s:TestValidateEncryptValueUnrecognized'))
