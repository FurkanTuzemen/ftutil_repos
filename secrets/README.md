# Encrypted secrets

Plaintext secrets are never committed to this repo. When a secret has to
survive the loss of the machine that holds it (for example the Conan server's
`.env`), commit it **encrypted with [age](https://age-encryption.org)** to the
public keys in [`age-recipients.txt`](age-recipients.txt), as `<file>.age`
next to where the plaintext lives.

| Encrypted file | Plaintext | Made by |
|---|---|---|
| `conan-server/linux/.env.age` | `conan-server/linux/.env` (ci password, JWT + updown secrets) | `conan-server/linux/encrypt-env.sh` on the server |

## The key

- **Private key (identity):** `C:\Users\Furkan\.age\ftutil_repos.key` on
  Furkan's PC. It's readable only by that user. **Keep a second copy in your
  password manager.** If you lose it, the `.age` files are unrecoverable.
- **Public key (recipient):** `age-recipients.txt`. It's safe to share, and
  it's all the servers need to encrypt.
- Encryption runs on the machine that has the plaintext, and only the public
  key goes there. The private key never leaves the PC.

## Decrypt / restore

```bash
# on a machine with the private key (Windows: winget install FiloSottile.age)
age -d -i ~/.age/ftutil_repos.key conan-server/linux/.env.age > .env
# copy .env to the server's conan-server/linux/, then: chmod 600 .env
```

## Add or rotate a key

Add the new public key to `age-recipients.txt`, then re-run each "Made by"
script so the files are re-encrypted to every listed key. To retire a key,
remove its line, re-encrypt, and rotate the secrets themselves: old git
history still holds copies encrypted to the old key.
