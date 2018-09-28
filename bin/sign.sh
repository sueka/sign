#!/bin/sh

set -eu

if ${DEBUG+:} false; then
	case "$DEBUG" in
		1 | TRUE | True | true )
			set -x
		;;

		'' | 0 | FALSE | False | false )
		;;

		* )
			return 64 # $EX_USAGE (not defined)
		;;
	esac
fi

LF='
'

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

SIGN_CONFIG_DIR="$HOME/.sign"

NAME=$(basename "$0")

#
# check_dependencies
#
check_dependencies() {
	ex=$EX_OK

	if ! command -v openssl 1>/dev/null; then
		echo_fatal "No command 'openssl' found." >&2
		ex=$EX_UNAVAILABLE
	fi

	if ! command -v xsel 1>/dev/null; then
		echo_fatal "No command 'xsel' found." >&2
		ex=$EX_UNAVAILABLE
	fi

	return $ex
}

#
# main init [<operand> ..]
# main up [<operand> ..]
# main in [<operand> ..]
# main migrate [<operand> ..]
#
main() {
	if ! [ 1 -le $# ]; then
		return $EX_USAGE
	fi

	subcommand=$1 && shift

	case "$subcommand" in
		init )
			sign_init "$@"
		;;

		up )
			sign_up "$@"
		;;

		in )
			sign_in "$@"
		;;

		migrate )
			sign_migrate "$@"
		;;

		list )
			sign_list "$@"
		;;

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
	if ! [ $# -eq 0 ]; then
		return $EX_USAGE
	fi

	if [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal "'$SIGN_CONFIG_DIR' does already exist." >&2
		return $EX_SOFTWARE
	fi

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s 'Enter your passphrase (invisible): '
	IFS= read -r passphrase
	echo

	# エコーバックを再開させる
	stty "$old_config"

	if ! echo "$passphrase" | LC_ALL=C grep -q '^[ -~]*$'; then
		echo_fatal 'Passphrase must be zero or more ASCII printable characters.'
		return $EX_SOFTWARE
	fi

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s 'Enter your passphrase again (invisible): '
	IFS= read -r passphrase_again
	echo

	# エコーバックを再開させる
	stty "$old_config"

	if [ "$passphrase" != "$passphrase_again" ]; then
		echo_fatal 'Passphrases do not match.' >&2
		return $EX_SOFTWARE
	fi

	# salt を生成する
	salt=$(tr -dc [:alnum:] </dev/urandom | dd bs=1024 count=1 2>/dev/null)

	# TODO: BEGIN TRANSACTION

	mkdir -p "$SIGN_CONFIG_DIR"
	chmod 755 "$SIGN_CONFIG_DIR"

	touch "$SIGN_CONFIG_DIR/passphrase_hmac"
	chmod 600 "$SIGN_CONFIG_DIR/passphrase_hmac"

	touch "$SIGN_CONFIG_DIR/services"
	chmod 644 "$SIGN_CONFIG_DIR/services"

	# NOTE: この HMAC は $passphrase (secret_key) を認証する
	echo "$salt	$(hmac_sha256 "$salt" "$passphrase")" >"$SIGN_CONFIG_DIR/passphrase_hmac"

	# TODO: COMMIT
}

#
# sign_up [<service name> [<your ID>]]
#
sign_up() {
	unset service_name your_id

	if ! [ $# -le 2 ]; then
		return $EX_USAGE
	fi

	if ! [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal 'Not initialized.' >&2
		return $EX_SOFTWARE
	fi

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s 'Enter your passphrase (invisible): '
	IFS= read -r passphrase
	echo

	# エコーバックを再開させる
	stty "$old_config"

	salt=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f1)
	passphrase_hmac=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f2)

	# passphrase が誤っている場合
	if [ $(hmac_sha256 "$salt" "$passphrase") != "$passphrase_hmac" ]; then
		echo_fatal 'Passphrase is wrong.' >&2
		return $EX_SOFTWARE
	fi

	# 第1オプション無しで呼ばれた場合、サービス名を尋ねる
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

	# サービス名が空文字列の場合
	if [ -z "$service_name" ]; then
		return $EX_SOFTWARE
	fi

	# ID が空文字列の場合
	if [ -z "$your_id" ]; then
		return $EX_SOFTWARE
	fi

	# 指定されたサービス名がサービス名一覧に存在しない場合、作成する
	if ! cut -f1 "$SIGN_CONFIG_DIR/services" | grep -q -- "^$service_name\$"; then

		# TODO: 似たサービス名を表示させる

		# パスワードの長さを尋ねる
		printf "Enter the password length you need (1-44) [44]: "
		read password_length

		if [ -z "$password_length" ]; then
			password_length=44
		fi

		if ! [ "$password_length" -eq "$password_length" ]; then
			echo_fatal 'The password length must be an integer.'
			return $EX_USAGE
		fi

		if ! ([ 1 -le "$password_length" ] && [ "$password_length" -le 44 ]); then
			echo_fatal 'The password length must be between 1 and 44.'
			return $EX_USAGE
		fi

		echo "$service_name	$password_length" >>"$SIGN_CONFIG_DIR/services"

		touch "$SIGN_CONFIG_DIR/${service_name}_ids"
		chmod 644 "$SIGN_CONFIG_DIR/${service_name}_ids"
	fi

	# ID がすでに存在する場合
	if grep -q -- "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids"; then
		echo_fatal "$service_name ID '$your_id' does already exist." >&2
		return $EX_SOFTWARE
	fi

	# TODO: 似た ID を表示させる

	echo "$your_id" >>"$SIGN_CONFIG_DIR/${service_name}_ids"

	copy_password "$service_name" "$your_id" "$passphrase"
	echo_info 'Your password is stored in the clipboard.'
}

#
# sign_in [<service name> [<your ID>]]
#
sign_in() {
	unset service_name your_id

	if ! [ $# -le 2 ]; then
		return $EX_USAGE
	fi

	if ! [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal 'Not initialized.' >&2
		return $EX_SOFTWARE
	fi

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s 'Enter your passphrase (invisible): '
	IFS= read -r passphrase
	echo

	# エコーバックを再開させる
	stty "$old_config"

	salt=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f1)
	passphrase_hmac=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f2)

	# passphrase が誤っている場合
	if [ $(hmac_sha256 "$salt" "$passphrase") != "$passphrase_hmac" ]; then
		echo_fatal 'Passphrase is wrong.' >&2
		return $EX_SOFTWARE
	fi

	# 第1オプション無しで呼ばれた場合、サービス名の設定を後回しにする
	if [ -z "$*" ]; then
		service_name=
	else
		service_name=$1 && shift
	fi

	# 第2オプション無しで呼ばれた場合、 ID の設定を後回しにする
	if [ -z "$*" ]; then
		your_id=
	else
		your_id=$1 && shift
	fi

	service_name=$(complete_as_service_name "$service_name")

	echo_info "Service '$service_name' chosen."

	your_id=$(complete_as_your_id "$service_name" "$your_id")

	echo_info "$service_name ID '$your_id' chosen."

	copy_password "$service_name" "$your_id" "$passphrase"
	echo_info 'Your password is stored in the clipboard.'
}

#
# sign_migrate
#
sign_migrate() {
	if ! [ $# -eq 0 ]; then
		return $EX_USAGE
	fi

	if ! [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal 'Not initialized.' >&2
		return $EX_SOFTWARE
	fi

	salt=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f1)
	old_passphrase_hmac=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f2)

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s 'Enter your old passphrase (invisible): '
	IFS= read -r old_passphrase
	echo

	# エコーバックを再開させる
	stty "$old_config"

	# old_passphrase が誤っている場合
	if [ $(hmac_sha256 "$salt" "$old_passphrase") != "$old_passphrase_hmac" ]; then
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

	if [ "$new_passphrase" != "$new_passphrase_again" ]; then
		echo_fatal 'New passphrases do not match.' >&2
		return $EX_SOFTWARE
	fi

	echo "$salt	$(hmac_sha256 "$salt" "$new_passphrase")" >"$SIGN_CONFIG_DIR/passphrase_hmac"

	cut -f1 "$SIGN_CONFIG_DIR/services" | while read -r service_name
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

	echo_info 'Your passphrase is successfully changed.'
}

#
# sign_list services
# sign list ids <service name>
#
sign_list() {
	if ! ([ $# -eq 1 ] || [ $# -eq 2 ]); then
		return $EX_USAGE
	fi

	the_word_services_or_ids=$1 && shift

	if [ "$the_word_services_or_ids" = 'services' ]; then
		cut -f1 $SIGN_CONFIG_DIR/services
	elif [ "$the_word_services_or_ids" = 'ids' ]; then
		if [ -z "$*" ]; then
			service_name=
		else
			service_name=$1 && shift
		fi

		service_name=$(complete_as_service_name "$service_name")

		cat $SIGN_CONFIG_DIR/${service_name}_ids
	else
		return $EX_USAGE
	fi
}

#
# complete_as_service_name <service name>
#
complete_as_service_name() {
	if ! [ $# -eq 1 ]; then
		return $EX_USAGE
	fi

	service_name=$1 && shift

	_abstract_complete \
		"$service_name" \
		"$(cut -f1 "$SIGN_CONFIG_DIR/services")" \
		"Choose a service:" \
		"Enter the service name"
}

#
# complete_as_your_id <service name> <your id>
#
complete_as_your_id() {
	if ! [ $# -eq 2 ]; then
		return $EX_USAGE
	fi

	service_name=$1 && shift
	your_id=$1 && shift

	_abstract_complete \
		"$your_id" \
		"$(cat "$SIGN_CONFIG_DIR/${service_name}_ids")" \
		"Choose your $service_name ID:" \
		"Enter an ID of yours for $service_name"
}

#
# _abstract_complete <x> <xs> <choose_prompt> <enter_prompt>
#
_abstract_complete() {
	if ! [ $# -eq 4 ]; then
		return $EX_USAGE
	fi

	x=$1 && shift
	xs=$1 && shift
	choose_prompt=$1 && shift
	enter_prompt=$1 && shift

	given_x=$x

	# 指定された値がリストに存在しない場合
	while ! echo "$xs" | grep -q -- "^$x\$"
	do
		if command -v peco 1>/dev/null; then
			x=$(
				echo "$xs" |
				peco --query "$given_x" --prompt "$enter_prompt: "
			)
		elif command -v percol 1>/dev/null; then
			x=$(
				echo "$xs" |
				percol --query "$given_x" --prompt "$enter_prompt:  %q"
			)
		else
			echo "$choose_prompt"

			echo
			echo "$xs" | while read -r line
			do
				echo_indented 2 "$line"
			done
			echo

			printf %s "$enter_prompt: "
			read -r x
		fi
	done

	printf %s "$x"
}

#
# copy_password <service name> <your id> <passphrase>
#
copy_password() {
	if ! [ $# -eq 3 ]; then
		return $EX_USAGE
	fi

	service_name=$1 && shift
	your_id=$1 && shift
	passphrase=$1 && shift

	password_length="$(grep -- "^$service_name	" "$SIGN_CONFIG_DIR/services" | cut -f2)"

	password=$(
		hexadecimal_to_duohexagesimal "$(hmac_sha256 "$service_name$LF$your_id" "$passphrase")" |
		cut -c"-$password_length"
	)
	printf %s "$password" | xsel -bi
}

#
# hexadecimal_to_duohexagesimal <hex>
#
hexadecimal_to_duohexagesimal() {
	if ! [ $# -eq 1 ]; then
		return $EX_USAGE
	fi

	hex=$1 && shift

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
	if ! [ $# -eq 2 ]; then
		return $EX_USAGE
	fi

	message=$1 && shift
	secret_key=$1 && shift

	printf %s "$(printf %s "$message" | openssl dgst -sha256 -hmac "$secret_key" | sed 's/^.* //')"
}

#
# echo_info [<string> ..]
#
echo_info() {
	string="$@"

	first_line=$(echo "$string" | head -n1)
	subsequent_lines=$(echo "$string" | tail -n+2)

	echo "[INFO]    $first_line"

	if [ -n "$subsequent_lines" ]; then
		echo_indented 10 "$subsequent_lines"
	fi
}

#
# echo_fatal [<string> ..]
#
echo_fatal() {
	string="$@"

	first_line=$(echo "$string" | head -n1)
	subsequent_lines=$(echo "$string" | tail -n+2)

	echo "[FATAL]   $first_line"

	if [ -n "$subsequent_lines" ]; then
		echo_indented 10 "$subsequent_lines"
	fi
}

#
# echo_indented <width> <string>
#
echo_indented() {
	if ! [ $# -eq 2 ]; then
		return $EX_USAGE
	fi

	width=$1 && shift
	string=$1 && shift

	echo "$string" | while IFS= read -r line
	do
		printf "%${width}s"
		echo "$line"
	done
}

#
# until_enter
#
until_enter() {
	if ! [ $# -eq 0 ]; then
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
