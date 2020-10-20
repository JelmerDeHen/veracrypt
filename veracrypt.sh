#!/bin/sh
declare -A VERACRYPT=(
	["VOLUMES"]="/data3/vera,/data4/vera"
	["KEYFILES"]="/.../secrets/veracrypt"
	["MOUNTPOINT"]="/mnt"
	["VOLSIZE"]="50"
)
# veracryptismounted <VOLUME>
function veracryptismounted () {
	local _FILE="${1}"
	if ! [ -f "${_FILE}" ]; then
		printf >&2 '%s: %s is not a file\n' "${FUNCNAME[0]}" "${_FILE}"
		return 1
	fi
	local _INDEX _CRYPTFILE _MAPPERDEV _MOUNTPOINT
	veracrypt &>/dev/null -t -l "${_FILE}"
	return $?
}
# _VOLUME to _KEYFILE: ${VERACRYPT[KEYFILES]}/${_VOLUME%.hc}.key
function veracryptkeyfile () {
	local _VOLUME="${1}" _KEYFILE
	if [ -z "${_VOLUME}" ]; then
		printf >&2 '%s: %s <VOLUME>\n' "${FUNCNAME[0]}" "${FUNCNAME[0]}"
		return 1
	fi
	# /path/to/VOLUME.hc -> NAME
	local _KEYFILE="${_VOLUME##*/}"
	printf -v _KEYFILE '%s/%s' "${VERACRYPT[KEYFILES]}" "${_KEYFILE%.hc}.key"
	printf '%s\n' "${_KEYFILE}"
	return 0
}
# VOLUME to ${VERACRYPT[MOUNTPOINT]}/${_NAME}
function veracryptmountpoint () {
	local _VOLUME="${1}" _MOUNTPOINT
	if [ -z "${_VOLUME}" ]; then
		printf >&2 '%s: %s <VOLUME>\n' "${FUNCNAME[0]}" "${FUNCNAME[0]}"
		return 1
	fi
	local _MOUNTPOINT="${_VOLUME##*/}"
	printf -v _MOUNTPOINT '%s/%s' "${VERACRYPT[MOUNTPOINT]}" "${_MOUNTPOINT%.hc}"
	printf '%s\n' "${_MOUNTPOINT}"
	return 0
}
# veracryptvolumes
# List volumes in ${VERACRYPT[VOLUMES]}
function veracryptvolumes () {
	find ${VERACRYPT[VOLUMES]//,/ } -mindepth 1 -maxdepth 1 -type f -name '*.hc'
}
# veracryptmount
# Mounts each _VOLUME found in ${VERACRYPT[VOLUMES]}
function veracryptmount () {
	local _VOLUME _KEYFILE _MOUNTPOINT _MOUNTCMD
	set -- $(veracryptvolumes)
	for _VOLUME; do
		# Get _KEYFILE
		printf -v _KEYFILE '%s' $(veracryptkeyfile "${_VOLUME}")
		if [ $? -ne 0 ]; then
			printf >&2 '%s: Could not obtain keyfile "%s" for volume "%s"\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
			continue
		elif [ ! -f "${_KEYFILE}" ]; then
			printf >&2 '%s: Keyfile "%s" does not exist\n' "${FUNCNAME[0]}" "${_KEYFILE}"
			continue
		fi
		# Get _MOUNTPOINT
		printf -v _MOUNTPOINT '%s' $(veracryptmountpoint "${_VOLUME}")
		if [ $? -ne 0 ]; then
			printf >&2 '%s: Could not obtain mountpoint "%s" for volume "%s"\n' "${FUNCNAME[0]}" "${_MOUNTPOINT}" "${_VOLUME}"
		fi
		# Create _MOUNTPOINT if it does not exist
		if [ ! -d "${_MOUNTPOINT}" ]; then
			mkdir -pv "${_MOUNTPOINT}"
			if [ $? != "0" ]; then
				printf >&2 '%s: Mountpoint directory does not exist %s, error creating it\n' "${FUNCNAME[0]}" "${_MOUNTPOINT}"
				continue
			fi
		fi
		# Got _KEYFILE _MOUNT
		if veracryptismounted "${_VOLUME}"; then
			printf >&2 '%s: %s already mounted\n' "${FUNCNAME[0]}" "${_VOLUME}"
			continue
		fi
		printf '%s: _VOLUME=%s; _KEYFILE=%s _MOUNTPOINT=%s\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}" "${_MOUNTPOINT}"
		printf -v _MOUNTCMD 'veracrypt -t --non-interactive --mount %s -k %s %s' "${_VOLUME}" "${_KEYFILE}" "${_MOUNTPOINT}"
		printf '%s: %s\n' "${FUNCNAME[0]}" "${_MOUNTCMD}"
		$_MOUNTCMD
	done
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
	printf -v _LSOFCMD 'lsof %s +f -- %s' "${_LSOFCMD}" "${_DEV}"
	#printf '%s\n' "${_LSOFCMD}"
	$_LSOFCMD
	return $?
}
# veracryptunmount
# Unounts each _VOLUME found in ${VERACRYPT[VOLUMES]}
function veracryptunmount () {
	set -- $(veracryptvolumes)
	local _INDEX _VOLFILE _MAPPERDEV _MOUNTOINT _ERRNO
	for _VOLUME; do
		if ! veracryptismounted "${_VOLUME}"; then
			continue
		fi
		read -r _INDEX _VOLFILE _MAPPERDEV _MOUNTPOINT < <(veracrypt -t -l "${_VOLUME}")
		if veracryptbusy "${_MAPPERDEV}"; then
			printf >&2 '%s: %s is busy\n' "${FUNCNAME[0]}" "${_VOLUME}"
			continue
		fi
		printf >&2 '%s: _INDEX=%s; _VOLFILE=%s; _MAPPERDEV=%s; _MOUNTPOINT=%s\n' "${FUNCNAME[0]}" "${_INDEX}" "${_VOLFILE}" "${_MAPPERDEV}" "${_MOUNTPOINT}"
		printf -v _UNMOUNTCMD 'veracrypt -t -d %s' "${_VOLUME}"
		printf '%s: %s\n' "${FUNCNAME[0]}" "${_UNMOUNTCMD}"
		$_UNMOUNTCMD
		_ERRNO=$?
		if [ $_ERRNO -ne 0 ]; then
			printf >&2 '%s: Unmount fail: %s (%s)\n' "${FUNCNAME[0]}" "${_UNMOUNTCMD}" "${_ERRNO}"
		fi
	done
}
# veracryptvolume
# Get all _VOLUME files
function veracryptvolume () {
	find ${VERACRYPT[VOLUMES]//,/ } -mindepth 1 -maxdepth 1 -type f -name '*.hc'
}
# veracryptgetwritablevoldir
# Find dir in comma-delimited ${VERACRYPT[VOLUMES]} having >${VERACRYPT[VOLSIZE]}GB available
function veracryptgetwritablevoldir () {
	for _VOLDIR in ${VERACRYPT[VOLUMES]//,/ }; do
		printf -v _AVAIL '%s' $(df -BG --output=avail "${_VOLDIR}" | tail -n +2)
		if [ -z "${_AVAIL}" ]; then
			printf >&2 '%s: Failed to get available space for volume directory %s\n' "${FUNCNAME[0]}" "${_VOLDIR}"
			return 1
		fi
		_AVAIL="${_AVAIL%G}"
		# Don't use dir when less than 100GB is available
		if [ $_AVAIL -lt ${VERACRYPT[VOLSIZE]} ]; then
			continue
		fi
		printf '%s\n' "${_VOLDIR}"
	done

}
# veracryptcreate <PROJECTNAME>
# Write _KEYFILE to ${VERACRYPT[KEYFILES]}
# Write _VOLUME to ${VERACRYPT[VOLUME]}
function veracryptcreate () {
	local _PROJECT="${1}"
	if [ "${_PROJECT//[a-zA-Z0-9-_]}" = "${_PROJECT}" ]; then
		printf >&2 '%s: Need project name\n' "${FUNCNAME[0]}"
		return 1
	fi
	# Get directory with at least 100G free space
	local _VOLDIR
	printf -v _VOLDIR $(veracryptgetwritablevoldir)
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Error enumerating writable directory\n' "${FUNCNAME[0]}"
		return 1
	elif [ ! -d "${_VOLDIR}" ]; then
		printf >&2 '%s: Writable directory "%s" not a directory\n' "${FUNCNAME[0]}" "${_VOLDIR}"
	fi
	# _VOLUME/_KEYFILE
	local _VOLUME _KEYFILE
	printf -v _VOLUME '%s/%s.hc' "${_VOLDIR}" "${_PROJECT}"
	printf -v _KEYFILE '%s' $(veracryptkeyfile "${_VOLUME}")
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not obtain keyfile "%s" for volume "%s"\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
		return 2
	fi
	if [ -f "${_CRYPTFILE}" ]; then
		printf >&2 '%s: Cryptfile %s exists\n' "${FUNCNAME[0]}" "${_CRYPTFILE}"
		return 3
	elif [ -f "${_KEYFILE}" ]; then
		printf >&2 '%s: Keyfile %s exists\n' "${FUNCNAME[0]}" "${_KEYFILE}"
		return 3
	fi
	printf '%s: _VOLUME=%s; _KEYFILE=%s\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
	# Generate _KEYFILE
	dd status=none if=/dev/random of=/dev/stdout bs=1 count=10000 2>/dev/null | head -c64 > "${_KEYFILE}"
	if [ "$?" != "0" ]; then
		printf >&2 '%s: Creating keyfile %s failed\n' "${FUNCNAME[0]}" "${_KEYFILE}"
		return 4
	fi
	printf -v _MKVOL 'veracrypt -t -c --volume-type=normal --encryption=aes --hash=sha-512 --filesystem=ext4 --pim=0 --size=%dG -k %s -p "" %s' "${VERACRYPT[VOLSIZE]}" "${_KEYFILE}" "${_VOLUME}"
	printf '%s\n' "${_MKVOL}"
	# The stdin will satisfy "Please type at least 320 randomly chosen characters and then press Enter:"
	dd status=none if=/dev/random of=/dev/stdout bs=1 count=10000 | grep -oa '[0-9a-zA-Z]' | tr -d '\n' | head -c320 | cat - <(printf '\n') | \
		$_MKVOL
	if [ "$?" != "0" ]; then
		printf '\n%s: Error, rolling back\n' "${FUNCNAME[0]}"
		rm -v "${_KEYFILE}" "${_VOLUME}"
		return 5
	fi
	printf '%s: Created %s\n' "${FUNCNAME[0]}" "${_VOLUME}"
}
