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
		elif ! [ -f "$SIGN_CONFIG_DIR/services" ]; then
			COMPREPLY=($(compgen -W "up migrate" -- "$cur"))
		else
			COMPREPLY=($(compgen -W "up in migrate list" -- "$cur"))
		fi

		return $EX_OK
	fi

	if (( $COMP_CWORD == 2 )); then
		case "$subcommand" in
			'up' )
				if [ -f "$SIGN_CONFIG_DIR/services" ]; then
					service_names=$(cut -f1 "$SIGN_CONFIG_DIR/services")
					COMPREPLY=($(compgen -W "$service_names" -- "$cur"))
				fi

				return $EX_OK
			;;

			'in' )
				service_names=$(cut -f1 "$SIGN_CONFIG_DIR/services")
				COMPREPLY=($(compgen -W "$service_names" -- "$cur"))

				return $EX_OK
			;;

			'list' )
				COMPREPLY=($(compgen -W 'services ids' -- "$cur"))

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
			'in' )
				service_names=$(cut -f1 "$SIGN_CONFIG_DIR/services")
				service_name=$operand_1

				if ! echo "$service_names" | grep -q -- "^$service_name\$"; then
					return $EX_USAGE
				fi

				your_ids=$(cat "$SIGN_CONFIG_DIR/${service_name}_ids")
				COMPREPLY=($(compgen -W "$your_ids" -- "$cur"))

				return $EX_OK
			;;

			'up' )
				if [ -n "$cur" ]; then
					return $EX_USAGE
				fi

				return $EX_OK
			;;

			'list' )
				case "$operand_1" in
					'services' )
						return $EX_OK
					;;

					'ids' )
						service_names=$(cut -f1 "$SIGN_CONFIG_DIR/services")
						COMPREPLY=($(compgen -W "$service_names" -- "$cur"))

						return $EX_OK
					;;
				esac
			;;

			'init' | 'migrate' )
				return $EX_USAGE
			;;
		esac
	fi

	return $EX_USAGE
}

complete -F _complete_sign sign
