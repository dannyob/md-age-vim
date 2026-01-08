" Tests for encryption/decryption
" Requires: age installed, test key at /tmp/test-age-key.txt

function! s:TestEncryptProducesArmoredOutput()
  " Read recipient from test key (format: "Public key: age1...")
  let line = trim(readfile('/tmp/test-age-recipient.txt')[0])
  let recipient = substitute(line, '^Public key: ', '', '')
  let plaintext = "Hello, World!"
  let result = mdage#Encrypt(plaintext, [recipient])
  call testify#assert#equals(result.success, 1)
  call testify#assert#equals(result.ciphertext =~# '^-----BEGIN AGE ENCRYPTED FILE-----', 1)
  call testify#assert#equals(result.ciphertext =~# '-----END AGE ENCRYPTED FILE-----$', 1)
endfunction
call testify#it('encrypts to armored output', function('s:TestEncryptProducesArmoredOutput'))

function! s:TestEncryptFailsWithNoRecipients()
  let plaintext = "Hello, World!"
  let result = mdage#Encrypt(plaintext, [])
  call testify#assert#equals(result.success, 0)
endfunction
call testify#it('fails with no recipients', function('s:TestEncryptFailsWithNoRecipients'))
