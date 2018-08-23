#!/bin/sh

EX_OK=0
EX_USAGE=64

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
		COMPREPLY=($(compgen -W "init register get migrate" -- "$cur"))

		return $EX_OK
	fi

	if (( $COMP_CWORD == 2 )); then
		case "$subcommand" in
			'register' | 'get' )
				service_names=$(cat ~/.sign/service_names)
				COMPREPLY=($(compgen -W "$service_names" -- "$cur"))

				return $EX_OK
			;;

			'init' | 'migrate' )
				if [ -n "$cur" ]; then
					return $EX_USAGE
				fi

				return $EX_OK
			;;
		esac
	fi

	if (( $COMP_CWORD == 3 )); then
		case "$subcommand" in
			'get' )
				service_names=$(cat ~/.sign/service_names)
				service_name=$operand_1

				if ! echo "$service_names" | grep "^$service_name\$" 1>/dev/null; then
					return $EX_USAGE
				fi

				your_ids=$(cat ~/".sign/${service_name}_ids")
				COMPREPLY=($(compgen -W "$your_ids" -- "$cur"))

				return $EX_OK
			;;

			'init' | 'register' | 'migrate' )
				if [ -n "$cur" ]; then
					return $EX_USAGE
				fi

				return $EX_OK
			;;
		esac
	fi
}

complete -F _complete_sign sign
