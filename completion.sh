#!/usr/bin/env bash
DIR=$(cd $(dirname "$(readlink -f "${BASH_SOURCE[0]}")") && pwd)
source "${DIR}/veracrypt.sh"
_veracrypt_complete() {
	local _OPTS=
	local _RECIPE="${COMP_WORDS[2]}"
	if [ ${#COMP_WORDS[@]} -eq 2 ]; then
		printf -v _OPTS '%s\n' "${_CMDS[@]}"
		COMPREPLY=( $(compgen -W "${_OPTS}" -- "${COMP_WORDS[COMP_CWORD]}" ) )
	elif [ "${#COMP_WORDS[@]}" -eq 3 ]; then
		case "${COMP_WORDS[1]^^}" in
			MOUNT|UNMOUNT|MV|RM|SHRINK)
				COMPREPLY=( $(compgen -W "$(veracryptprojects)" -- "${COMP_WORDS[COMP_CWORD]}" ) )
				;;
			*)
				;;
		esac
	fi
}
complete -F _veracrypt_complete vera $0
