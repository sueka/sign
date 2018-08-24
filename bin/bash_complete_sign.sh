#!/bin/bash

EX_OK=0
EX_USAGE=64

SIGN_CONFIG_DIR="$HOME/.sign"

_complete_sign() {
	COMPREPLY=()

	local cur="${COMP_WORDS[COMP_CWORD]}"

	local command="${COMP_WORDS[0]}"
	local subcommand="${COMP_WORDS[1]}"
	local operand_1="${COMP_WORDS[2]}"
	local operand_2="${COMP_WORDS[3]}"

	if ! [ "$command" = 'sign' ]; then
		return $EX_USAGE
	fi

	# $COMP_CWORD >= 1

	if (( $COMP_CWORD == 1 )); then
		if ! [ -d "$SIGN_CONFIG_DIR" ]; then
			COMPREPLY=($(compgen -W "init" -- "$cur"))
		elif ! [ -f "$SIGN_CONFIG_DIR/service_names" ]; then
			COMPREPLY=($(compgen -W "register migrate" -- "$cur"))
		else
			COMPREPLY=($(compgen -W "register get migrate" -- "$cur"))
		fi

		return $EX_OK
	fi

	if (( $COMP_CWORD == 2 )); then
		case "$subcommand" in
			'register' )
				if [ -f "$SIGN_CONFIG_DIR/service_names" ]; then
					service_names=$(cat "$SIGN_CONFIG_DIR/service_names")
					COMPREPLY=($(compgen -W "$service_names" -- "$cur"))
				fi

				return $EX_OK
			;;

			'get' )
				service_names=$(cat "$SIGN_CONFIG_DIR/service_names")
				COMPREPLY=($(compgen -W "$service_names" -- "$cur"))

				return $EX_OK
			;;

			'init' | 'migrate' )
				if [ -n "$cur" ]; then
					return $EX_OK
				fi

				return $EX_OK
			;;
		esac
	fi

	if (( $COMP_CWORD == 3 )); then
		case "$subcommand" in
			'get' )
				service_names=$(cat "$SIGN_CONFIG_DIR/service_names")
				service_name=$operand_1

				if ! echo "$service_names" | grep "^$service_name\$" 1>/dev/null; then
					return $EX_OK
				fi

				your_ids=$(cat "$SIGN_CONFIG_DIR/${service_name}_ids")
				COMPREPLY=($(compgen -W "$your_ids" -- "$cur"))

				return $EX_OK
			;;

			'init' | 'register' | 'migrate' )
				if [ -n "$cur" ]; then
					return $EX_OK
				fi

				return $EX_OK
			;;
		esac
	fi
}

complete -F _complete_sign sign
