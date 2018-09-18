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

PROJECT_ROOT_DIR=$(cd "$(dirname "$0")/../.."; pwd)

NAME=$(basename "$0")


. "$PROJECT_ROOT_DIR/bin/sign.sh"

#
# test
#
test() {
	if ! [ $# -eq 0 ]; then
		return $EX_USAGE
	fi

	ex=$EX_OK

	mkdir -p "$PROJECT_ROOT_DIR/test/tmp"

	mkdir -p "$PROJECT_ROOT_DIR/test/tmp/dev"

	PATH_IGNORING_STTY="$PROJECT_ROOT_DIR/test/dummy-stty/bin"':$PATH'

	main_test
	sign_init_test 'sign_init'

	hexadecimal_to_duohexagesimal_test
	hmac_sha256_test
	bc_with_no_linefeeds_test

	rm -r "$PROJECT_ROOT_DIR/test/tmp"

	return $ex
}

#
# main_test
#
main_test() {
	if ! [ $# -eq 0 ]; then
		return $EX_USAGE
	fi

	assert 'main' $EX_USAGE

	sign_init_test 'main init'
}

#
# setup_for_each_sign_init_test
#
setup_for_each_sign_init_test() {
	if ! [ $# -eq 0 ]; then
		return $EX_USAGE
	fi

	SIGN_CONFIG_DIR="$PROJECT_ROOT_DIR/test/tmp/home/.sign"

	if [ -d "$SIGN_CONFIG_DIR" ]; then
		rm -r "$SIGN_CONFIG_DIR"
	fi
}

#
# sign_init_test <sign_init_test_command>
#
sign_init_test() {
	if ! [ $# -eq 1 ]; then
		return $EX_USAGE
	fi

	sign_init_test_command=$1 && shift

	setup_for_each_sign_init_test
	assert "echo 'passphrase${LF}passphrase' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_OK

	setup_for_each_sign_init_test
	assert "echo '#${LF}#' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_OK

	setup_for_each_sign_init_test
	assert "echo 'elif${LF}elif' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_OK

	setup_for_each_sign_init_test
	assert "echo '.${LF}.' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_OK

	setup_for_each_sign_init_test
	assert "echo 'Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor.${LF}Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor.' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_OK

	setup_for_each_sign_init_test
	# passphrase と passphrase_again は完全に一致しなければならない。
	assert "echo 'passphrase${LF}passphrase ' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_SOFTWARE

	setup_for_each_sign_init_test
	# sign_init はオプションを受け付けない。
	assert "$sign_init_test_command :" $EX_USAGE

	setup_for_each_sign_init_test
	# passphrase は空文字列であってもよい。
	assert "echo '' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_OK

	setup_for_each_sign_init_test
	# passphrase は空白のみでもよい。
	assert "echo ' $LF ' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_OK

	setup_for_each_sign_init_test
	# 空白の種類は区別される。
	assert "echo ' $LF	' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_SOFTWARE
}

#
# hexadecimal_to_duohexagesimal_test
#
hexadecimal_to_duohexagesimal_test() {
	if ! [ $# -eq 0 ]; then
		return $EX_USAGE
	fi

	assert 'hexadecimal_to_duohexagesimal 0' 0 '0'
	assert 'hexadecimal_to_duohexagesimal F' 0 'F'
	assert 'hexadecimal_to_duohexagesimal FF' 0 '47'
	assert 'hexadecimal_to_duohexagesimal FFFFFFFFFFFF' 0 '1HvWXNAa7'
}

#
# hmac_sha256_test
#
hmac_sha256_test() {
	if ! [ $# -eq 0 ]; then
		return $EX_USAGE
	fi

	assert 'hmac_sha256 " " " "' 0 '1352c6b2598324a5fb3ad64097ca2d678ddb71d906aa994e2fd0678e0be361aa'
	assert 'hmac_sha256 message secret' 0 '8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b'
}

#
# bc_with_no_linefeeds_test
#
bc_with_no_linefeeds_test() {
	if ! [ $# -eq 0 ]; then
		return $EX_USAGE
	fi

	assert 'echo "ibase=16; FFFFFFFFFFFF" | bc_with_no_linefeeds' 0 '281474976710655'
	assert 'echo "obase=62; 281474976710655" | bc_with_no_linefeeds' 0 ' 01 17 57 32 33 23 10 36 07'
	assert 'echo "obase=94; 281474976710655" | bc_with_no_linefeeds' 0 ' 04 32 01 09 77 41 88 03'
	assert 'echo "obase=1000; 281474976710655" | bc_with_no_linefeeds' 0 ' 281 474 976 710 655'
	assert 'echo "obase=62; 20988936657440586486151264256610222593863921" | bc_with_no_linefeeds' 0 ' 02 01 01 17 11 32 48 01 31 17 36 40 32 55 58 20 38 51 46 25 22 47 58 50 37'
}

#
# assert <command> <expected_exit_status> [<expected_stdout> [<expected_stderr>]]
#
assert() {
	if ! ([ 2 -le $# ] && [ $# -le 4 ]); then
		return $EX_USAGE
	fi

	command=$1 && shift
	expected_exit_status=$1 && shift

	if [ -n "$*" ]; then
		expected_stdout=$1 && shift
	fi

	if [ -n "$*" ]; then
		expected_stderr=$1 && shift
	fi

	# TODO: $command が実行可能であることを確認する

	set_current=$(set +o)
	set +e

	# NOTE: exit する関数を呼ぶと errexit off でも終了してしまうが、 subshell として呼ぶと回避できる。
	(eval "$command" 1>"$PROJECT_ROOT_DIR/test/tmp/dev/stdout" 2>"$PROJECT_ROOT_DIR/test/tmp/dev/stderr")

	actual_exit_status=$?
	eval "$set_current"

	actual_stdout=$(cat "$PROJECT_ROOT_DIR/test/tmp/dev/stdout")
	actual_stderr=$(cat "$PROJECT_ROOT_DIR/test/tmp/dev/stderr")

	if [ "$actual_exit_status" -eq "$expected_exit_status" ]; then
		report_pass "'$command' exited with $actual_exit_status as expected."
	else
		report_failure "'$command' is expected to exit with $expected_exit_status, but it exited with $actual_exit_status."
	fi

	if ${expected_stdout+:} false; then
		if [ "$actual_stdout" = "$expected_stdout" ]; then
			report_pass "'$command' printed $actual_stdout as expected."
		else
			report_failure "'$command' is expected to print $expected_stdout, but it printed $actual_stdout."
		fi

		unset expected_stdout
	fi

	if ${expected_stderr+:} false; then
		if [ "$actual_stderr" = "$expected_stderr" ]; then
			report_pass "'$command' printed $actual_stderr as expected."
		else
			report_failure "'$command' is expected to print $expected_stderr, but it printed $actual_stderr."
		fi

		unset expected_stderr
	fi
}



#
# report_pass [<string> ..]
#
report_pass() {
	string="$@"

	first_line=$(echo "$string" | head -n1)
	subsequent_lines=$(echo "$string" | tail -n+2)

	echo "[PASS]    $first_line"

	if [ -n "$subsequent_lines" ]; then
		echo_indented 10 "$subsequent_lines"
	fi
}

#
# report_failure [<string> ..]
#
report_failure() {
	ex=$EX_SOFTWARE

	string="$@"

	first_line=$(echo "$string" | head -n1)
	subsequent_lines=$(echo "$string" | tail -n+2)

	echo "[FAILURE] $first_line"

	if [ -n "$subsequent_lines" ]; then
		echo_indented 10 "$subsequent_lines"
	fi
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

# entry
case "$NAME" in
	sign_test.sh )
		test "$@"
	;;

	sign_test_test.sh )
	;;

	* )
		return $EX_USAGE
	;;
esac
