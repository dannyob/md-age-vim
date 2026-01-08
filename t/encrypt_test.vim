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

function! s:TestDecryptRoundtrip()
  let line = trim(readfile('/tmp/test-age-recipient.txt')[0])
  let recipient = substitute(line, '^Public key: ', '', '')
  let identity = '-i /tmp/test-age-key.txt'
  let plaintext = "Secret message\nWith multiple lines"

  let encrypted = mdage#Encrypt(plaintext, [recipient])
  call testify#assert#equals(encrypted.success, 1)

  let decrypted = mdage#Decrypt(encrypted.ciphertext, identity)
  call testify#assert#equals(decrypted.success, 1)
  call testify#assert#equals(decrypted.plaintext, plaintext)
endfunction
call testify#it('roundtrip encrypt/decrypt', function('s:TestDecryptRoundtrip'))

function! s:TestDecryptFailsWithWrongKey()
  " Create a different keypair
  call system('age-keygen -o /tmp/test-age-wrong-key.txt 2>/dev/null')

  let line = trim(readfile('/tmp/test-age-recipient.txt')[0])
  let recipient = substitute(line, '^Public key: ', '', '')
  let encrypted = mdage#Encrypt("test", [recipient])

  let decrypted = mdage#Decrypt(encrypted.ciphertext, '-i /tmp/test-age-wrong-key.txt')
  call testify#assert#equals(decrypted.success, 0)
endfunction
call testify#it('fails with wrong key', function('s:TestDecryptFailsWithWrongKey'))

function! s:TestDecryptFailsWithNoIdentity()
  let line = trim(readfile('/tmp/test-age-recipient.txt')[0])
  let recipient = substitute(line, '^Public key: ', '', '')
  let encrypted = mdage#Encrypt("test", [recipient])

  let decrypted = mdage#Decrypt(encrypted.ciphertext, '')
  call testify#assert#equals(decrypted.success, 0)
endfunction
call testify#it('fails with no identity', function('s:TestDecryptFailsWithNoIdentity'))
