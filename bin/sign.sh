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

	if ! command -v xsel 1>/dev/null && ! command -v pbcopy 1>/dev/null; then
		echo_fatal "No command 'xsel' nor 'pbcopy' found." >&2
		ex=$EX_UNAVAILABLE
	fi

	return $ex
}

#
# main init [<operand> ..]
# main up [<operand> ..]
# main in [<operand> ..]
# main migrate [<operand> ..]
# main list [<operand> ..]
#
main() {
	if ! [ 1 -le $# ]; then
		echo 'Usage:  sign init'
		echo '        sign up <service name> <your ID>'
		echo '        sign in <service name> <your ID>'
		echo '        sign migrate'
		echo '        sign list services'
		echo '        sign list ids <service name>'
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
		echo 'Usage:  sign init'
		return $EX_USAGE
	fi

	if [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal "'$SIGN_CONFIG_DIR' does already exist." >&2
		return $EX_USAGE
	fi

	ask_passphrase 'Enter your passphrase (invisible): ' passphrase

	if ! echo "$passphrase" | LC_ALL=C grep -q '^[ -~]*$'; then
		echo_fatal 'Passphrase must be zero or more ASCII printable characters.'
		return $EX_USAGE
	fi

	ask_passphrase 'Enter your passphrase again (invisible): ' passphrase_again

	if [ "$passphrase" != "$passphrase_again" ]; then
		echo_fatal 'Passphrases do not match.' >&2
		return $EX_USAGE
	fi

	# salt を生成する
	salt=$(LC_CTYPE=C tr -dc [:alnum:] </dev/urandom | dd bs=1024 count=1 2>/dev/null)

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
# sign_up <service name> <your ID>
#
sign_up() {
	if ! [ $# -eq 2 ]; then
		echo 'Usage:  sign up <service name> <your ID>'
		return $EX_USAGE
	fi

	service_name=$1 && shift
	your_id=$1 && shift

	if ! [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal 'Not initialized.' >&2
		return $EX_USAGE
	fi

	ask_passphrase 'Enter your passphrase (invisible): ' passphrase

	salt=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f1)
	passphrase_hmac=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f2)

	# passphrase が誤っている場合
	if [ $(hmac_sha256 "$salt" "$passphrase") != "$passphrase_hmac" ]; then
		echo_fatal 'Passphrase is wrong.' >&2
		return $EX_USAGE
	fi

	if ! echo "$service_name" | LC_ALL=C grep -q '^[!-~]\+\( \+[!-~]\+\)*$'; then
		echo_fatal 'Service name must be one or more ASCII printable characters with no SPACEs at the both ends.'
		return $EX_USAGE
	fi

	if ! echo "$your_id" | LC_ALL=C grep -q '^[!-~]\+\( \+[!-~]\+\)*$'; then
		echo_fatal 'ID must be one or more ASCII printable characters with no SPACEs at the both ends.'
		return $EX_USAGE
	fi

	# 指定されたサービス名がサービス名一覧に存在しない場合、作成する
	if ! cut -f1 "$SIGN_CONFIG_DIR/services" | grep -q -- "^$service_name\$"; then

		# TODO: 似たサービス名を表示させる

		# パスワードの長さを尋ねる
		printf "Enter the password length you need (1-43) [43]: "
		read password_length

		if [ -z "$password_length" ]; then
			password_length=43
		fi

		if ! [ "$password_length" -eq "$password_length" ]; then
			echo_fatal 'The password length must be an integer.'
			return $EX_USAGE
		fi

		if ! ([ 1 -le "$password_length" ] && [ "$password_length" -le 43 ]); then
			echo_fatal 'The password length must be between 1 and 43.'
			return $EX_USAGE
		fi

		echo "$service_name	$password_length" >>"$SIGN_CONFIG_DIR/services"

		touch "$SIGN_CONFIG_DIR/${service_name}_ids"
		chmod 644 "$SIGN_CONFIG_DIR/${service_name}_ids"
	fi

	# ID がすでに存在する場合
	if grep -q -- "^$your_id\$" "$SIGN_CONFIG_DIR/${service_name}_ids"; then
		echo_fatal "$service_name ID '$your_id' does already exist." >&2
		return $EX_USAGE
	fi

	# TODO: 似た ID を表示させる

	echo "$your_id" >>"$SIGN_CONFIG_DIR/${service_name}_ids"

	copy_password "$service_name" "$your_id" "$passphrase"
	echo_info 'Your password is stored in the clipboard.'
}

#
# sign_in <service name> <your ID>
#
sign_in() {
	if ! [ $# -eq 2 ]; then
		echo 'Usage:  sign in <service name> <your ID>'
		return $EX_USAGE
	fi

	service_name=$1 && shift
	your_id=$1 && shift

	if ! [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal 'Not initialized.' >&2
		return $EX_USAGE
	fi

	ask_passphrase 'Enter your passphrase (invisible): ' passphrase

	salt=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f1)
	passphrase_hmac=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f2)

	# passphrase が誤っている場合
	if [ $(hmac_sha256 "$salt" "$passphrase") != "$passphrase_hmac" ]; then
		echo_fatal 'Passphrase is wrong.' >&2
		return $EX_USAGE
	fi

	copy_password "$service_name" "$your_id" "$passphrase"
	echo_info 'Your password is stored in the clipboard.'
}

#
# ask_passphrase <prompt> <var_name>
#
ask_passphrase() {
	if ! [ $# -eq 2 ]; then
		return $EX_USAGE
	fi

	prompt=$1 && shift
	var_name=$1 && shift

	# エコーバックを停止させる
	old_config=$(stty -g)
	stty -echo

	printf %s "$prompt"
	IFS= read -r "$var_name"
	echo

	# エコーバックを再開させる
	stty "$old_config"
}

#
# sign_migrate
#
sign_migrate() {
	if ! [ $# -eq 0 ]; then
		echo 'Usage:  sign migrate'
		return $EX_USAGE
	fi

	if ! [ -d "$SIGN_CONFIG_DIR" ]; then
		echo_fatal 'Not initialized.' >&2
		return $EX_USAGE
	fi

	salt=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f1)
	old_passphrase_hmac=$(cat "$SIGN_CONFIG_DIR/passphrase_hmac" | cut -f2)

	ask_passphrase 'Enter your old passphrase (invisible): ' old_passphrase

	# old_passphrase が誤っている場合
	if [ $(hmac_sha256 "$salt" "$old_passphrase") != "$old_passphrase_hmac" ]; then
		echo_fatal 'Passphrase is wrong.' >&2
		return $EX_USAGE
	fi

	ask_passphrase 'Enter your new passphrase (invisible): ' new_passphrase
	ask_passphrase 'Enter your new passphrase again (invisible): ' new_passphrase_again

	if [ "$new_passphrase" != "$new_passphrase_again" ]; then
		echo_fatal 'New passphrases do not match.' >&2
		return $EX_USAGE
	fi

	echo "$salt	$(hmac_sha256 "$salt" "$new_passphrase")" >"$SIGN_CONFIG_DIR/passphrase_hmac"

	cut -f1 "$SIGN_CONFIG_DIR/services" | while read -r service_name
	do
		cat "$SIGN_CONFIG_DIR/${service_name}_ids" | while read -r your_id
		do
			echo_info "Changing your password for $service_name ID '$your_id'.."

			printf %s "$your_id" | ubiquitous_pbcopy
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
# sign_list ids <service name>
#
sign_list() {
	if ! [ 1 -le $# ]; then
		echo 'Usage:  sign list services'
		echo '        sign list ids <service name>'
		return $EX_USAGE
	fi

	the_word_services_or_ids=$1 && shift

	if [ "$the_word_services_or_ids" = 'services' ]; then
		cut -f1 $SIGN_CONFIG_DIR/services
	elif [ "$the_word_services_or_ids" = 'ids' ]; then
		if ! [ $# -eq 1 ]; then
			echo 'Usage:  sign list ids <service name>'
			return $EX_USAGE
		fi

		service_name=$1 && shift

		cat $SIGN_CONFIG_DIR/${service_name}_ids
	else
		echo 'Usage:  sign list services'
		echo '        sign list ids <service name>'
		return $EX_USAGE
	fi
}

#
# copy_password <service name> <your ID> <passphrase>
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
	printf %s "$password" | ubiquitous_pbcopy
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
	bc "$@" </dev/stdin | sed -e':_' -e'$!N' -e'$!b_' -e's/\\\n//g'
}

#
# ubiquitous_pbcopy
#
ubiquitous_pbcopy() {
	if command -v xsel >/dev/null; then
		xsel -bi </dev/stdin
	elif command -v pbcopy >/dev/null; then
		pbcopy </dev/stdin
	else
		return $EX_SOFTWARE
	fi
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
		IFS= read -r dummy </dev/tty

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
