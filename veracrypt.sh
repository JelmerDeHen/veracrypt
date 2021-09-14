#!/usr/bin/env bash
# LICENSE
#
#######################################
#
# Veracrypt container manager
#
#######################################
#
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

  # Store current PWD
  local pwd="${PWD}"

  flags=("${src}")
  if ! cd "${src%/*}"; then
    return 2
  fi

  local ret="${PWD}"

  flags=("${pwd}")
  if ! cd "${flags[@]}"; then
    return 3
  fi

  printf '%s\n' "${ret}"
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
# Check if volume is mounted
# Globals:
#   None
# Arguments:
#   volume
# Outputs:
#   Returns zero if mounted, otherwise returns 1
#######################################
function volume_mounted () {
  local volume="${1}"

  if [ ! -f "${volume}" ]; then
    printf >&2 '%s: %s is not a file (from %s)\n' "${FUNCNAME[0]}" "${volume}" "${FUNCNAME[1]}"
    return 1
  fi

  local flags=( -t -l "${volume}" )
  veracrypt &>/dev/null "${flags[@]}"
  # keep error code
}

#######################################
# Print keyfile associated with volume
# Globals:
#   VERACRYPT[KEYFILES]
# Arguments:
#   volume
# Outputs:
#   Path of associated keyfile
#######################################
function volume_to_keyfile () {
  local volume="${1}" keyfile

  if [ -z "${volume}" ]; then
    printf >&2 '%s: Need volume\n' "${FUNCNAME[0]}"
    return 1
  fi

  keyfile="${volume##*/}"
  keyfile="${VERACRYPT[KEYFILES]}/${keyfile%.hc}.key"

  if [ ! -f "${keyfile}" ]; then
    printf >&2 '%s: Keyfile "%s" does not exist\n' "${FUNCNAME[0]}" "${keyfile}"
    return 2
  fi

  if [ ! -s "${keyfile}" ]; then
    printf >&2 '%s: Keyfile %s was empty (perms?)\n' "${FUNCNAME[0]}" "${keyfile}"
    return 3
  fi

  printf '%s\n' "${keyfile}"
}

#######################################
# Print path to mount volume
# Globals:
#   VERACRYPT[MOUNTPOINT]
# Arguments:
#   volume
# Outputs:
#   Location to mount volume
#######################################
function volume_to_mountpoint () {
  local volume="${1}"
  local mountpoint="${volume##*/}"
  printf '%s/%s/\n' "${VERACRYPT[MOUNTPOINT]}" "${mountpoint%.hc}"
}

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
# Mounts volume
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Status, non-zero error code on failure
#######################################
function mount_volume () {
  if [[ ! -x "$(command -v veracrypt)" ]]; then
    printf >&2 '%s: veracrypt: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local volume="${1}" keyfile mountpoint

  if volume_mounted "${volume}"; then
    return 0
  fi

  if ! keyfile="$(volume_to_keyfile "${volume}")"; then
    printf >&2 '%s: Could not obtain keyfile for volume "%s"\n' "${FUNCNAME[0]}" "${volume}"
    return 2
  fi

  if ! mountpoint="$(volume_to_mountpoint "${volume}")"; then
    printf >&2 '%s: Could not get mountpoint for %s\n' "${FUNCNAME[0]}" "${volume}"
    return 3
  fi
  if [ ! -d "${mountpoint}" ]; then
    if ! mkdir -pv "${mountpoint}"; then
      printf >&2 '%s: Mountpoint directory does not exist %s, error creating it\n' "${FUNCNAME[0]}" "${mountpoint}"
      return 4
    fi
  fi

  local -a flags
  flags=(-t --non-interactive --mount "${volume}")

  # The secrets are stored by project name
  # Figure out project name
  local project password
  project="${volume##*/}"
  project="${project%.hc}"

  # Access the secret. When gcloud has no secret (old projects) then no password is tried and only keyfile is used
  if password="$(gcloud_access_secret "${project}")"; then
    printf >&2 '%s: Received secret from gcloud\n' "${FUNCNAME[0]}"
    flags+=( -p "${password}" )
  fi

  flags+=(-k "${keyfile}" "${mountpoint}")
  if ! veracrypt "${flags[@]}"; then
    printf >&2 '%s: Mount error\n' "${FUNCNAME[0]}"
    return 5
  fi
}

#######################################
# Mount all volumes returned by list_volumes
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
#######################################
function mount_all () {
  local volume

  while read -r volume; do
    if mount_volume "${volume}"; then
      printf >&2 '%s: mount %s success\n' "${FUNCNAME[0]}" "${volume}"
    else
      printf >&2 '%s: mount %s failed\n' "${FUNCNAME[0]}" "${volume}"
    fi
  done < <(list_volumes)
}

#######################################
# Finds volume associated with first argument. The argument may be a project name or absolute volume path
# Globals:
#   None
# Arguments:
#   project or volume
# Outputs:
#   Non-zero error code on failure
#######################################
function lookup_volume () {
  local project="${1}" volume

  # Absolute
  if [ "${project:0:1}" = "/" ]; then
    printf '%s\n' "${project}"
    # Check for existence?
    return 0
  fi

  # project name
  if ! volume="$(project_to_volume "${project}")"; then
    #printf >&2 '%s: No volume associated with %s\n' "${FUNCNAME[0]}" "${project}"
    return 1
  fi
  printf '%s\n' "${volume}"
}

#######################################
# Check if it is safe to unmount filesystem by finding open files associated with mountpoint
# Globals:
#   None
# Arguments:
#   Mountpoint (path)
# Outputs:
#   Lsof output, non-zero error code on failure
#######################################
function is_mountpoint_busy () {
  if [[ ! -x "$(command -v lsof)" ]]; then
    printf >&2 '%s: lsof: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local mountpoint="${1}"
  if [[ ! -d "${mountpoint}" ]]; then
    printf >&2 '%s: %s is not a mountpoint\n' "${FUNCNAME[0]}" "${mountpoint}"
    return 2
  fi

  local -a flags
  # Exclude FUSE
  while read -r; do
    flags+=( -e "${REPLY}" )
  done < <( find /run -name gvfs 2>/dev/null )

  flags+=( +f -- "${mountpoint}" )

  # lsof returns 1 when no open files were found. Err on zero
  if lsof "${flags[@]}"; then
    printf >&2 '%s: Open files associated with %s\n' "${FUNCNAME[0]}" "${mountpoint}"
    return 3
  fi

}

#######################################
# Unounts each volume found in ${VERACRYPT[VOLUMES]}
# Globals:
#   VERACRYPT[VOLUMES]
# Arguments:
#   None
# Outputs:
#   Status
#######################################
function unmount_all () {
  local volume
  while read -r volume; do
    if ! volume_mounted "${volume}"; then
      continue
    fi

    if ! unmount_volume "${volume}"; then
      printf >&2 '%s: Unmounting %s failed\n' "${FUNCNAME[0]}" "${volume}"
    else
      printf '%s: %s has been unmounted\n' "${FUNCNAME[0]}" "${volume}"
    fi
  done < <(list_volumes)
}

#######################################
# Unmount volume described by volume path
# Globals:
#   None
# Arguments:
#   volume
# Outputs:
#   Status or non-zero when error
#######################################
function unmount_volume () {
  if [[ ! -x "$(command -v veracrypt)" ]]; then
    printf >&2 '%s: veracrypt: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local volume="${1}"
  if [[ ! -f "${volume}" ]]; then
    printf >&2 '%s: %s is not a file\n' "${FUNCNAME[0]}" "${volume}"
    return 2
  fi

  if ! volume_mounted "${volume}"; then
    return 0
  fi

  # Get /dev/mapper/veracryptX by using "veracrypt -t -l" (-l = list)
  local out
  local -a flags
  flags=( -t -l "${volume}" )
  if ! out="$(veracrypt "${flags[@]}")"; then
    printf >&2 '%s: Could not get volume info using veracrypt\n' "${FUNCNAME[0]}"
    return 3
  fi
  local -a volinfo
  read -ra volinfo <<<"${out}" 

  # This can be fixed using: veracrypt -d /path/to/container.hc
  if [[ "${volinfo[3]}" == "-" ]]; then
    printf >&2 '%s: The volume %s has "-" as mountpoint: "veracrypt -t -l %s"\n' "${FUNCNAME[0]}" "${volume}" "${volume}"
    return 4
  fi

  # -l lists volume path, virtual device, and mount point
  # N: {volume.hc} /dev/mapper/veracryptN {mountpoint}
  if ! is_mountpoint_busy "${volinfo[3]}"; then
    printf >&2 '%s: %s is busy\n' "${FUNCNAME[0]}" "${volume}"
    return 5
  fi

  flags=( -t -d "${volume}" )
  if ! veracrypt "${flags[@]}"; then
    printf >&2 '%s: failed to unmount %s\n' "${FUNCNAME[0]}" "${volume}"
    return 6
  fi
}

#######################################
# Check each VERACRYPT[VOLUMES] until VERACRYPT[VOLSIZE] bytes is available. Print path
# Globals:
#   VERACRYPT[VOLSIZE]
#   VERACRYPT[VOLUMES]
# Arguments:
#   None
# Outputs:
#   Path to write volume file or non-zero error code
#######################################
function get_writable_voldir () {
  local voldir
  local -i avail
  local -a voldirs

  IFS=, read -ra voldirs <<<"${VERACRYPT[VOLUMES]}"
  for voldir in "${voldirs[@]}"; do
    if [ ! -d "${voldir}" ]; then
      continue
    fi

    if ! avail="$(disk_space_avail_df "${voldir}")"; then
      printf >&2 '%s: Failed to get available space for volume directory %s\n' "${FUNCNAME[0]}" "${voldir}"
      return 1
    fi

    if [[ "${avail}" < "${VERACRYPT[VOLSIZE]}" ]]; then
      printf >&2 '%s: %d bytes needed for volume but %s has %d bytes available\n' "${FUNCNAME[0]}" "${VERACRYPT[VOLSIZE]}" "${voldir}" "${avail}"
      continue
    fi

    printf '%s\n' "${voldir}"
    return 0
  done
  return 1
}

#######################################
# Create volume for new project. Write _KEYFILE to ${VERACRYPT[KEYFILES]}; Write volume to ${VERACRYPT[VOLUME]}
# Globals:
#   VERACRYPT[VOLSIZE]
#   VERACRYPT[VOLUMES]
# Arguments:
#   project
# Outputs:
#   Status info or non-zero error code on failure
#######################################
function _create () {
  if [[ ! -x "$(command -v veracrypt)" ]]; then
    printf >&2 '%s: veracrypt: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local project="${1}" voldir
  local -a flags

  if (( "${VERACRYPT[VOLSIZE]}" < 1048576 * 5 )); then
    printf >&2 '%s: Minimum volume size not satisfied\n' "${FUNCNAME[0]}"
    return 3
  fi

  if ! voldir="$(get_writable_voldir)"; then
    printf >&2 '%s: No storage directory satisfied needs (%s)\n' "${FUNCNAME[0]}" "${VERACRYPT[VOLUMES]}"
    return 4
  fi

  local volume keyfile
  printf -v volume '%s/%s.hc' "${voldir}" "${project}"
  printf -v keyfile '%s/%s.key' "${VERACRYPT[KEYFILES]}" "${project}"

  if [ -f "${volume}" ]; then
    printf >&2 '%s: Volume or %s exist. Please run "_rm %s" before proceeding\n' "${FUNCNAME[0]}" "${volume}" "${project}"
    return 5
  fi

  if [ -f "${keyfile}" ]; then
    printf >&2 '%s: Keyfile exist. Please run "_rm %s" before proceeding\n' "${FUNCNAME[0]}" "${project}"
    return 6
  fi

  # Create keyfile
  flags=(-t --non-interactive --create-keyfile "${keyfile}")
  if ! veracrypt "${flags[@]}"; then
    printf >&2 '\n%s: Creating keyfile %s failed\n' "${FUNCNAME[0]}" "${keyfile}"
    return 7
  fi

  # Use secret at gcloud as pw
  local secret
  if ! secret="$(generate_secret)"; then
    printf >&2 '%s: Secret generation failed\n' "${FUNCNAME[0]}"
    return 1
  fi

  if ! gcloud_create_secret "${project}" "${secret}"; then
    printf >&2 '%s: Error storing gcloud secret\n' "${FUNCNAME[0]}"
    return 8
  fi

  # Create volume
  flags=( -t --non-interactive -c --volume-type=normal --encryption=aes --hash=sha-512 --filesystem=ext4 --pim=0 --size="${VERACRYPT[VOLSIZE]}" -p "${secret}" --keyfiles="${keyfile}" "${volume}" )
  if ! veracrypt "${flags[@]}"; then
    printf >&2 '\n%s: Error, rolling back\n' "${FUNCNAME[0]}"
    rm -v "${keyfile}" "${volume}"
    return 9
  fi
}

#######################################
# Unmount & remove the volume & keyfile associated with project
# Globals:
#   None
# Arguments:
#   project
# Outputs:
#   None
#######################################
function _rm () {
  local project="${1}" volume keyfile
  local -a flags

  if volume="$(project_to_volume "${project}")"; then
    flags=( "${volume}" )
    if ! unmount_volume "${volume}"; then
      printf >&2 '%s: Could not unmount %s\n' "${FUNCNAME[0]}" "${volume}"
      return 1
    fi
  fi

  printf -v keyfile '%s/%s.key' "${VERACRYPT[KEYFILES]}" "${project}"
  if [[ -f "${keyfile}" ]]; then
    flags+=( "${keyfile}" )
  fi

  if [[ "${#flags[@]}" == 0 ]]; then
    printf '%s: Volume/keyfile not found for project %s\n' "${FUNCNAME[0]}" "${project}"
    return 0
  fi

  flags+=( -v )
  if ! rm "${flags[@]}"; then
    printf >&2 '%s: Error from rm\n' "${FUNCNAME[0]}"
  fi

  if ! gcloud_rm_secret "${project}"; then
    printf >&2 '%s: Error deleting secret at gcloud\n' "${FUNCNAME[0]}"
  fi

}

#######################################
# Look in each VERACRYPT[VOLUMES] directory for volume; return path of found volume
# Globals:
#   VERACRYPT[VOLUMES]
# Arguments:
#   project
# Outputs:
#   Path of found volume
#######################################
function project_to_volume () {
  local project="${1}" voldir volume
  local -a voldirs

  IFS=, read -ra voldirs <<<"${VERACRYPT[VOLUMES]}"

  for voldir in "${voldirs[@]}"; do
    printf -v volume '%s/%s.hc' "${voldir}" "${project}"
    if [ -f "${volume}" ]; then
      printf '%s\n' "${volume}"
      return 0
    fi
  done
  return 1
}

#######################################
# Report bytes available of partition where path is stored on (using stat)
# TODO(JdH): Reported size available not matching output of "df -B 1 <path>"
#   Using disk_space_avail_df for now
# Globals:
#   None
# Arguments:
#   path
# Outputs:
#   File size available in bytes
#######################################
function disk_space_avail_stat () {
  if [[ ! -x "$(command -v stat)" ]]; then
    printf >&2 '%s: stat: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local path="${1}" out
  local -a flags

  flags=( -fc "%s %b %f" "${path}" )
  if ! out="$(stat "${flags[@]}")"; then
    printf >&2 '%s: Failed to stat %s\n' "${FUNCNAME[0]}" "${path}"
    return 1
  fi

  local -i blocksize blocks freeblocks
  read -r blocksize blocks freeblocks <<<"${out}"
  #declare -p blocksize blocks freeblocks >&2
  printf '%d\n' "$((freeblocks*blocksize))"
}

#######################################
# Report bytes available of partition where path is stored on (using df)
# Globals:
#   None
# Arguments:
#   path
# Outputs:
#   File size available in bytes
#######################################
function disk_space_avail_df () {
  if [[ ! -x "$(command -v df)" ]]; then
    printf >&2 '%s: df: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local dir="${1}"
  if [ -z "${dir}" ]; then
    return 2
  fi

  local -a flags=( -B 1 --output=avail "${dir}" )
  local out
  if ! out="$(df "${flags[@]}")"; then
    printf >&2 '%s: Error: df -B 1 --output=avail %s\n' "${FUNCNAME[0]}" "${dir}"  
    return 3
  fi

  # out looks like:
  # "   Avail"
  # "69421337"
  local -a outarr
  mapfile -t -c 1 outarr <<<"${out}"
  # Verify 2 lines are returned and second line only contained numbers
  if [[ "${#outarr[@]}" != 2 ]] || [[ "${outarr[1]//[^0-9]/}" != "${outarr[1]}" ]]; then
    return 4
  fi

  printf '%d\n' "${outarr[1]}"
}

#######################################
# Report bytes used on partition where path is stored on
# Globals:
#   None
# Arguments:
#   path
# Outputs:
#   File size used in bytes
#######################################
function disk_space_used () {
  if [[ ! -x "$(command -v stat)" ]]; then
    printf >&2 '%s: stat: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local path="${1}" out
  local -a flags

  flags=( -fc "%s %b %f" "${path}" )
  if ! out="$(stat "${flags[@]}")"; then
    printf >&2 '%s: Failed to stat %s\n' "${FUNCNAME[0]}" "${path}"
    return 1
  fi

  local -i blocksize blocks freeblocks
  read -r blocksize blocks freeblocks <<<"${out}"

  printf '%d\n' "$(( (blocks-freeblocks) * blocksize ))"
}

#######################################
# Rename volume & keyfile associated with project to dest
# Globals:
#   VERACRYPT[KEYFILES]
# Arguments:
#   project
#   dest
# Outputs:
#   Non-zero error code on failure
#######################################
function _mv () {
  local project="${1}" dest="${2}" volume keyfile

  if ! volume="$(project_to_volume "${project}")"; then
    printf >&2 '%s: No volume associated with %s\n' "${FUNCNAME[0]}" "${project}"
    return 2
  fi

  if ! keyfile="$(volume_to_keyfile "${volume}")"; then
    printf >&2 '%s: Could not obtain keyfile for volume "%s"\n' "${FUNCNAME[0]}" "${volume}"
    return 3
  fi


  local dest_volume dest_keyfile
  dest_volume="${volume%/*}/${dest}.hc"
  dest_keyfile="${dest_volume##*/}"
  dest_keyfile="${VERACRYPT[KEYFILES]}/${dest_keyfile%.hc}.key"

  # Move the secret in gcloud
  # 1. Delete secret for $dest (happens using shrink)
  # 2. Extract current secret for $project
  # 3. Create new entry having same secret as $project on $dest
  # 4. Remove secret $project
  local secret
  if secret="$(gcloud_access_secret "${dest}" 2>/dev/null)"; then
    gcloud_rm_secret "${dest}"
  fi
  if secret="$(gcloud_access_secret "${project}")"; then
    gcloud_create_secret "${dest}" "${secret}"
    gcloud_rm_secret "${project}"
  fi

  if ! unmount_volume "${volume}"; then
    printf >&2 '%s: Could not unmount %s (%d)\n' "${FUNCNAME[0]}" "${volume}" "${_ERRNO}"
    return 4
  fi

  mv -v "${volume}" "${dest_volume}"
  mv -v "${keyfile}" "${dest_keyfile}"
}

#######################################
# 1. Figure out size of all files in volume associated with project
# 2. Create new volume matching size
# 3. Remove vol/keyfile of original project and rename shrunken vol/keyfile to orig (optional)
# Globals:
#   VERACRYPT[VOLSIZE]
# Arguments:
#   project
# Outputs:
#   Status, non-zero error code on failure
#######################################
function shrink () {
  if [[ ! -x "$(command -v diff)" ]]; then
    printf >&2 '%s: diff: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  if [[ ! -x "$(command -v rsync)" ]]; then
    printf >&2 '%s: rsync: command not found\n' "${FUNCNAME[0]}"
    return 2
  fi

  local project="${1}" volume

  if ! volume="$(project_to_volume "${project}")"; then
    printf >&2 '%s: No volume associated with %s\n' "${FUNCNAME[0]}" "${project}"
    return 3
  fi

  # Mount volume to discover disk size used
  if ! volume_mounted "${volume}"; then
    if ! mount_volume "${volume}"; then
      printf >&2 '%s: Could not mount %s\n' "${FUNCNAME[0]}" "${volume}"
      return 4
    fi
    if ! volume_mounted "${volume}"; then
      printf >&2 '%s: %s was not mounted\n' "${FUNCNAME[0]}" "${volume}"
      return 5
    fi
  fi

  local mountpoint
  if ! mountpoint="$(volume_to_mountpoint "${volume}")"; then
    printf >&2 '%s: Could not get mountpoint for %s\n' "${FUNCNAME[0]}" "${volume}"
    return 6
  fi

  local -i newvol_size
  if ! newvol_size="$(disk_space_used "${mountpoint}")"; then
    printf >&2 '%s: Could not get used space for %s\n' "${FUNCNAME[0]}" "${mountpoint}"
    return 7
  fi


  # Create volume size of used space
  if (( "${newvol_size}" < 1048576 * 10 )); then
    printf 'Setting volume size for new container to minimum size of 10MB (%d bytes were used)\n' "${newvol_size}"
    newvol_size=$((1048576*10))
  fi

  local newvol_project="${1}_shrink"

  # Overwrite global value used in _create
  VERACRYPT[VOLSIZE]="$(( newvol_size + 1048576 * 10 ))"

  if ! _create "${newvol_project}"; then
    printf >&2 '%s: _create failed\n' "${FUNCNAME[0]}"
    return 8
  fi

  local newvol_project newvol_volume

  local newvol_volume
  if ! newvol_volume="$(project_to_volume "${newvol_project}")"; then
    printf >&2 '%s: project_to_volume failed for "%s"\n' "${FUNCNAME[0]}" "${newvol_project}"
    _rm "${newvol_project}"
    return 9
  fi

  local newvol_mountpoint
  if ! newvol_mountpoint="$(volume_to_mountpoint "${newvol_volume}")"; then
    printf >&2 '%s: volume_to_mountpoint failed for "%s"\n' "${FUNCNAME[0]}" "${newvol_project}"
    _rm "${newvol_project}"
    return 10
  fi

  # Mounting freshly created volume to mirror content
  mount_volume "${newvol_volume}"

  if ! volume_mounted "${newvol_volume}"; then
    printf >&2 '%s: %s not mounted\n' "${FUNCNAME[0]}" "${newvol_volume}"
    _rm "${newvol_project}"
    return 9
  fi

  flags=( -azl "${mountpoint}" "${newvol_mountpoint}" )
  if ! rsync "${flags[@]}"; then
    printf >&2 '%s: rsync fail\n' "${FUNCNAME[0]}"
    _rm "${newvol_project}"
    return 10
  fi

  flags=( --no-dereference -r "${mountpoint}" "${newvol_mountpoint}" )
  if ! diff "${flags[@]}"; then
    printf >&2 '%s: diff fail\n' "${FUNCNAME[0]}"
    _rm "${newvol_project}"
    return 11
  fi

  if ! _rm "${project}"; then
    printf >&2 '%s: _rm fail\n' "${FUNCNAME[0]}"
    return 12
  fi

  # Rename {project}_shrink to {project}
  if ! _mv "${newvol_project}" "${project}"; then
    printf >&2 '%s: _mv fail\n' "${FUNCNAME[0]}"
    return 13
  fi

  printf '%s: Shrinking completed\n' "${FUNCNAME[0]}"
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

#######################################
# List information about projects
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   json-encoded project information
#######################################
function _list () {
  if [[ ! -x "$(command -v jq)" ]]; then
    printf >&2 '%s: jq: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  if [[ ! -x "$(command -v stat)" ]]; then
    printf >&2 '%s: stat: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local volume keyfile mountpoint mounted
  local project ret

  while read -r project; do
    if ! volume="$(project_to_volume "${project}")"; then
      return 2
    fi

    if ! keyfile="$(volume_to_keyfile "${volume}")"; then
      return 3
    fi

    if ! mountpoint="$(volume_to_mountpoint "${volume}")"; then
      return 4
    fi

    if volume_mounted "${volume}"; then
      mounted="true"
    else
      mounted="false"
    fi

    local -a flags
    flags=(-c "%s" "${volume}")
    local -i volsize
    if ! volsize="$(stat "${flags[@]}")"; then
      return 5
    fi

    local -i diskused=0
    if [[ "${mounted}" == "true" ]]; then
      if ! diskused="$(disk_space_used "${mountpoint}")"; then
        return 6
      fi
    fi

    # converts bytes to mb
    volsize=$((volsize/1024/1024))
    diskused=$((diskused/1024/1024))

    # Means df went over drive
    if (( diskused > volsize )); then
      continue
    fi

    flags=(-n -r)
    flags+=(--arg project "${project}")
    flags+=(--arg volume "${volume}")
    flags+=(--arg keyfile "${keyfile}")
    flags+=(--arg mountpoint "${mountpoint}")
    flags+=(--argjson mounted "${mounted}")
    flags+=(--argjson volsize "${volsize}")
    flags+=(--argjson diskused "${diskused}")
    flags+=("
    {
      project: \$project,
      volume: \$volume,
      keyfile: \$keyfile,
      mountpoint: \$mountpoint,
      mounted: \$mounted,
      volsize: \$volsize,
      diskused: \$diskused
    }
    ")
    if ! ret+="$(jq "${flags[@]}")"; then
      return 7
    fi
  done < <(list_projects)

  jq -s <<<"${ret}"
}

#######################################
# Read 1kb bytes from /dev/urandom and filter alphanumeric chars. Print first 32 chars found
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Random string
#######################################
function generate_secret () {
  local out
  local -a flags flagstr
  flags=( if=/dev/urandom bs=1k count=1 status=none )
  flagstr=( -cd "a-zA-Z0-9" )
  if ! out="$(dd "${flags[@]}" | tr "${flagstr[@]}")"; then
    return 1
  fi

  if (( "${#out}" < 32 )); then
      return 2
  fi

  printf '%s\n' "${out:0:32}"
}

#######################################
# Read 1kb bytes from /dev/urandom and filter alphanumeric chars. Print first 32 chars found
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   non-zero error code on failure
#######################################
function gcloud_create_secret () {
  if [[ ! -x "$(command -v gcloud)" ]]; then
    printf >&2 '%s: gcloud: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local secret_id="vera_${1}" secret="${2}"

  local -a flags
  flags=( secrets create "${secret_id}" --replication-policy="automatic" )
  if ! gcloud "${flags[@]}"; then
    printf >&2 '%s: Error creating secret_id %s\n' "${FUNCNAME[0]}" "${secret_id}"
    return 1
  fi

  flags=( secrets versions add "${secret_id}" --data-file=- )
  if ! gcloud "${flags[@]}" <<<"${secret}"; then
    printf >&2 '%s: Error adding secret %s\n' "${FUNCNAME[0]}" "${secret_id}"
    return 2
  fi
}

#######################################
# Access the secret vera_<project> from gcloud secrets
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   non-zero error code on failure
#######################################
function gcloud_access_secret () {
  if [[ ! -x "$(command -v gcloud)" ]]; then
    printf >&2 '%s: gcloud: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local secret_id="vera_${1}"
  local -a flags
  flags=( secrets versions access latest --secret="${secret_id}" )
  if ! gcloud "${flags[@]}"; then
    printf >&2 '%s: Error retrieving secret_id %s\n' "${FUNCNAME[0]}" "${secret_id}"
    return 1
  fi
}

#######################################
# Delete the secret vera_<project> from gcloud secrets
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   non-zero error code on failure
#######################################
function gcloud_rm_secret () {
  if [[ ! -x "$(command -v gcloud)" ]]; then
    printf >&2 '%s: gcloud: command not found\n' "${FUNCNAME[0]}"
    return 1
  fi

  local secret_id="vera_${1}"
  local -a flags
  flags=( secrets delete --quiet "${secret_id}" )
  if ! gcloud "${flags[@]}"; then
    printf >&2 '%s: Error deleting secret_id %s\n' "${FUNCNAME[0]}" "${secret_id}"
    return 1
  fi
}

function main () {
  local cmd="${1,,}" project="${2}" dest="${3}"
  local volume
  if [[ "${cmd}" != "create" ]] && [[ "${cmd,,}" != "rm" ]]; then
    volume="$(project_to_volume "${project}")"
  fi

  # Make sure project/dest only contain alphanum-_
  if [[ "${project//[^a-zA-Z0-9-_]}" != "${project}" ]]; then
    printf '%s: project contained invalid characters\n' "${FUNCNAME[0]}"
    return 1
  fi

  if [[ "${dest//[^a-zA-Z0-9-_]}" != "${dest}" ]]; then
    printf '%s: dest contained invalid characters\n' "${FUNCNAME[0]}"
    return 2
  fi

  case "${cmd}" in
    c|create)
      if _create "${project}"; then
        printf >&2 '%s: Create %s success\n' "${FUNCNAME[0]}" "${project}"
      fi
      ;;
    ls)
      _list
      ;;
    mount)
      if [[ -z "${project}" ]]; then
        mount_all
      else
        if mount_volume "${volume}"; then
          printf >&2 '%s: mount %s success\n' "${FUNCNAME[0]}" "${volume}"
        else
          printf >&2 '%s: mount %s failed\n' "${FUNCNAME[0]}" "${volume}"
        fi
      fi
      ;;
    mv)
      _mv "${project}" "${dest}"
      ;;
    rm)
      _rm "${project}"
      ;;
    shrink)
      shrink "${project}"
      ;;
    unmount)
      if [[ -z "${project}" ]]; then
        unmount_all
      else
        if unmount_volume "${volume}"; then
          printf >&2 '%s: unmount %s success\n' "${FUNCNAME[0]}" "${volume}"
        else
          printf >&2 '%s: unmount %s failed\n' "${FUNCNAME[0]}" "${volume}"
        fi
      fi
      ;;
    *)
      printf '%s <create|ls|mount|mv|rm|shrink|unmount> [project] [dest]\n' "${0}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
  main "$@"
fi
