#!/bin/sh

set -eu

PROJECT_ROOT_DIR=$(cd "$(dirname "$0")/../.."; pwd)

. "$PROJECT_ROOT_DIR/bin/sign.sh"

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

LF='
'

NAME=$(basename "$0")

#
# test
#
test() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	exit_code=$EX_OK

	mkdir -p "$PROJECT_ROOT_DIR/test/tmp"

	mkdir -p "$PROJECT_ROOT_DIR/test/tmp/dev"

	PATH_IGNORING_STTY="$PROJECT_ROOT_DIR/test/dummy-stty/bin"':$PATH'

	main_test
	sign_init_test 'sign_init'

	rm -r "$PROJECT_ROOT_DIR/test/tmp"

	return $exit_code
}

#
# main_test
#
main_test() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	assert 'main' $EX_USAGE

	sign_init_test 'main init'
}

#
# setup_for_each_sign_init_test
#
setup_for_each_sign_init_test() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
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

	# オプション無しで呼ばれた場合
	if [ -z "$*" ]; then
		return $EX_USAGE
	fi

	sign_init_test_command=$1 && shift

	# 第2オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

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
	# passphrase は空文字列であってはならない。
	assert "echo '' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_SOFTWARE

	setup_for_each_sign_init_test
	# passphrase は空白のみでもよい。
	assert "echo ' $LF ' | PATH="$PATH_IGNORING_STTY" $sign_init_test_command" $EX_OK
}

#
# assert <command> <expected_exit_status> [<expected_stdout> [<expected_stderr>]]
#
assert() {
	command=$1 && shift
	expected_exit_status=$1 && shift

	if [ -n "$*" ]; then
		expected_stdout=$1 && shift

		if [ -n "$*" ]; then
			expected_stderr=$1 && shift
		fi
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
	fi

	if ${expected_stderr+:} false; then
		if [ "$actual_stderr" = "$expected_stderr" ]; then
			report_pass "'$command' printed $actual_stderr as expected."
		else
			report_failure "'$command' is expected to print $expected_stderr, but it printed $actual_stderr."
		fi
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
		echo_indented "$subsequent_lines" 10
	fi
}

#
# report_failure [<string> ..]
#
report_failure() {
	exit_code=$EX_SOFTWARE

	string="$@"

	first_line=$(echo "$string" | head -n1)
	subsequent_lines=$(echo "$string" | tail -n+2)

	echo "[FAILURE] $first_line"

	if [ -n "$subsequent_lines" ]; then
		echo_indented "$subsequent_lines" 10
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
		echo_indented "$subsequent_lines" 10
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
		echo_indented "$subsequent_lines" 10
	fi
}

#
# echo_indented <string> <width>
#
echo_indented() {
	string=$1 && shift
	width=$1 && shift

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
