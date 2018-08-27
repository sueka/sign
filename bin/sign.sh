#!/bin/sh

set -eu

EX_OK=0

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
# check_dependencies
#
check_dependencies() {
	ex=$EX_OK

	# openssl が無い場合
	if ! command -v openssl 1>/dev/null; then
		echo_fatal "No command 'openssl' found." >&2
		ex=$EX_UNAVAILABLE
	fi

	# xsel が無い場合
	if ! command -v xsel 1>/dev/null; then
		echo_fatal "No command 'xsel' found." >&2
		ex=$EX_UNAVAILABLE
	fi

	return $ex
}

#
# main init
# main register [<service name> [<your ID>]]
# main get [<service name> [<your ID>]]
# main migrate
#
main() {

	# オプション無しで呼ばれた場合
	if [ -z "$*" ]; then
		return $EX_USAGE
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
			return $EX_USAGE
		;;
	esac
}

#
# sign_init
#
sign_init() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	# $SIGN_CONFIG_DIR が存在する場合
	if [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal "'$SIGN_CONFIG_DIR' does already exist." >&2
		return $EX_SOFTWARE
	fi

	# secret_key を生成する
	secret_key=$(tr -dc [:alnum:] </dev/urandom | dd bs=1024 count=1 2>/dev/null)

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s 'Enter your passphrase (invisible): '
	IFS= read -r passphrase
	echo

	printf %s 'Enter your passphrase again (invisible): '
	IFS= read -r passphrase_again
	echo

	# エコーバックを再開させる
	stty "$old_config"

	# passphrase と passphrase_again が異なる場合
	if [ "$passphrase" != "$passphrase_again" ]; then
		echo_fatal 'Passphrases do not match.' >&2
		return $EX_SOFTWARE
	fi

	mkdir -p "$SIGN_CONFIG_DIR"
	chmod 700 "$SIGN_CONFIG_DIR"

	touch "$SIGN_CONFIG_DIR/secret_key"
	chmod 600 "$SIGN_CONFIG_DIR/secret_key"

	touch "$SIGN_CONFIG_DIR/passphrase"
	chmod 600 "$SIGN_CONFIG_DIR/passphrase"

	touch "$SIGN_CONFIG_DIR/service_names"
	chmod 604 "$SIGN_CONFIG_DIR/service_names"

	echo "$secret_key" >"$SIGN_CONFIG_DIR/secret_key"
	echo "$(hmac_sha256 "$passphrase" "$secret_key")" >"$SIGN_CONFIG_DIR/passphrase"
}

#
# sign_register [<service name> [<your ID>]]
#
sign_register() {

	# オプション無しで呼ばれた場合、サービス名を尋ねる
	if [ -z "$*" ]; then
		printf %s 'Enter the service name: '
		read -r service_name
	else
		service_name=$1 && shift
	fi

	# 第2オプション無しで呼ばれた場合、 ID を尋ねる
	if [ -z "$*" ]; then
		printf %s "Enter an ID of yours for $service_name: "
		read -r your_id
	else
		your_id=$1 && shift
	fi

	# 第3オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	# 指定されたサービス名がサービス名一覧に存在しない場合、作成する
	if ! grep "^$service_name\$" "$SIGN_CONFIG_DIR/service_names" 1>/dev/null; then

		# TODO: 似たサービス名を表示させる

		echo "$service_name" >>"$SIGN_CONFIG_DIR/service_names"

		touch "$SIGN_CONFIG_DIR/${service_name}_ids"
		chmod 644 "$SIGN_CONFIG_DIR/${service_name}_ids"
	fi

	# ID がすでに存在する場合
	if grep "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids" 1>/dev/null; then
		echo_fatal "$service_name ID '$your_id' does already exist." >&2
		return $EX_SOFTWARE
	fi

	# TODO: 似た ID を表示させる

	echo "$your_id" >>"$SIGN_CONFIG_DIR/${service_name}_ids"

	copy_password "$service_name" "$your_id"
	echo_info 'Your password is stored in the clipboard.'
}

#
# sign_get [<service name> [<your ID>]]
#
sign_get() {

	# 第1オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		service_name=$1 && shift
	else
		service_name=

		if ! command -v peco 1>/dev/null && ! command -v percol 1>/dev/null; then
			echo 'Choose a service:'

			echo
			cat "$SIGN_CONFIG_DIR/service_names" | sed 's/^/  /'
			echo

			printf %s 'Enter the service name: '
			read -r service_name
		fi
	fi

	# 第2オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		your_id=$1 && shift
	else
		your_id=

		if ! command -v peco 1>/dev/null && ! command -v percol 1>/dev/null; then
			echo "Choose your $service_name ID:"

			echo
			cat "$SIGN_CONFIG_DIR/${service_name}_ids" | sed 's/^/  /'
			echo

			printf %s "Enter an ID of yours for $service_name: "
			read -r your_id
		fi
	fi

	# 第3オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	given_service_name=$service_name

	# 指定されたサービス名がサービス一覧に存在しない場合
	while ! grep "^$service_name\$" "$SIGN_CONFIG_DIR/service_names" 1>/dev/null
	do
		if command -v peco 1>/dev/null; then
			service_name=$(
				cat "$SIGN_CONFIG_DIR/service_names" |
				peco --query "$given_service_name" --prompt 'Enter the service name: '
			)
		elif command -v percol 1>/dev/null; then
			service_name=$(
				cat "$SIGN_CONFIG_DIR/service_names" |
				percol --query "$given_service_name" --prompt 'Enter the service name:  %q'
			)
		fi
	done

	echo_info "Service '$service_name' chosen."

	your_given_id=$your_id

	# ID が存在しない場合
	while ! grep "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids" 1>/dev/null
	do
		if command -v peco 1>/dev/null; then
			your_id=$(
				cat "$SIGN_CONFIG_DIR/${service_name}_ids" |
				peco --query "$your_given_id" --prompt "Enter an ID of yours for $service_name: "
			)
		elif command -v percol 1>/dev/null; then
			your_id=$(
				cat "$SIGN_CONFIG_DIR/${service_name}_ids" |
				percol --query "$your_given_id" --prompt "Enter an ID of yours for $service_name:  %q"
			)
		fi
	done

	echo_info "$service_name ID '$your_id' chosen."

	printf %s "$your_id" | xsel -bi
	echo_info 'Your ID is stored in the clipboard.'

	copy_password "$service_name" "$your_id"
	echo_info 'Your password is stored in the clipboard.'
}

#
# sign_migrate
#
sign_migrate() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	# $SIGN_CONFIG_DIR が存在しない場合
	if ! [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal 'Not initialized.' >&2
		return $EX_IOERR
	fi

	secret_key=$(cat "$SIGN_CONFIG_DIR/secret_key")

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s 'Enter your old passphrase (invisible): '
	IFS= read -r old_passphrase
	echo

	# エコーバックを再開させる
	stty "$old_config"

	# old_passphrase が誤っている場合
	if [ $(hmac_sha256 "$old_passphrase" "$secret_key") != "$(cat "$SIGN_CONFIG_DIR/passphrase")" ]; then
		echo_fatal 'Passphrase is wrong.' >&2
		return $EX_SOFTWARE
	fi

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s 'Enter your new passphrase (invisible): '
	IFS= read -r new_passphrase
	echo

	printf %s 'Enter your new passphrase again (invisible): '
	IFS= read -r new_passphrase_again
	echo

	# エコーバックを再開させる
	stty "$old_config"

	# new_passphrase と new_passphrase_again が異なる場合
	if [ "$new_passphrase" != "$new_passphrase_again" ]; then
		echo_fatal 'New passphrases do not match.' >&2
		return $EX_SOFTWARE
	fi

	echo "$(hmac_sha256 "$new_passphrase" "$secret_key")" >"$SIGN_CONFIG_DIR/passphrase"

	cat "$SIGN_CONFIG_DIR/service_names" | while read -r service_name
	do
		cat "$SIGN_CONFIG_DIR/${service_name}_ids" | while read -r your_id
		do
			echo_info "Changing your password for $service_name ID '$your_id'.."

			printf %s "$your_id" | xsel -bi
			echo_info "Your ID '$your_id' is stored in the clipboard."
			until_enter

			copy_password "$service_name" "$your_id" "$old_passphrase"
			echo_info "Your old password for $service_name ID '$your_id' is stored in the clipboard."
			until_enter

			copy_password "$service_name" "$your_id" "$new_passphrase"
			echo_info "Your new password for $service_name ID '$your_id' is stored in the clipboard."
			until_enter
		done
	done
}

#
# copy_password <service name> <your id> [<passphrase>]
#
copy_password() {
	service_name=$1 && shift
	your_id=$1 && shift

	# 第3オプション無しで呼ばれた場合、 passphrase を尋ねる
	if [ -z "$*" ]; then
		secret_key=$(cat "$SIGN_CONFIG_DIR/secret_key")

		# エコーバックを停止させる
		old_config=$(stty -g)
		stty -echo

		printf %s 'Enter your passphrase (invisible): '
		IFS= read -r passphrase
		echo

		# エコーバックを再開させる
		stty "$old_config"

		# 入力された passphrase が誤っている場合
		if [ "$(hmac_sha256 "$passphrase" "$secret_key")" != "$(cat "$SIGN_CONFIG_DIR/passphrase")" ]; then
			echo_fatal 'Passphrase is wrong.' >&2
			return $EX_SOFTWARE
		fi
	else
		passphrase=$1 && shift
	fi

	# 第4オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	password=$(hexadecimal_to_duohexagesimal "$(hmac_sha256 "$service_name $your_id" "$passphrase")")
	printf %s "$password" | xsel -bi
}

#
# hexadecimal_to_duohexagesimal <hex>
#
hexadecimal_to_duohexagesimal() {
	hex=$1 && shift

	# 第2オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	uppercase_hex=$(printf %s "$hex" | LC_COLLATE=C tr a-z A-Z)

	dec=$(echo "ibase=16; $uppercase_hex" | bc_with_no_linefeeds)

	duohexagesimal_digits=$(echo "obase=62; $dec" | bc_with_no_linefeeds | tr ' ' '\n' | bc_with_no_linefeeds)

	echo "$duohexagesimal_digits" | while read i
	do
		if [ 0 -le "$i" ] && [ "$i" -le 9 ]; then
			charcode=$(echo "$i - 0 + 48" | bc)
		elif [ 10 -le "$i" ] && [ "$i" -le 35 ]; then
			charcode=$(echo "$i - 10 + 65" | bc)
		elif [ 36 -le "$i" ] && [ "$i" -le 61 ]; then
			charcode=$(echo "$i - 36 + 97" | bc)
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
	message=$1 && shift
	secret_key=$1 && shift

	# 第3オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	printf %s "$(printf %s "$message" | openssl dgst -sha256 -hmac "$secret_key" | sed 's/^.* //')"
}

#
# echo_info [<string> ..]
#
echo_info() {
	echo "[INFO]   $@"
}

#
# echo_fatal [<string> ..]
#
echo_fatal() {
	echo "[FATAL]  $@"
}

#
# until_enter
#
until_enter() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	while true
	do
		printf %s 'Press the enter key. '
		IFS= read dummy </dev/tty

		if [ -z "$dummy" ]; then
			break
		fi
	done
}

# entry
case "$NAME" in
	sign )
		check_dependencies
		main "$@"
	;;

	sign.sh )
		check_dependencies
		main "$@"
	;;

	sign_test.sh )
		check_dependencies
	;;

	* )
		return $EX_USAGE
	;;
esac
