#!/bin/sh -eu

EX_USAGE=64
EX_DATAERR=65
EX_NOINPUT=66
EX_NOUSER=67
EX_NOHOST=68
EX_UNAVAILABLE=69
EX_SOFTWARE=70
EX_OSERR=71
EX_OSFILE=72
EX_CANTCREAT=73
EX_IOERR=74
EX_TEMPFAIL=75
EX_PROTOCOL=76
EX_NOPERM=77
EX_CONFIG=78

NAME=$(basename "$0")

SIGN_CONFIG_DIR="$HOME/.sign"

#
# main init
# main register [<service name> [<your ID>]]
# main get [<service name> [<your ID>]]
# main migrate
#
main() {

	# オプション無しで呼ばれた場合
	if [ -z "$*" ]; then
		exit $EX_USAGE
	fi

	subcommand=$1 && shift

	case "$subcommand" in
		init )
			sign_init "$@"
		;;

		register )
			sign_register "$@"
		;;

		get )
			sign_get "$@"
		;;

		migrate )
			sign_migrate "$@"
		;;

		# サブコマンドが存在しない場合
		* )
			echo_fatal "No subcommand '$subcommand' found." >&2
			exit $EX_USAGE
		;;
	esac
}

#
# sign_init
#
sign_init() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		exit $EX_USAGE
	fi

	# $SIGN_CONFIG_DIR が存在する場合
	if [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal "'$SIGN_CONFIG_DIR' does already exist." >&2
		exit $EX_SOFTWARE
	fi

	# エコーバックを停止させる
	stty -echo

	printf %s 'Enter your passphrase (invisible): '
	IFS= read -r passphrase
	echo

	printf %s 'Enter your passphrase again (invisible): '
	IFS= read -r passphrase_again
	echo

	# エコーバックを再開させる
	stty echo

	# passphrase と passphrase_again が異なる場合
	if [ "$passphrase" != "$passphrase_again" ]; then
		echo_fatal 'Passphrases do not match.' >&2
		exit $EX_SOFTWARE
	fi

	mkdir -p "$SIGN_CONFIG_DIR"
	chmod 700 "$SIGN_CONFIG_DIR"

	touch "$SIGN_CONFIG_DIR/passphrase"
	chmod 600 "$SIGN_CONFIG_DIR/passphrase"

	echo $(hmac_sha256 "$passphrase" 'a secret key') >"$SIGN_CONFIG_DIR/passphrase"
}

#
# sign_register [<service name> [<your ID>]]
#
sign_register() {

	# サービス名一覧が存在しない場合、作成する
	if ! [ -f "$SIGN_CONFIG_DIR/service_names" ]; then
		touch "$SIGN_CONFIG_DIR/service_names"
		chmod 755 "$SIGN_CONFIG_DIR/service_names"
	fi

	# オプション無しで呼ばれた場合、サービス名を尋ねる
	if [ -z "$*" ]; then
		printf %s 'Enter the service name: '
		read -r service_name
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

	# 第2オプション無しで呼ばれた場合、 ID を尋ねる
	if [ -z "$*" ]; then
		printf %s "Enter an ID of yours for $service_name: "
		read -r your_id
	else
		your_id=$1 && shift
	fi

	# ID がすでに存在する場合
	if grep "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids" 1>/dev/null; then
		echo_fatal "$service_name ID '$your_id' does already exist." >&2
		exit $EX_SOFTWARE
	fi

	# TODO: 似た ID を表示させる

	echo "$your_id" >>"$SIGN_CONFIG_DIR/${service_name}_ids"

	hash_and_then_copy "$service_name" "$your_id"
	echo_info 'Your password is stored into the clipboard.'
}

#
# sign_get [<service name> [<your ID>]]
#
sign_get() {

	# オプション無しで呼ばれた場合、サービス名の入力を受け付ける
	if [ -z "$*" ]; then

		# peco または percol がある場合は対話的に取得し、無い場合はサービス名一覧を表示してから read する
		if command -v peco 1>/dev/null; then
			service_name=$(cat "$SIGN_CONFIG_DIR/service_names" | peco)

			echo "Service '$service_name' chosen."
		elif command -v percol 1>/dev/null; then
			service_name=$(cat "$SIGN_CONFIG_DIR/service_names" | percol)

			echo "Service '$service_name' chosen."
		else
			echo 'Choose a service:'

			echo
			cat "$SIGN_CONFIG_DIR/service_names" | sed 's/^/  /'
			echo

			printf %s 'Enter the service name: '
			read -r service_name
		fi
	else
		service_name=$1 && shift
	fi

	# 指定されたサービス名がサービス一覧に存在しない場合
	if ! grep "^$service_name\$" "$SIGN_CONFIG_DIR/service_names" 1>/dev/null; then

		# TODO: 似たサービス名を表示させる

		echo_fatal "No service '$service_name' found." >&2
		exit $EX_SOFTWARE
	fi

	# 第2オプション無しで呼ばれた場合、 ID の入力を受け付ける
	if [ -z "$*" ]; then

		# peco または percol がある場合は対話的に取得し、無い場合は ID 一覧を表示してから read する
		if command -v peco 1>/dev/null; then
			your_id=$(cat "$SIGN_CONFIG_DIR/${service_name}_ids" | peco)

			echo "$service_name ID '$your_id' chosen."
		elif command -v percol 1>/dev/null; then
			your_id=$(cat "$SIGN_CONFIG_DIR/${service_name}_ids" | percol)

			echo "$service_name ID '$your_id' chosen."
		else
			echo "Choose your $service_name ID:"

			echo
			cat "$SIGN_CONFIG_DIR/${service_name}_ids" | sed 's/^/  /'
			echo

			printf %s "Enter an ID of yours for $service_name: "
			read -r your_id
		fi
	else
		your_id=$1 && shift
	fi

	# ID が存在しない場合
	if ! grep "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids" 1>/dev/null; then

		# TODO: 似た ID を表示させる

		echo_fatal "No $service_name ID '$your_id' found." >&2
		exit $EX_SOFTWARE
	fi

	printf %s "$your_id" | xsel -bi
	echo_info 'Your ID is stored into the clipboard.'

	hash_and_then_copy "$service_name" "$your_id"
	echo_info 'Your password is stored into the clipboard.'
}

#
# sign_migrate
#
sign_migrate() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		exit $EX_USAGE
	fi

	# $SIGN_CONFIG_DIR が存在しない場合
	if ! [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal "$NAME is not initialized." >&2
		exit $EX_IOERR
	fi

	# エコーバックを停止させる
	stty -echo

	printf %s 'Enter your old passphrase (invisible): '
	IFS= read -r old_passphrase
	echo

	# エコーバックを再開させる
	stty echo

	# old_passphrase が誤っている場合
	if [ $(hmac_sha256 "$old_passphrase" 'a secret key') != "$(cat "$SIGN_CONFIG_DIR/passphrase")" ]; then
		echo_fatal 'Passphrase is wrong.' >&2
		exit $EX_SOFTWARE
	fi

	# エコーバックを停止させる
	stty -echo

	printf %s 'Enter your new passphrase (invisible): '
	IFS= read -r new_passphrase
	echo

	printf %s 'Enter your new passphrase again (invisible): '
	IFS= read -r new_passphrase_again
	echo

	# エコーバックを再開させる
	stty echo

	# new_passphrase と new_passphrase_again が異なる場合
	if [ "$new_passphrase" != "$new_passphrase_again" ]; then
		echo_fatal 'New passphrases do not match.' >&2
		exit $EX_SOFTWARE
	fi

	echo $(hmac_sha256 "$new_passphrase" 'a secret key') >"$SIGN_CONFIG_DIR/passphrase"

	for service_name in $(cat "$SIGN_CONFIG_DIR/service_names")
	do
		for your_id in $(cat "$SIGN_CONFIG_DIR/${service_name}_ids")
		do
			printf %s "$your_id" | xsel -bi
			echo_info 'Your ID is stored into the clipboard.'
			until_enter

			hash_and_then_copy "$service_name" "$your_id" "$old_passphrase"
			echo_info 'Your old password is stored into the clipboard.'
			until_enter

			hash_and_then_copy "$service_name" "$your_id" "$new_passphrase"
			echo_info 'Your new password is stored into the clipboard.'
			until_enter
		done
	done
}

#
# hash_and_then_copy <service name> <your id> [<passphrase>]
#
hash_and_then_copy() {

	# xsel が無い場合
	if ! command -v xsel 1>/dev/null; then
		echo_fatal "No command 'xsel' found." >&2
		exit $EX_UNAVAILABLE
	fi

	service_name=$1 && shift
	your_id=$1 && shift

	# 第3オプション無しで呼ばれた場合、 passphrase を尋ねる
	if [ -z "$*" ]; then

		# エコーバックを停止させる
		stty -echo

		printf %s 'Enter your passphrase (invisible): '
		IFS= read -r passphrase
		echo

		# エコーバックを再開させる
		stty echo
	else
		passphrase=$1 && shift
	fi

	password=$(hexadecimal_to_duohexagesimal "$(hmac_sha256 "$service_name $your_id" "$passphrase")")
	printf %s "$password" | xsel -bi
}

#
# hexadecimal_to_duohexagesimal <hex>
#
hexadecimal_to_duohexagesimal() {
	hex=$1 && shift

	uppercase_hex=$(printf %s "$hex" | LC_COLLATE=C tr 'a-z' 'A-Z')

	dec=$(echo 'ibase=16;' "$uppercase_hex" | bc_with_no_linefeeds)

	duohexagesimal_digits=$(echo 'obase=62;' "$dec" | bc_with_no_linefeeds | tr ' ' '\n' | bc_with_no_linefeeds | tr '\n' ' ')

	for i in $duohexagesimal_digits
	do
		if [ 0 -le "$i" ] && [ "$i" -le 9 ]; then
			charcode=$(echo "48 + $i - 0" | bc)
		elif [ 10 -le "$i" ] && [ "$i" -le 35 ]; then
			charcode=$(echo "65 + $i - 10" | bc)
		elif [ 36 -le "$i" ] && [ "$i" -le 61 ]; then
			charcode=$(echo "97 + $i - 36" | bc)
		fi

		printf "\\$(printf %o "$charcode")"
	done
}

#
# bc_with_no_linefeeds [-l] [<file> ..]
#
bc_with_no_linefeeds() {
	while read line
	do
		echo "$line"
	done | bc "$@" | sed ':_;N;$!b_;s/\\\n//g'
}

#
# hmac_sha256 <message> <secret key>
#
hmac_sha256() {

	# openssl が無い場合
	if ! command -v openssl 1>/dev/null; then
		echo_fatal "No command 'openssl' found." >&2
		exit $EX_UNAVAILABLE
	fi

	message=$1 && shift
	secret_key=$1 && shift

	printf %s $(printf %s "$message" | openssl dgst -sha256 -hmac "$secret_key" | sed 's/^.* //')
}

#
# echo_info [<string> ..]
#
echo_info() {
	print_colored 0 255 255 "[INFO]   $@"
	echo
}

#
# echo_fatal [<string> ..]
#
echo_fatal() {
	print_colored 255 0 0 "[FATAL]  $@"
	echo
}

#
# print_colored <red> <green> <blue> [<string> ..]
#
print_colored() {
	red=$1 && shift
	green=$1 && shift
	blue=$1 && shift

	printf '\e[38;2;%d;%d;%dm' "$red" "$green" "$blue"
	printf %s "$@"
	printf '\e[0m'
}

#
# until_enter
#
until_enter() {
	while true
	do
		printf %s 'Press the enter key. '
		IFS= read dummy

		if [ -z "$dummy" ]; then
			break
		fi
	done
}

main "$@"
