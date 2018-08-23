# sign

A password manager.

[![Build Status](https://travis-ci.org/sueka/sign.svg?branch=master)](https://travis-ci.org/sueka/sign)

## Installation

``` sh
sudo mkdir -p /opt/local
sudo chmod uo+rwx /opt/local

git clone --depth=1 https://github.com/sueka/sign.git /opt/local/sign

sudo ln -s /opt/local/sign/bin/sign.sh /usr/local/bin/sign

# Bash auto completion
echo '. /opt/local/sign/bin/complete_sign.sh' >>~/.bashrc
```

### Update

``` sh
cd /opt/local/sign

git checkout master
git pull origin master
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
