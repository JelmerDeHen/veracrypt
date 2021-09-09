#!/bin/sh
declare -A VERACRYPT=(
	["VOLUMES"]="/data/vera,/data3/vera,/data4/vera"
	["KEYFILES"]="/.../secrets/veracrypt"
	["MOUNTPOINT"]="/mnt"
	["VOLSIZE"]="50"
)
# veracryptismounted <VOLUME>
function veracryptismounted () {
	local _VOLUME="${1}"
	if ! [ -f "${_VOLUME}" ]; then
		printf >&2 '%s: %s is not a file\n' "${FUNCNAME[0]}" "${_VOLUME}"
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
# VOLUME to ${VERACRYPT[MOUNTPOINT]}/${_NAME}
function veracryptmountpoint () {
	local _VOLUME="${1}"
	if [ -z "${_VOLUME}" ]; then
		printf >&2 '%s: %s <VOLUME>\n' "${FUNCNAME[0]}" "${FUNCNAME[0]}"
		return 1
	fi
	local _MOUNTPOINT="${_VOLUME##*/}"
	printf -v _MOUNTPOINT '%s/%s' "${VERACRYPT[MOUNTPOINT]}" "${_MOUNTPOINT%.hc}"
	printf '%s\n' "${_MOUNTPOINT}"
}
# veracryptvolumes
# List volumes in ${VERACRYPT[VOLUMES]}
function veracryptvolumes () {
	find ${VERACRYPT[VOLUMES]//,/ } -mindepth 1 -maxdepth 1 -type f -name '*.hc' 2>/dev/null
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
			if [ $? -ne 0 ]; then
				printf >&2 '%s: Mountpoint directory does not exist %s, error creating it\n' "${FUNCNAME[0]}" "${_MOUNTPOINT}"
				continue
			fi
		fi
		# Got _VOLUME _KEYFILE _MOUNTPOINT
		if veracryptismounted "${_VOLUME}"; then
			#printf >&2 '%s: %s already mounted\n' "${FUNCNAME[0]}" "${_VOLUME}"
			continue
		fi
		printf '%s: _VOLUME=%s; _KEYFILE=%s _MOUNTPOINT=%s\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}" "${_MOUNTPOINT}"
		printf -v _MOUNTCMD 'veracrypt -t --non-interactive --mount %s -k %s %s' "${_VOLUME}" "${_KEYFILE}" "${_MOUNTPOINT}"
		#printf '%s: %s\n' "${FUNCNAME[0]}" "${_MOUNTCMD}"
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
	$_LSOFCMD
	return $?
}
# veracryptunmount
# Unounts each _VOLUME found in ${VERACRYPT[VOLUMES]}
function veracryptunmount () {
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
# veracryptgetwritablevoldir
# Find dir in comma-delimited ${VERACRYPT[VOLUMES]} having >${VERACRYPT[VOLSIZE]}GB available
function veracryptgetwritablevoldir () {
	local _VOLDIR _AVAIL
	for _VOLDIR in ${VERACRYPT[VOLUMES]//,/ }; do
		if [ ! -d "${_VOLDIR}" ]; then
			continue
		fi
		printf -v _AVAIL '%s' $(df -BG --output=avail "${_VOLDIR}" | tail -n +2)
		if [ -z "${_AVAIL}" ]; then
			printf >&2 '%s: Failed to get available space for volume directory %s\n' "${FUNCNAME[0]}" "${_VOLDIR}"
			return 1
		fi
		_AVAIL="${_AVAIL%G}"
		if [ $_AVAIL -lt ${VERACRYPT[VOLSIZE]} ]; then
			printf >&2 '%s: %dGB needed for volume but %s has %dGB left\n' "${FUNCNAME[0]}" "${VERACRYPT[VOLSIZE]}" "${_VOLDIR}" "${_AVAIL}"
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
	printf -v _KEYFILE '%s' "$(veracryptkeyfile ${_VOLUME})"
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
	printf -v _MKVOL 'veracrypt -t --non-interactive -c --volume-type=normal --encryption=aes --hash=sha-512 --filesystem=ext4 --pim=0 --size=%dG --keyfiles=%s --password= %s' "${VERACRYPT[VOLSIZE]}" "${_KEYFILE}" "${_VOLUME}"
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
	local _PROJECT="${1}"
	local _VOLDIR
	printf -v _VOLDIR "$(veracryptgetwritablevoldir)"
	# _VOLUME/_KEYFILE
	local _VOLUME _KEYFILE
	printf -v _VOLUME '%s/%s.hc' "${_VOLDIR}" "${_PROJECT}"
	printf -v _KEYFILE '%s' "$(veracryptkeyfile ${_VOLUME})"
	if [ $? -ne 0 ]; then
		printf >&2 '%s: Could not obtain keyfile "%s" for volume "%s"\n' "${FUNCNAME[0]}" "${_VOLUME}" "${_KEYFILE}"
		return 1
	fi
	veracryptunmountvolume "${_VOLUME}"
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
