#!/bin/sh -eu

SIGN_CONFIG_DIR="$HOME/.sign"

#
# main init
# main register [<service name> [<your ID>]]
# main get [<service name> [<your ID>]]
#
main() {

  # オプション無しで呼ばれた場合、 64 で終了する
  if [ -z "$*" ]; then
    exit 64
  fi

  subcommand=$1 && shift

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
      echo_fatal "No subcommand '$subcommand' found." >&2
      exit 65
    ;;
  esac
}

#
# init
#
init() {

  # オプション付きで呼ばれた場合、 67 で終了する
  if [ -n "$*" ]; then
    exit 67
  fi

  # $SIGN_CONFIG_DIR が存在する場合、 68 で終了する
  if [ -d "$SIGN_CONFIG_DIR" ]; then
    echo_fatal "'$SIGN_CONFIG_DIR' does already exist." >&2
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
    echo_fatal 'Passphrases do not match each other.' >&2
    exit 69
  fi

  mkdir -p "$SIGN_CONFIG_DIR"
  chmod 700 "$SIGN_CONFIG_DIR"

  touch "$SIGN_CONFIG_DIR/passphrase"
  chmod 600 "$SIGN_CONFIG_DIR/passphrase"

  echo $(hmac_sha384 "$passphrase" 'a secret key') >"$SIGN_CONFIG_DIR/passphrase"
}

#
# register [<service name> [<your ID>]]
#
register() {

  # サービス名一覧が存在しない場合、作成する
  if ! [ -f "$SIGN_CONFIG_DIR/service_names" ]; then
    touch "$SIGN_CONFIG_DIR/service_names"
    chmod 755 "$SIGN_CONFIG_DIR/service_names"
  fi

  # オプション無しで呼ばれた場合、サービス名を尋ねる
  if [ -z "$*" ]; then
    printf %s 'Enter the service name: '
    read service_name
  else
    service_name=$1 && shift
  fi

  # 指定されたサービス名がサービス名一覧に存在しない場合、作成する
  if ! grep "^$service_name\$" "$SIGN_CONFIG_DIR/service_names" 1>/dev/null; then

    # TODO: 似たサービス名を表示させる

    echo "$service_name" >>"$SIGN_CONFIG_DIR/service_names"

    touch "$SIGN_CONFIG_DIR/${service_name}_ids"
    chmod 644 "$SIGN_CONFIG_DIR/${service_name}_ids"
  fi

  # 1オプションで呼ばれた場合、 ID を尋ねる
  if [ -z "$*" ]; then
    printf %s "Enter an ID of yours for $service_name: "
    read your_id
  else
    your_id=$1 && shift
  fi

  # ID がすでに存在する場合、 77 で終了する
  if grep "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids" 1>/dev/null; then
    echo_fatal "'$your_id' for $service_name does already exist." >&2
    exit 77
  fi

  # TODO: 似た ID を表示させる

  echo "$your_id" >>"$SIGN_CONFIG_DIR/${service_name}_ids"

  hash_and_then_copy "$service_name" "$your_id"
  echo_info 'Your password is stored into the clipboard.'
}

#
# get [<service name> [<your ID>]]
#
get() {

  # オプション無しで呼ばれた場合、サービス名の入力を受け付ける
  if [ -z "$*" ]; then

    # peco または percol がある場合は対話的に取得し、無い場合はサービス名一覧を表示してから read する
    if command -v peco 1>/dev/null; then
      service_name=$(cat "$SIGN_CONFIG_DIR/service_names" | peco)
    elif command -v percol 1>/dev/null; then
      service_name=$(cat "$SIGN_CONFIG_DIR/service_names" | percol)
    else
      cat "$SIGN_CONFIG_DIR/service_names"

      printf %s 'Enter the service name: '
      read service_name
    fi
  else
    service_name=$1 && shift
  fi

  # 指定されたサービス名がサービス一覧に存在しない場合、 71 で終了する
  if ! grep "^$service_name\$" "$SIGN_CONFIG_DIR/service_names" 1>/dev/null; then

    # TODO: 似たサービス名を表示させる

    exit 71
  fi

  # 1オプションで呼ばれた場合、 ID の入力を受け付ける
  if [ -z "$*" ]; then

    # peco がある場合は対話的に取得し、無い場合は ID 一覧を表示してから read する
    if command -v peco 1>/dev/null; then
      your_id=$(cat "$SIGN_CONFIG_DIR/${service_name}_ids" | peco)
    else
      cat "$SIGN_CONFIG_DIR/${service_name}_ids"

      printf %s "Enter an ID of yours for $service_name: "
      read your_id
    fi
  else
    your_id=$1 && shift
  fi

  # ID が存在しない場合、 72 で終了する
  if ! grep "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids" 1>/dev/null; then

    # TODO: 似た ID を表示させる

    echo_fatal "No $service_name ID '$your_id' found." >&2
    exit 72
  fi

  echo "$your_id" | xsel -bi
  echo_info 'Your ID is stored into the clipboard.'

  hash_and_then_copy "$service_name" "$your_id"
  echo_info 'Your password is stored into the clipboard.'
}

#
# hash_and_then_copy <service name> <your id>
#
hash_and_then_copy() {

  # xsel が無い場合、 73 で終了する
  if ! command -v xsel 1>/dev/null; then
    echo_fatal "No command 'xsel' found." >&2
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
  if [ $(hmac_sha384 "$passphrase" 'a secret key') != "$(cat "$SIGN_CONFIG_DIR/passphrase")" ]; then
    echo_fatal 'Passphrase is wrong.' >&2
    exit 70
  fi

  service_name=$1 && shift
  your_id=$1 && shift

  hash=$(hex_to_printable_ascii "$(hmac_sha384 "$service_name $your_id" "$passphrase")")
  printf %s "$hash" | xsel -bi
}

#
# hex_to_printable_ascii <hex>
#
hex_to_printable_ascii() {

  # xxd が無い場合、 78 で終了する
  if ! command -v xxd 1>/dev/null; then
    echo_fatal "No command 'xxd' found." >&2
    exit 78
  fi

  hex=$1 && shift

  printf %s "$hex" | xxd -r -p | strings -n1 | tr -d '\n'
}

#
# hmac_sha384 <message> <secret key>
#
hmac_sha384() {

  # openssl が無い場合、 66 で終了する
  if ! command -v openssl 1>/dev/null; then
    echo_fatal "No command 'openssl' found." >&2
    exit 66
  fi

  message=$1 && shift
  secret_key=$1 && shift

  printf %s $(printf %s "$message" | openssl dgst -sha384 -hmac "$secret_key" | sed 's/^.* //')
}

#
# echo_info <string> ..
#
echo_info() {
  print_colored 0 255 255 "[INFO]   $@"
  echo
}

#
# echo_fatal <string> ..
#
echo_fatal() {
  print_colored 255 0 0 "[FATAL]  $@"
  echo
}

#
# print_colored <red> <green> <blue> <string> ..
#
print_colored() {
  red=$1 && shift
  green=$1 && shift
  blue=$1 && shift

  printf '\e[38;2;%d;%d;%dm' "$red" "$green" "$blue"
  printf %s "$@"
  printf '\e[0m'
}

main "$@"
