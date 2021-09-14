# INSTALLATION

```shell
# Put `vera` command on PATH
ln -svf ${PWD}/veracrypt.sh /usr/local/bin/vera
chmod +x ${PWD}/veracrypt.sh completion.sh
# Configure env
mv env.example env
```

Source completion.sh somewhere in your `.bashrc` for tab completion.

Make sure gcloud secrets is configured. Check if `gcloud secrets list` works, otherwise [configure](https://cloud.google.com/secret-manager) it.

# USAGE

```shell
# Create new volume in configured VERACRYPT_VOLUMES directory
# VERACRYPT_VOLUMES is a comma-separated list of directories, when the first directory can't hold a full volume anymore the next directory is tried
# A keyfile is generated and stored in VERACRYPT_KEYFILES directory
# A gcloud secret is created named vera_<project> and used as password
vera create <project>
# Mount project
# Automatically finds keyfile/secret
vera mount <project>
# Does what you expect
vera unmount <project>
# List info about projects in JSON-encoded
vera ls
# Shrinks a volume to the files in the volume
vera shrink <project>
# Removes volume/keyfile/secret from gcloud
vera rm <project>
```
