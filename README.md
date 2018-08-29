# sign

A password manager.

[![Build Status](https://travis-ci.org/sueka/sign.svg?branch=master)](https://travis-ci.org/sueka/sign)

## Installation

``` sh
sudo mkdir -p /opt/local
sudo chmod 1777 /opt/local

git clone --depth=1 https://github.com/sueka/sign.git /opt/local/sign

sudo ln -s /opt/local/sign/bin/sign.sh /usr/local/bin/sign

# Bash auto completion
echo '. /opt/local/sign/bin/bash_complete_sign.sh' >>~/.bashrc
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

Enabling the Bash auto completion, type `sign ` and hit the <kbd>Tab</kbd> twice.

## License

[CC0 1.0 Universal](./LICENSE.txt)
