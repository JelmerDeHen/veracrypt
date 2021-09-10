#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
	exit 1
fi
declare -A VERACRYPT=(
	["VOLUMES"]="/data/vera,/data3/vera,/data4/vera"
	["KEYFILES"]="/.../secrets/veracrypt"
	["MOUNTPOINT"]="/mnt"
	["VOLSIZE"]="$((50*1024))"
)
declare -a _CMDS=("mount" "unmount" "shrink" "mv" "rm" "create" "ls")
# veracryptismounted <_VOLUME>
function veracryptismounted () {
	local _VOLUME="${1}"
	if [ ! -f "${_VOLUME}" ]; then
		printf >&2 '%s: %s is not a file (from %s)\n' "${FUNCNAME[0]}" "${_VOLUME}" "${FUNCNAME[1]}"
		return 1
	fi
	veracrypt &>/dev/null -t -l "${_VOLUME}"
	return $?
}
# _VOLUME to _KEYFILE: ${VERACRYPT[KEYFILES]}/${_VOLUME%.hc}.key
function veracryptkeyfile () {
	local _VOLUME="${1}" _KEYFILE
	if [ -z "${_VOLUME}" ]; then
		printf >&2 '%s: %s <VOLUME>\n' "${FUNCNAME[0]}" "${FUNCNAME[0]}"
		return 1
	fi
	local _KEYFILE="${_VOLUME##*/}"
	printf -v _KEYFILE '%s/%s.key' "${VERACRYPT[KEYFILES]}" "${_KEYFILE%.hc}"
	printf '%s\n' "${_KEYFILE}"
}
# veracryptmountpoint <_VOLUME>
# VOLUME to ${VERACRYPT[MOUNTPOINT]}/${_NAME}
function veracryptmountpoint () {
	local _VOLUME="${1}"
	if [ -z "${_VOLUME}" ]; then
		printf >&2 '%s: %s <VOLUME>\n' "${FUNCNAME[0]}" "${FUNCNAME[0]}"
		return 1
	fi
	local _MOUNTPOINT="${_VOLUME##*/}"
	printf -v _MOUNTPOINT '%s/%s/' "${VERACRYPT[MOUNTPOINT]}" "${_MOUNTPOINT%.hc}"
	printf '%s\n' "${_MOUNTPOINT}"
}
# veracryptvolumes
# List volumes in ${VERACRYPT[VOLUMES]}
function veracryptvolumes () {
	find ${VERACRYPT[VOLUMES]//,/ } -mindepth 1 -maxdepth 1 -type f -name '*.hc' 2>/dev/null
}
# veracryptprojects
# List projects
function veracryptprojects () {
	while read -r; do
		REPLY="${REPLY##*/}"
		REPLY="${REPLY%.hc}"
		printf '%s\n' "${REPLY}"
	done < <(veracryptvolumes) | sort
}
# veracryptmountall
# Mount each _VOLUME found in ${VERACRYPT[VOLUMES]}
function veracryptmountall () {
	local _VOLUME _KEYFILE _MOUNTPOINT _MOUNTCMD
	set -- $(veracryptvolumes)
	for _VOLUME; do
		veracryptmountvolume "${_VOLUME}"
	done
}
# veracryptmountvolume <_VOLUME>
# Mounts _VOLUME
function veracryptmountvolume () {
	local _VOLUME="${1}" _KEYFILE _MOUNTPOINT _MOUNTCMD
	if veracryptismounted "${_VOLUME}"; then
		return 0
	fi
	_KEYFILE=$(veracryptkeyfile "${_VOLUME}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not obtain keyfile "%s" for volume "%s"\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
		return 1
	elif [ ! -f "${_KEYFILE}" ]; then
		printf >&2 '%s: Keyfile "%s" does not exist\n' "${FUNCNAME[0]}" "${_KEYFILE}"
		return 2
	elif [ ! -s "${_KEYFILE}" ]; then
		printf >&2 '%s: Keyfile %s was empty (perms?)\n' "${FUNCNAME[0]}" "${_KEYFILE}"
		return 3
	fi
	_MOUNTPOINT=$(veracryptmountpoint "${_VOLUME}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not get mountpoint for %s\n' "${FUNCNAME[0]}" "${_VOLUME}"
		return 4
	elif [ ! -d "${_MOUNTPOINT}" ]; then
		mkdir -pv "${_MOUNTPOINT}"
		if [ $? -ne 0 ]; then
			printf >&2 '%s: Mountpoint directory does not exist %s, error creating it\n' "${FUNCNAME[0]}" "${_MOUNTPOINT}"
			return 5
		fi
	fi
	printf '%s: _VOLUME=%s; _KEYFILE=%s _MOUNTPOINT=%s\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}" "${_MOUNTPOINT}"
	printf -v _MOUNTCMD 'veracrypt -t --non-interactive --mount %s -k %s %s' "${_VOLUME}" "${_KEYFILE}" "${_MOUNTPOINT}"
	$_MOUNTCMD
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Mount command error: %s\n' "${FUNCNAME[0]}" "${_MOUNTCMD}"
		return 6
	fi
}
# _getVolume <_PROJECT|_VOLUME>
function _getVolume () {
	local _VOLUME
	# Absolute
	if [ "${1:0:1}" = "/" ]; then
		printf '%s\n' "${1}"
		return 0
	fi
	# Project name
	_VOLUME=$(_getVolumeByProject "${1}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: No volume associated with %s\n' "${FUNCNAME[0]}" "${1}"
		return 1
	fi
	printf '%s\n' "${_VOLUME}"
}

# veracryptmount <_PROJECT|_VOLUME|>
# Mount _VOLUME associated with project
# Or mount _VOLUME
# When _PROJECT is empty, mount all
function veracryptmount () {
	local _PROJECT="${1}" _VOLUME
	if [ -z "${_PROJECT}" ]; then
		veracryptmountall
		return $?
	fi
	_VOLUME=$(_getVolume "${_PROJECT}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: %s was not a volume or project\n' "${FUNCNAME[0]}" "${_PROJECT}"
		return 1
	fi
	veracryptmountvolume "${_VOLUME}"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not mount %s\n' "${_VOLUME}"
		return 2
	fi
}
# veracryptbusy <DEV>
# Uses lsof to see if volume is busy
# Returns 0 when volume is not busy
function veracryptbusy () {
	local _DEV="${1}"
	if [ -z "${_DEV}" ]; then
		printf >&2 '%s: %s <DEV>\n' "${FUNCNAME[0]}" "${FUNCNAME[0]}"
		return 1
	fi
	# Exclude FUSE
	local _LSOFCMD
	while read -r; do
		printf -v _LSOFCMD '%s-e %s ' "${_LSOFCMD}" "${REPLY}"
	done < <(find 2>/dev/null /run -name gvfs )
	_LSOFCMD="${_LSOFCMD% }"
	# TODO: lsof is dependency
	printf -v _LSOFCMD 'lsof %s +f -- %s' "${_LSOFCMD}" "${_DEV}"
	$_LSOFCMD
	return $?
}
# veracryptunmountall
# Unounts each _VOLUME found in ${VERACRYPT[VOLUMES]}
function veracryptunmountall () {
	set -- $(veracryptvolumes)
	local _ERRNO
	for _VOLUME; do
		if ! veracryptismounted "${_VOLUME}"; then
			continue
		fi
		veracryptunmountvolume "${_VOLUME}"
		_ERRNO=$?
		if [ $_ERRNO -ne 0 ]; then
			printf >&2 '%s: Unmounting %s failed (%d)\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_ERRNO}"
		else
			printf '%s: %s has been unmounted\n' "${FUNCNAME[0]}" "${_VOLUME}"
		fi
	done
}
# veracryptunmountvolume <_VOLUME>
# Unmount specific veracrypt volume
function veracryptunmountvolume () {
	local _VOLUME="${1}" _INDEX _VOLFILE _MAPPERDEV _MOUNTPOINT _ERRNO _UNMOUNTCMD
	if [ ! -f "${_VOLUME}" ]; then
		printf >&2 '%s: %s is not a file\n' "${FUNCNAME[0]}" "${_VOLUME}"
		return 1
	fi
	if ! veracryptismounted "${_VOLUME}"; then
		return 0
	fi
	read -r _INDEX _VOLFILE _MAPPERDEV _MOUNTPOINT < <(veracrypt -t -l "${_VOLUME}")
	if veracryptbusy "${_MAPPERDEV}"; then
		printf >&2 '%s: %s is busy\n' "${FUNCNAME[0]}" "${_VOLUME}"
		return 1
	fi
	printf -v _UNMOUNTCMD 'veracrypt -t -d %s' "${_VOLUME}"
	printf '%s: %s\n' "${FUNCNAME[0]}" "${_UNMOUNTCMD}"
	$_UNMOUNTCMD
	_ERRNO=$?
	if [ $_ERRNO -ne 0 ]; then
		printf >&2 '%s: Unmount failed: %s (%s)\n' "${FUNCNAME[0]}" "${_UNMOUNTCMD}" "${_ERRNO}"
		return 1
	fi
}
# veracryptunmount <_PROJECT|_VOLUME|>
function veracryptunmount () {
	local _PROJECT _VOLUME
	if [ -z "${1}" ]; then
		veracryptunmountall
		return $?
	fi
	_VOLUME=$(_getVolume "${_PROJECT}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: %s was not a volume or project\n' "${FUNCNAME[0]}" "${_PROJECT}"
		return 1
	fi
	veracryptunmountvolume "${_VOLUME}"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not mount %s\n' "${_VOLUME}"
		return 2
	fi
}
# veracryptgetwritablevoldir
# Find dir in comma-delimited ${VERACRYPT[VOLUMES]} having >${VERACRYPT[VOLSIZE]}MB available
function veracryptgetwritablevoldir () {
	local _VOLDIR _AVAIL
	for _VOLDIR in ${VERACRYPT[VOLUMES]//,/ }; do
		if [ ! -d "${_VOLDIR}" ]; then
			continue
		fi
		_AVAIL=$(_getDiskSpaceAvail "${_VOLDIR}")
		if [ $? -ne 0 ] || [ -z "${_AVAIL}" ]; then
			printf >&2 '%s: Failed to get available space for volume directory %s\n' "${FUNCNAME[0]}" "${_VOLDIR}"
			return 1
		elif [ $_AVAIL -lt ${VERACRYPT[VOLSIZE]} ]; then
			printf >&2 '%s: %dMB needed for volume but %s has %dMB available\n' "${FUNCNAME[0]}" "${VERACRYPT[VOLSIZE]}" "${_VOLDIR}" "${_AVAIL}"
			continue
		fi
		printf '%s\n' "${_VOLDIR}"
		return 0
	done
	return 1
}
# veracryptcreate <PROJECTNAME>
# Write _KEYFILE to ${VERACRYPT[KEYFILES]}
# Write _VOLUME to ${VERACRYPT[VOLUME]}
function veracryptcreate () {
	local _PROJECT="${1}" _VOLDIR
	if [ "${_PROJECT//[a-zA-Z0-9-_]}" = "${_PROJECT}" ]; then
		printf >&2 '%s: Need project name\n' "${FUNCNAME[0]}"
		return 1
	fi
	_VOLDIR="$(veracryptgetwritablevoldir)"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: No storage directory satisfied needs (%s)\n' "${FUNCNAME[0]}" "${VERACRYPT[VOLUMES]}"
		return 1
	elif [ ! -d "${_VOLDIR}" ]; then
		printf >&2 '%s: Writable directory "%s" not a directory\n' "${FUNCNAME[0]}" "${_VOLDIR}"
		return 2
	fi
	# _VOLUME/_KEYFILE
	local _VOLUME _KEYFILE
	printf -v _VOLUME '%s/%s.hc' "${_VOLDIR}" "${_PROJECT}"
	printf -v _KEYFILE '%s' $(veracryptkeyfile "${_VOLUME}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not obtain keyfile "%s" for volume "%s"\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
		return 3
	fi
	local _RET=0
	if [ -f "${_VOLUME}" ]; then
		printf >&2 '%s: Volume %s exists\n' "${FUNCNAME[0]}" "${_VOLUME}"
		_RET=1
	elif [ -f "${_KEYFILE}" ]; then
		printf >&2 '%s: Keyfile %s exists\n' "${FUNCNAME[0]}" "${_KEYFILE}"
		_RET=1
	fi
	if [ ${_RET} -ne 0 ]; then
		printf >&2 '%s: Volume or keyfile exist. Please run "veracryptrm %s" before proceeding\n' "${FUNCNAME[0]}" "${_PROJECT}"
		return 4
	fi
	printf '%s: _VOLUME=%s; _KEYFILE=%s\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
	# Generate _KEYFILE
	local _MKKEYFILE
	printf -v _MKKEYFILE 'veracrypt -t --non-interactive --create-keyfile %s' "${_KEYFILE}"
	printf '%s: %s\n' "${FUNCNAME[0]}" "${_MKKEYFILE}"
	${_MKKEYFILE}
	if [ "$?" != "0" ]; then
		printf >&2 '%s: Creating keyfile %s failed\n' "${FUNCNAME[0]}" "${_KEYFILE}"
		return 5
	fi
	printf -v _MKVOL 'veracrypt -t --non-interactive -c --volume-type=normal --encryption=aes --hash=sha-512 --filesystem=ext4 --pim=0 --size=%dM --keyfiles=%s --password= %s' "${VERACRYPT[VOLSIZE]}" "${_KEYFILE}" "${_VOLUME}"
	printf '%s: %s\n' "${FUNCNAME[0]}" "${_MKVOL}"
	${_MKVOL}
	if [ "$?" != "0" ]; then
		printf >&2 '\n%s: Error, rolling back\n' "${FUNCNAME[0]}"
		rm -v "${_KEYFILE}" "${_VOLUME}"
		return 6
	fi
	printf '%s: Created %s\n' "${FUNCNAME[0]}" "${_VOLUME}"
}
# veracryptrm <_PROJECT>
# Unmount associated _VOLUME and remove _VOLUME/_KEYFILE
function veracryptrm () {
	local _PROJECT="${1}" _VOLUME _KEYFILE
	_VOLUME=$(_getVolumeByProject "${_PROJECT}")
	if [ $? -ne 0 ]; then
		printf '%s: No volume associated with %s\n' "${FUNCNAME[0]}" "${_PROJECT}"
	fi
	printf -v _KEYFILE '%s' $(veracryptkeyfile "${_VOLUME}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not obtain keyfile "%s" for volume "%s"\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
		return 1
	fi
	veracryptunmount "${_VOLUME}"
	local _ERRNO=$?
	if [ $_ERRNO -ne 0 ]; then
		printf >&2 '%s: Could not unmount %s (%d)\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_ERRNO}"
		return 2
	fi
	# Volume is now unmounted
	local -a _FILES
	if [ -f "${_VOLUME}" ]; then
		_FILES+=("${_VOLUME}")
	fi
	if [ -f "${_KEYFILE}" ]; then
		_FILES+=("${_KEYFILE}")
	fi
	local _FILESSTR="${_FILES[@]}"
	while true; do
		read -p "rm ${_FILESSTR}? " yn
		case $yn in
			[Yy]* ) break;;
			[Nn]* ) return 3;;
			* ) echo "Please answer yes or no.";;
		esac
	done
	rm -v "${_FILES[@]}"
}
# _getVolumeByProject <_PROJECT>
# Look in each VERACRYPT[VOLUMES] directory for volume; return path of found _VOLUME
function _getVolumeByProject () {
	local _PROJECT="${1}" _VOLUME
	for _VOLDIR in ${VERACRYPT[VOLUMES]//,/ }; do
		printf -v _VOLUME '%s/%s.hc' "${_VOLDIR}" "${_PROJECT}"
		if [ -f "${_VOLUME}" ]; then
			break
		fi
		return 1
	done
	printf '%s\n' "${_VOLUME}"
}
# _getDiskSpaceAvail
# Find disk space available
function _getDiskSpaceAvail () {
	local _DIR="${1}" _AVAIL
	printf -v _AVAIL '%s' $(df -BM --output=avail "${_DIR}" | tail -n +2)
	if [ -z "${_AVAIL}" ]; then
		printf >&2 '%s: Could not get size available for %s\n' "${FUNCNAME[0]}" "${_DIR}"
		return 1
	fi
	printf '%d\n' "${_AVAIL%M}"
}
# _getDiskSpaceUsed <_DIR>
# Find disk space used
function _getDiskSpaceUsed () {
	local _DIR="${1}" _USED
	printf -v _USED '%s' $(df -BM --output=used "${_DIR}" | tail -n +2)
	if [ -z "${_USED}" ]; then
		printf >&2 '%s: Could not get size available for %s\n' "${FUNCNAME[0]}" "${_DIR}"
		return 1
	fi
	printf '%d\n' "${_USED%M}"
}
# veracryptrename <_PROJECT> <_NEWNAME>
# Rename volume
function veracryptrename () {
	local _PROJECT="${1}" _NEWNAME="${2}" _VOLUME _KEYFILE
	_VOLUME=$(_getVolumeByProject "${_PROJECT}")
	if [ $? -ne 0 ]; then
		printf '%s: No volume associated with %s\n' "${FUNCNAME[0]}" "${_PROJECT}"
	fi
	printf -v _KEYFILE '%s' "$(veracryptkeyfile ${_VOLUME})"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not obtain keyfile "%s" for volume "%s"\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
		return 1
	fi
	veracryptunmount "${_VOLUME}"
	local _ERRNO=$?
	if [ $_ERRNO -ne 0 ]; then
		printf >&2 '%s: Could not unmount %s (%d)\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_ERRNO}"
		return 2
	fi
	# Until here same as veracryptrm
	if [ "${_NEWNAME//[a-zA-Z0-9-_]}" = "${_NEWNAME}" ]; then
		printf >&2 '%s: Need new project name\n' "${FUNCNAME[0]}"
		return 3
	fi
	_NEWNAME_VOLUME="${_VOLUME%/*}/${_NEWNAME}.hc"
	_NEWNAME_KEYFILE=$(veracryptkeyfile "${_NEWNAME_VOLUME}")
	mv -v "${_VOLUME}" "${_NEWNAME_VOLUME}"
	mv -v "${_KEYFILE}" "${_NEWNAME_KEYFILE}"
}
# veracryptshrink <_PROJECT>
# 1. Figure out size of all files in volume associated with _PROJECT
# 2. Create new container matching size
# 3. Remove vol/keyfile of original _PROJECT and rename shrunken vol/keyfile to orig (optional)
function veracryptshrink () {
	local _PROJECT="${1}" _VOLUME _MOUNTPOINT _USED
	local _NEWVOL_PROJECT="${1}_shrink" _NEWVOL_VOLUME _NEWVOL_MOUNTPOINT
	_VOLUME=$(_getVolumeByProject "${_PROJECT}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: No volume associated with %s\n' "${FUNCNAME[0]}" "${_PROJECT}"
		return 1
	fi
	if ! veracryptismounted "${_VOLUME}"; then
		veracryptmount "${_VOLUME}"
		if ! veracryptismounted "${_VOLUME}"; then
			printf >&2 '%s: Could not mount %s\n' "${FUNCNAME[0]}" "${_VOLUME}"
			return 2
		fi
	fi
	_MOUNTPOINT=$(veracryptmountpoint "${_VOLUME}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not get mountpoint for %s\n' "${FUNCNAME[0]}" "${_VOLUME}"
		return 3
	fi
	_USED=$(_getDiskSpaceUsed "${_MOUNTPOINT}")
	if [ $? -ne 0 ] || [ -z "${_USED}" ]; then
		printf >&2 '%s: Could not get used space for %s\n' "${FUNCNAME[0]}" "${_MOUNTPOINT}"
		return 4
	fi
	#printf >&2 '%s: _VOLUME=%s _MOUNTPOINT=%s _USED=%s\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_MOUNTPOINT}" "${_USED}"
	# Sanity check
	if [ "${_USED}" -gt "${VERACRYPT[VOLSIZE]}" ]; then
		printf >&2 '%s: Used size greater than VERACRYPT[VOLSIZE]: _USED=%s; VERACRYPT[VOLSIZE]=%d\n' "${FUNCNAME[0]}" "${_USED}" "${VERACRYPT[VOLSIZE]}"
		return 5
	fi
	# Create volume the size of used space
	VERACRYPT[VOLSIZE]="$((${_USED}+100))"
	veracryptcreate "${_NEWVOL_PROJECT}"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: veracryptcreate failed\n' "${FUNCNAME[0]}"
		return 6
	fi
	local _SIZE _NEWVOL_SIZE
	veracryptmount "${_NEWVOL_PROJECT}"
	_NEWVOL_VOLUME=$(_getVolumeByProject "${_NEWVOL_PROJECT}")
	_NEWVOL_MOUNTPOINT=$(veracryptmountpoint "${_NEWVOL_VOLUME}")
	_SIZE=$(stat -c '%s' "${_VOLUME}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: stat fail\n' "${FUNCNAME[0]}" "${_VOLUME}"
		# Rollback
		veracryptrm "${_NEWVOL_PROJECT}"
		return 7
	fi
	_NEWVOL_SIZE=$(stat -c '%s' "${_NEWVOL_VOLUME}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: stat _NEWVOL_VOLUME %s fail\n' "${FUNCNAME[0]}" "${_NEWVOL_VOLUME}"
		veracryptrm "${_NEWVOL_PROJECT}"
		return 8
	fi
	if ! veracryptismounted "${_NEWVOL_VOLUME}"; then
		printf >&2 '%s: %s not mounted\n' "${FUNCNAME[0]}" "${_NEWVOL_VOLUME}"
		veracryptrm "${_NEWVOL_PROJECT}"
		return 9
	fi
	# TODO: rsync is dependency
	rsync -azl "${_MOUNTPOINT}" "${_NEWVOL_MOUNTPOINT}"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: rsync fail\n' "${FUNCNAME[0]}"
		veracryptrm "${_NEWVOL_PROJECT}"
		return 10
	fi
	# TODO: diff is dependency
	diff --no-dereference -r "${_MOUNTPOINT}" "${_NEWVOL_MOUNTPOINT}"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: diff fail\n' "${FUNCNAME[0]}"
		veracryptrm "${_NEWVOL_PROJECT}"
		return 11
	fi
	printf '%s: %s=%dMB %s=%dMB (diff=%dMB)\n' "${FUNCNAME[0]}" "${_VOLUME}" "$((${_SIZE}/1024/1024))" "${_NEWVOL_VOLUME}" "$((${_NEWVOL_SIZE}/1024/1024))" $(((${_SIZE}-${_NEWVOL_SIZE})/1024/1024))
	local _PROMPT
	printf -v _PROMPT 'Remove %s project and rename %s to %s?' "${_PROJECT}" "${_NEWVOL_PROJECT}" "${_PROJECT}"
	while true; do
		read -p "${_PROMPT} " yn
		case $yn in
			[Yy]* ) break;;
			[Nn]* ) return 3;;
			* ) echo "Please answer yes or no.";;
		esac
	done
	veracryptrm "${_PROJECT}"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: veracryptrm fail\n' "${FUNCNAME[0]}"
		return 12
	fi
	veracryptrename "${_NEWVOL_PROJECT}" "${_PROJECT}"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: veracryptrename fail\n' "${FUNCNAME[0]}"
		return 13
	fi
	veracryptmount "${_PROJECT}"
}
# veracryptls
# Get infor about projects
function veracryptls () {
	local _PROJECT _VOLUME _KEYFILE _MOUNTPOINT _MOUNTED _SIZE _USED _RET
	while read -r _PROJECT; do
		_VOLUME=$(_getVolumeByProject "${_PROJECT}")
		_KEYFILE=$(veracryptkeyfile "${_VOLUME}")
		_MOUNTPOINT=$(veracryptmountpoint "${_VOLUME}")
		veracryptismounted "${_VOLUME}" && _MOUNTED=true || _MOUNTED=false
		_SIZE=$(($(stat -c '%s' "${_VOLUME}")/1024/1024))
		# Check used space when volume is mounted
		_USED=0
		if $_MOUNTED; then
			_USED=$(_getDiskSpaceUsed "${_MOUNTPOINT}")
		fi
		# TODO: jq is dependency
		_RET+=$(jq -r -n \
			--arg _PROJECT "${_PROJECT}" \
			--arg _VOLUME "${_VOLUME}" \
			--arg _KEYFILE "${_KEYFILE}" \
			--arg _MOUNTPOINT "${_MOUNTPOINT}" \
			--argjson _MOUNTED ${_MOUNTED} \
			--argjson _SIZE "${_SIZE}" \
			--argjson _USED "${_USED}" \
			'
			{
				project: $_PROJECT,
				volume: $_VOLUME,
				keyfile: $_KEYFILE,
				mountpoint: $_MOUNTPOINT,
				mounted: $_MOUNTED,
				size: $_SIZE,
				used: $_USED
			}
			'
		)
	done < <(veracryptprojects)
	jq -s <<<"${_RET}"
}
