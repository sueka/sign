#!/bin/sh -u

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

#
# setup
#
setup() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	PROJECT_ROOT_DIR=$(cd "$(dirname "$0")/../.."; pwd)

	. "$PROJECT_ROOT_DIR/bin/sign.sh"

	mkdir -p "$PROJECT_ROOT_DIR/test/tmp"

	mkdir -p "$PROJECT_ROOT_DIR/test/tmp/bin"

	echo '#!/bin/sh' >"$PROJECT_ROOT_DIR/test/tmp/bin/stty"

	chmod +x "$PROJECT_ROOT_DIR/test/tmp/bin/stty"

	PATH_IGNORING_STTY="$PROJECT_ROOT_DIR/test/tmp/bin:$PATH"
}

#
# teardown
#
teardown() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	rm -r "$PROJECT_ROOT_DIR/test/tmp"
}

#
# test
#
test() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	setup

	main_test
	sign_init_test

	teardown
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
}

#
# sign_init_test
#
sign_init_test() {

	# オプション付きで呼ばれた場合
	if [ -n "$*" ]; then
		return $EX_USAGE
	fi

	SIGN_CONFIG_DIR="$PROJECT_ROOT_DIR/test/tmp/home/.sign"

	valid_passphrases=$(cat <<-'EOD'
		passphrase
		#
		elif
		.
		Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor.
	EOD
	)

	echo "$valid_passphrases" | while IFS= read -r line
	do
		input="$line\n$line"

		assert "echo '$input' | PATH="$PATH_IGNORING_STTY" sign_init" $EX_OK
		rm -r "$PROJECT_ROOT_DIR/test/tmp/home/.sign"
	done

	assert "sign_init :" $EX_USAGE
	assert "echo '' | PATH="$PATH_IGNORING_STTY" sign_init" $EX_SOFTWARE
}

#
# assert <command> <expected_exit_status>
#
assert() {
	command=$1 && shift
	expected_exit_status=$1 && shift

	# TODO: $command が実行可能であることを確認する

	eval $command >/dev/null 2>&1
	actual_exit_status=$?

	if [ "$actual_exit_status" -eq "$expected_exit_status" ]; then
		echo_info "'$command' exited with $actual_exit_status as expected."
	else
		echo_fatal "'$command' is expected to exit with $expected_exit_status, but it exited with $actual_exit_status."
	fi
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

test "$@"