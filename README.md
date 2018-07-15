# sign

A password manager.

## Installation

``` sh
sudo mkdir -p /opt/local
sudo chown $USER:$(id -gn $USER) /opt/local

git clone --depth=1 https://github.com/sueka/sign.git /opt/local/sign

sudo ln -s /opt/local/sign/bin/sign.sh /usr/local/bin/sign
```

## Usage

### Dependencies

- `openssl`
- `xsel`
- `peco` or `percol` (optional)

---

Executing `sign init` asks your passphrase and stores it (hashed) in "$HOME/.sign/passphrase".

When you sign up, use `sign register`.

When you sign in, use `sign get`.

To change your passphrase, use `sign migrate`.

## License

[CC0 1.0 Universal](./LICENSE.txt)
