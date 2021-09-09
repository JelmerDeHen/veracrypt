#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
	exit 1
fi
DIR=$(cd $(dirname "$(readlink -f "${BASH_SOURCE[0]}")") && pwd)
source "${DIR}/veracrypt.sh"
function usage () {
	local _CMDLIST
	printf -v _CMDLIST '%s|' "${_CMDS[@]}"
	_CMDLIST="${_CMDLIST%|}"
	printf '%s: %s <%s> ...\n' "${FUNCNAME[0]}" "${0}" "${_CMDLIST}"
}
case "${1,,}" in
	mount)
		veracryptmount "${2}"
		;;
	unmount)
		veracryptunmount "${2}"
		;;
	shrink)
		veracryptshrink "${2}"
		;;
	mv)
		veracryptshrink "${2}" "${3}"
		;;
	rm)
		veracryptrm "${2}"
		;;
	create)
		veracryptcreate "${2}"
		;;
	ls)
		veracryptprojects
		;;
	*)
		usage
		;;
esac
