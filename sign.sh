#!/bin/sh -eu

SIGN_CONFIG_DIR="$HOME/.sign"

#
# main init
# main register
# main register GitLab
# main register GitLab sueka
# main get
# main get GitLab
# main get GitLab sueka
#
main() {

  # オプション無しで呼ばれた場合、 64 で終了する
  if [ -z "$*" ]; then
    exit 64
  fi

  subcommand=$1
  shift

  case "$subcommand" in
    init )
      init "$@"
    ;;

    register )
      register "$@"
    ;;

    get )
      get "$@"
    ;;

    # サブコマンドが存在しない場合、 65 で終了する
    * )
      echo "No subcommand '$subcommand' found." >&2
      exit 65
    ;;
  esac
}

init() {

  # オプション付きで呼ばれた場合、 67 で終了する
  if [ -n "$*" ]; then
    exit 67
  fi

  # $SIGN_CONFIG_DIR が存在する場合、 68 で終了する
  if [ -d "$SIGN_CONFIG_DIR" ]; then
    echo "'$SIGN_CONFIG_DIR' does already exist." >&2
    exit 68
  fi

  # エコーバックを停止させる
  stty -echo

  printf %s 'Enter your passphrase (invisible): '
  read passphrase
  echo

  printf %s 'Enter your passphrase again (invisible): '
  read passphrase_again
  echo

  # エコーバックを再開させる
  stty echo

  # passphrase と passphrase_again が異なる場合、 69 で終了する
  if [ "$passphrase" != "$passphrase_again" ]; then
    echo 'Passphrases do not match each other.' >&2
    exit 69
  fi

  mkdir -p "$SIGN_CONFIG_DIR"
  chmod 700 "$SIGN_CONFIG_DIR"

  echo $(hmac_sha256 "$passphrase" 'a secret key') >"$SIGN_CONFIG_DIR/passphrase"
  chmod 600 "$SIGN_CONFIG_DIR/passphrase"
}

register() {

  # オプション無しで呼ばれた場合、サービス名を尋ねる
  if [ -z "$*" ]; then
    printf %s 'Enter the service name: '
    read service_name
  else
    service_name=$1
    shift
  fi

  # 指定されたサービスの ID 一覧が存在しない場合、作成する
  if ! [ -f "$SIGN_CONFIG_DIR/${service_name}_ids" ]; then

    # TODO
    if ! confirm "Do you want to create '$SIGN_CONFIG_DIR/${service_name}_ids' ?"; then
      exit 74
    fi

    touch "$SIGN_CONFIG_DIR/${service_name}_ids"
  fi

  # 1オプションで呼ばれた場合、 ID を尋ねる
  if [ -z "$*" ]; then
    printf %s "Enter an ID of yours for $service_name: "
    read your_id
  else
    your_id=$1
    shift
  fi

  # ID がすでに存在する場合、 77 で終了する
  if grep "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids" 1>/dev/null; then
    echo "'$your_id' for $service_name does already exist." >&2
    exit 77
  fi

  # TODO
  if ! confirm "Do you want to append '$your_id' to '$SIGN_CONFIG_DIR/${service_name}_ids' ?"; then
    exit 75
  fi

  echo "$your_id" >>"$SIGN_CONFIG_DIR/${service_name}_ids"

  hash_and_then_copy "$service_name" "$your_id"
}

get() {

  # オプション無しで呼ばれた場合、サービス名を尋ねる
  if [ -z "$*" ]; then
    printf %s 'Enter the service name: '
    read service_name
  else
    service_name=$1
    shift
  fi

  # 指定されたサービスの ID 一覧が存在しない場合、 71 で終了する
  if ! [ -f "$SIGN_CONFIG_DIR/${service_name}_ids" ]; then
    exit 71
  fi

  # 1オプションで呼ばれた場合、 ID を尋ねる
  if [ -z "$*" ]; then
    printf %s "Enter an ID of yours for $service_name: "
    read your_id
  else
    your_id=$1
    shift
  fi

  # ID が存在しない場合、 72 で終了する
  if ! grep "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids" 1>/dev/null; then
    exit 72
  fi

  hash_and_then_copy "$service_name" "$your_id"
}

#
# hash_and_then_copy <service name> <your id>
#
hash_and_then_copy() {

  # xsel が無い場合、 73 で終了する
  if ! command -v xsel 1>/dev/null; then
    echo "No command 'xsel' found." >&2
    exit 73
  fi

  # エコーバックを停止させる
  stty -echo

  printf %s 'Enter your passphrase (invisible): '
  read passphrase
  echo

  # エコーバックを再開させる
  stty echo

  # passphrase が誤っている場合、 70 で終了する
  if [ $(hmac_sha256 "$passphrase" 'a secret key') != "$(cat "$SIGN_CONFIG_DIR/passphrase")" ]; then
    echo 'Passphrase is wrong.' >&2
    exit 70
  fi

  service_name=$1
  shift

  your_id=$1
  shift

  hmac_sha256 "$service_name $your_id" "$passphrase" | xsel -bi
}

#
# hmac_sha256 <message> <secret key>
#
hmac_sha256() {

  # openssl が無い場合、 66 で終了する
  if ! command -v openssl 1>/dev/null; then
    echo "No command 'openssl' found." >&2
    exit 66
  fi

  message=$1
  shift

  secret_key=$1
  shift

  printf %s $(printf %s "$message" | openssl dgst -sha256 -hmac "$secret_key" | sed 's/^.* //')
}

#
# confirm <prompt>
#
confirm() {
  prompt=$1
  shift

  printf %s "$prompt [Y/n] "
  read yes_no

  case "$yes_no" in
    '' | Y | YES | Yes | y | yes )
      return 0
    ;;

    N | NO | No | n | no )
      return 1
    ;;

    # yes/no 以外が入力された場合、 76 で終了する
    * )
      echo "Type 'yes' or 'no'." >&2
      exit 76
    ;;
  esac
}

main "$@"
