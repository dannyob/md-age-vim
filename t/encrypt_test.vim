" Tests for encryption/decryption
" Requires: age installed

" Setup fresh test keys for each test run
let s:keyfile = tempname() . '-age-key.txt'
let s:recipientfile = tempname() . '-age-recipient.txt'
call system('age-keygen -o ' . shellescape(s:keyfile) . ' 2>' . shellescape(s:recipientfile))
let s:recipient_line = trim(readfile(s:recipientfile)[0])
let s:test_recipient = substitute(s:recipient_line, '^Public key: ', '', '')

function! s:TestEncryptProducesArmoredOutput()
  let plaintext = "Hello, World!"
  let result = mdage#Encrypt(plaintext, [s:test_recipient])
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

function! s:TestDecryptRoundtrip()
  let identity = '-i ' . s:keyfile
  let plaintext = "Secret message\nWith multiple lines"

  let encrypted = mdage#Encrypt(plaintext, [s:test_recipient])
  call testify#assert#equals(encrypted.success, 1)

  let decrypted = mdage#Decrypt(encrypted.ciphertext, identity)
  call testify#assert#equals(decrypted.success, 1)
  call testify#assert#equals(decrypted.plaintext, plaintext)
endfunction
call testify#it('roundtrip encrypt/decrypt', function('s:TestDecryptRoundtrip'))

function! s:TestDecryptFailsWithWrongKey()
  " Create a different keypair
  let wrongkey = tempname() . '-wrong-key.txt'
  call system('age-keygen -o ' . shellescape(wrongkey) . ' 2>/dev/null')

  let encrypted = mdage#Encrypt("test", [s:test_recipient])

  let decrypted = mdage#Decrypt(encrypted.ciphertext, '-i ' . wrongkey)
  call testify#assert#equals(decrypted.success, 0)
endfunction
call testify#it('fails with wrong key', function('s:TestDecryptFailsWithWrongKey'))

function! s:TestDecryptFailsWithNoIdentity()
  let encrypted = mdage#Encrypt("test", [s:test_recipient])

  let decrypted = mdage#Decrypt(encrypted.ciphertext, '')
  call testify#assert#equals(decrypted.success, 0)
endfunction
call testify#it('fails with no identity', function('s:TestDecryptFailsWithNoIdentity'))
