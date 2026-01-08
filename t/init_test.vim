" Tests for mdage#Init() and default recipients

function! s:TestInitNoDefaults()
  " Ensure no defaults set
  if exists('g:md_age_default_recipients')
    unlet g:md_age_default_recipients
  endif

  new
  call mdage#Init()
  let lines = getline(1, '$')
  bdelete!

  call testify#assert#equals(lines[0], '---')
  call testify#assert#equals(lines[1], 'age-encrypt: yes')
  call testify#assert#equals(lines[2], 'age-recipients:')
  call testify#assert#equals(lines[3], '  - ')
  call testify#assert#equals(lines[4], '---')
endfunction
call testify#it('Init inserts empty placeholder without defaults', function('s:TestInitNoDefaults'))

function! s:TestInitSingleStringRecipient()
  let g:md_age_default_recipients = 'age1xyz'

  new
  call mdage#Init()
  let lines = getline(1, '$')
  bdelete!

  unlet g:md_age_default_recipients

  call testify#assert#equals(lines[0], '---')
  call testify#assert#equals(lines[1], 'age-encrypt: yes')
  call testify#assert#equals(lines[2], 'age-recipients:')
  call testify#assert#equals(lines[3], '  - age1xyz')
  call testify#assert#equals(lines[4], '---')
endfunction
call testify#it('Init inserts single string recipient', function('s:TestInitSingleStringRecipient'))

function! s:TestInitMultipleRecipients()
  let g:md_age_default_recipients = ['age1abc', 'age1xyz']

  new
  call mdage#Init()
  let lines = getline(1, '$')
  bdelete!

  unlet g:md_age_default_recipients

  call testify#assert#equals(lines[0], '---')
  call testify#assert#equals(lines[1], 'age-encrypt: yes')
  call testify#assert#equals(lines[2], 'age-recipients:')
  call testify#assert#equals(lines[3], '  - age1abc')
  call testify#assert#equals(lines[4], '  - age1xyz')
  call testify#assert#equals(lines[5], '---')
endfunction
call testify#it('Init inserts multiple recipients from list', function('s:TestInitMultipleRecipients'))

function! s:TestInitSkipsExistingFrontmatter()
  " Ensure no defaults set
  if exists('g:md_age_default_recipients')
    unlet g:md_age_default_recipients
  endif

  new
  call setline(1, ['---', 'title: Existing', '---', 'body'])
  call mdage#Init()
  let lines = getline(1, '$')
  bdelete!

  " Should not have added new frontmatter
  call testify#assert#equals(lines[0], '---')
  call testify#assert#equals(lines[1], 'title: Existing')
  call testify#assert#equals(lines[2], '---')
  call testify#assert#equals(lines[3], 'body')
endfunction
call testify#it('Init skips buffer with existing frontmatter', function('s:TestInitSkipsExistingFrontmatter'))
