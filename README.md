# Cloud Backup

`Cloud Backup` is a complete and fully automated incremental cloud backup solution using free open-source tools for `MacOS`. It combines the power of [dar](http://dar.linux.free.fr), [par2](http://parchive.sourceforge.net), and [rclone](https://rclone.org) to perform incremental backups, ensure data integrity, and interact with the cloud, respectively. These tools are readily installed via [Homebrew](https://brew.sh). `launchd` services take care of scheduling incremental backups, detecting when moving onto the preferred WiFi network, and take note of disk (un)mounts. A workspace is created in memory for speed and avoiding disk wear-and-tear and some of the work is parallelized for efficiency. Optionally, install [Growl](https://github.com/growl/growl/tags) and [growlnotify](https://github.com/growl/growl/tags) to receive notifications.

## Usage

Move the folder containing `Cloud Backup` to `Library/Application Support` in your home directory. Configure your preferred WiFi `NETWORK` in `etc/config`, which contains many other parameters that can be tuned to your needs.

Each file in `etc/config.d` configures a backup target. Its parameters and their meaning are listed in the table below.

|parameter|meaning|
--------|-----
|`BACKUP_NAME`|base name for the backup|
|`SOURCE`|folder to back up|
|`TARGET`|[rclone](https://rclone.org) remote path|
|`DESTINATION`| directory to restore files to|

From the `bin` directory run:

```shell
./cloud_level-0.bash
```

This could take a while.

Copy `net.ddns.christiaanboersma.cloud_backup.plist` from the `share` folder to `Library/LaunchAgents` in your home directory. Log out and back in.

## Restoring from backup

Restoring entire backups is done with `cloud_restore.bash` from the `bin` directory:

```shell
./cloud_restore.bash documents
```

The first argument matches a file in `etc/config.d`. Use `cloud_restore_file.bash` to restore a single file:

```shell
./cloud_restore_file.bash documents Documents/myfile.txt
```

The first argument again matches a file in `etc/config.d` and the second argument is the file to restore.

## Trimming backups

Trimming backups is done with `cloud_trim.bash` from the `bin` directory:

```shell
./cloud_trim.bash documents 10
```

The first argument matches a file in `etc/config.d` and the second the level to trim up to.

Take care to follow up with a level-x backup:

```shell
./cloud_level-x.bash documents
```

Note that this may take significantly longer than usual, as the increment will be against and earlier backup.

## Notes

1. Cloud storage is required and [rclone](https://rclone.org) needs to be configured to access it.
2. Despite incremental backups, cloud space requirements will only grow. Use `cloud_trim.bash` to trim backups followed by a `cloud_level-x.bash` backup.
3. Logging is done to `Library/Logs/cloud_backup.log` in your home directory.
4. `dar`, `par2`, and `rclone` paths are hardcoded to be in  `/usr/local/bin`.
5. `unbuffer` is used to disable output buffering and can be readily installed with [Homebrew](https://brew.sh).

## BSD-3 License

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
