Configure directories:
```sh
declare -A VERACRYPT=(
	["VOLUMES"]="/data3/vera,/data4/vera"
	["KEYFILES"]="/.../secrets/veracrypt"
	["MOUNTPOINT"]="/mnt"
	["VOLSIZE"]="50"
)
```
```sh
# Creates keyfile/volume in ${VERACRYPT[VOLUMES]}/${VERACRYPT[KEYFILES]}
veracryptcreate <PROJECT>
# Mount each volume to ${VERACRYPT[MOUNTPOINT]}
veracryptmount
# Unmount all volumes
veracryptunmount
```
