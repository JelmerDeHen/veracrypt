#!/usr/bin/env bash

#######################################
# Get directory of script
# Globals:
#   PWD
#   BASH_SOURCE
# Arguments:
#   None
# Outputs:
#   Directory of script
#######################################
function _vera_pwd () {
  local -a flags

  flags=( -f "${BASH_SOURCE[0]}" )
  if ! src="$(readlink "${flags[@]}")"; then
    return 1
  fi

  local pwd="${PWD}"
  flags=("${src}")
  if ! cd "${src%/*}"; then
    return 2
  fi
  local relativePwd="${PWD}"

  flags=("${pwd}")
  if ! cd "${flags[@]}"; then
    return 3
  fi

  printf '%s\n' "${relativePwd}"
}
declare -A VERACRYPT
while read -r; do
    if [[ "${REPLY%%=*}" == "VERACRYPT_VOLUMES" ]]; then
      VERACRYPT[VOLUMES]="${REPLY#*=}"
    elif [[ "${REPLY%%=*}" == "VERACRYPT_KEYFILES" ]]; then
      VERACRYPT[KEYFILES]="${REPLY#*=}"
    elif [[ "${REPLY%%=*}" == "VERACRYPT_MOUNTPOINT" ]]; then
      VERACRYPT[MOUNTPOINT]="${REPLY#*=}"
    elif [[ "${REPLY%%=*}" == "VERACRYPT_VOLSIZE" ]]; then
      VERACRYPT[VOLSIZE]="${REPLY#*=}"
    fi
done <"$(_vera_pwd)/env"

#######################################
# Get all volumes found in volume storage directories
# Globals:
#   VERACRYPT[VOLUMES]
# Arguments:
#   None
# Outputs:
#   Line-separated volume paths
#######################################
function list_volumes () {
  if [[ ! -x "$(command -v find)" ]]; then
    printf >&2 '%s: find: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local -a flags
  IFS=, read -ra flags <<<"${VERACRYPT[VOLUMES]}"
  flags+=(-mindepth 1 -maxdepth 1 -type f -name '*.hc')

  find "${flags[@]}" 2>/dev/null

  # Don't relay find's return code
  return 0
}

#######################################
# List project names
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Sorted line-separated projects
#######################################
function list_projects () {
  local project
  while read -r project; do
    project="${project##*/}"
    project="${project%.hc}"
    printf '%s\n' "${project}"
  done < <(list_volumes) | sort
}

_vera_complete() {
  local _vera_projects
  _vera_projects="$(list_projects)"
	if [ ${#COMP_WORDS[@]} -eq 2 ]; then
    local -a flags
    flags=( -W $'create\nls\nmount\nmv\nrm\nshrink\nunmount' -- "${COMP_WORDS[COMP_CWORD]}" )
    mapfile -t COMPREPLY < <(compgen "${flags[@]}")
	elif [ "${#COMP_WORDS[@]}" -eq 3 ]; then
		case "${COMP_WORDS[1],,}" in
      ls|mount|mv|rm|shrink|unmount)
        local -a flags
        flags=( -W "${_vera_projects}" -- "${COMP_WORDS[COMP_CWORD]}" )
        mapfile -t COMPREPLY < <(compgen "${flags[@]}")
				;;
			*)
				;;
		esac
	fi
}

complete -F _vera_complete vera "${0}"
