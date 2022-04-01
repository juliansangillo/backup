# backup
Back up an entire linux system to google cloud storage.
1. [Usages](#usages)
2. [Commands](#commands)
    1. [Init](#init)
    2. [Start](#start)
    3. [Schedule](#schedule)
    4. [Show](#show)
    5. [Unschedule](#unschedule)
    6. [Reschedule](#reschedule)
    7. [Snapshots](#snapshots)
    8. [Restore](#restore)
3. [backup.conf](#backupconf)
4. [Dependencies](#dependencies)
    1. [restic](#restic)
    2. [mikefarah yq](#mikefarah-yq)
5. [Install](#install)

## Usages
```bash
backup [-d] [-q] <command> [-h]
backup [-c] [-e] [-v] [-h]
```
- command : Operation to perform. Next section has details on the possible commands.
- -d, --dry-run : Execute the command without making changes to the restic repository or crontab. Any commands that do make changes will not run and will simply be outputted instead. It will also output any variable exports except for password related variables. This is useful for troubleshooting as well as entering missing configuration and walking through the process without actually making changes.
- -q, --quiet : Execute the command in quiet mode. This will gaurentee that the user is not prompted for input during runtime. Any configuration that is missing or invalid will cause it to error out instead of prompting the user for information. NOTE: This can't be run as a normal user in quiet mode due to interactive password prompts. If running in quiet mode, this must be run with sudo.
- -c, --conf : Shows path to conf file if it exists.
- -e, --edit : Open conf in editor to add or change file. Editor used is vim if installed or vi otherwise.
- -v, --version : Show version info.
- -h, --help : Show help text. In case you forget how to use.

## Commands
There are a number of operations that can be performed in relation to the backup which can be specified as the command. Most commands will get the data they need from the conf file if there is one. If no conf file exists or required fields are missing, then it will prompt you to input the missing data and will update the conf file accordingly, unless running in quiet mode. Alternatively, you can also run `backup --edit` first and add all the necessary configuration manually.

### Init
```bash
backup [-d] [-q] init [-h]
```
Initialize the google cloud storage (gs) repository (will be referred to as "the repository" from here on). This must be run first. It will also prompt you if you want to start the initial backup and if you want to schedule a regular backup. In quiet mode, you won't be prompted and the default 'no' response is used for both questions. In this case, the initial backup and scheduling a backup job will have to be done manually.

### Start
```bash
backup [-d] [-q] start [-h]
```
Starts a backup. The repository must be initialized first. Backed up data will be encrypted using the repository password provided in the conf. Also provided in the conf is a list of files and directories to include and a list of regex patterns to exclude. This combination is used to determine what should be backed up. Backups are also incremental, so it won't re-upload duplicate data in the repository and each subsequent backup won't take as much time. At the end of the backup, it will also forget old backups and delete data from the repository that isn't used anymore in order to reduce consumed memory and cost.

### Schedule
```bash
backup [-d] [-q] schedule [-h]
```
This will add a cron job on your machine which will run `backup -q start` at a regular interval. It can also pipe the output to a custom command. This is useful in sending yourself the output logs by email or notification. The output command must support taking input from stdin. The cron time and output command can be specified in the conf. This will error if the cron job already exists.

### Show
```bash
backup [-d] [-q] show [-h]
```
The show command will output the backup cron job if it exists. If it doesn't exist, then nothing will be outputted and a non-zero exit code is returned. Unaffected by --dry-run or --quiet.

### Unschedule
```bash
backup [-d] [-q] unschedule [-h]
```
This will remove the cron job from your machine and will error if the cron job doesn't exist.

### Reschedule
```bash
backup [-d] [-q] reschedule [-h]
```
This will update the cron job with the current configuration. Changing the cron time or output command in the conf file will NOT automattically update the cron job. The reschedule command will need to be run if you change the conf.

### Snapshots
```bash
backup [-d] [-q] snapshots [-h]
```
The snapshots command will output the list of saved snapshots. Unaffected by --dry-run or --quiet.

### Restore
```bash
backup [-d] [-q] restore [-s <snapshot-id>] [-h]
```
- -s, --snapshot : The snapshot id to restore to. The default is latest.

This will restore your system using one of the saved snapshots. Use `backup snapshots` to get the list of snapshot ids.

## backup.conf
The conf file is in yaml format and is placed at the path returned by `backup --conf`.
```yaml
backup:
    keep: 10    #How many backups to keep in the repository. Any old backups that exceed this amount will be deleted. Enter '*' here to keep all backups.
    google:
        project-id: my-google-project
        credentials: /home/user/.config/backup.json    #Required only if no access token.
        access-token: some_gcloud_access_token    #Required only if no json credentials.
    restic:
        repository: gs:my-google-backup-bucket:/    #Google storage bucket and restic repository. Must start with gs, then have the bucket name, and then end with the directory path each separated by colons.
        password: my_random_password    #Password choosen by you to encrypt the files with. A randomized and secure password is recommended here.
    includes:    #Optional. List of files and directories to include in the backup. Default is /. Separate filesystems and partitions must be specified here to be backed as well.
        - /
        - /home
    excludes:    #Optional. List of paths to exclude from the backup. Regex is supported here. Any file or directory path that is a match will not be backed up.
        - .*/.cache/.*
        - .*/.local/share/gvfs-metadata/.*
        - .*/.local/share/Trash/.*
        - .*/.local/share/Steam/steamapps/.*
        - .*/.xsession-errors
        - .*/tmp/.*
        - .*/temp/.*
    job:
        cron: 0 2 * * *    #Cron string. The backup will run on a regular schedule at this time.
        output-cmd: mail -s "Hello World" someone@example.com    #Optional. Bash command to pipe the output of the backup to. Useful for notifications.
```
To manually create, run `backup --edit`. Alternatively, you can run the init command in dry-run mode so it only prompts you for the required configuration and won't actually make changes. This can be done by running `backup --dry-run init`.  
NOTE: This is only an example and you are expected to change it to meet your requirements. Fields that are optional are marked as optional. This tool will only backup the current filesystem. If there are mounted filesystems or separate partitions that you want to backup as well, then they have to be listed separately. For example, if home and usr are separate partitions here, then everything in root that is on the same filesystem and /home is backed up, but /usr isn't backed up because it is not included.

## Dependencies
These must be installed before using this tool.

### restic
This is used as the backend for handling the backup operations. For more information, please see the restic documentation [here](https://restic.readthedocs.io/en/stable/index.html).
```bash
sudo apt install restic
```

### mikefarah yq
Used for yaml parsing with the conf file. For more information and the published versions, please see the yq github [here](https://github.com/mikefarah/yq).
```bash
sudo wget \
    https://github.com/mikefarah/yq/releases/download/v${version}/yq_linux_amd64.tar.gz -O - |\
    sudo tar xz && sudo mv yq_linux_amd64 /usr/bin/yq
```
```bash
sudo ./install-man-page.sh && \
    sudo rm install-man-page.sh && \
    sudo rm yq.1
```

### fcron
Used for cron scheduling. For more information, please see the fcron home page [here](http://fcron.free.fr).
```bash
sudo wget \
    http://fcron.free.fr/archives/fcron-${version}.src.tar.gz -O - |\
    sudo tar x && cd fcron-${version}
```
```bash
./configure &&
    make &&
    sudo make install
```

## Installation
To install, please install the dependencies above, then run the commands below:
```bash
version=<version-to-install>
```
```bash
sudo wget https://github.com/juliansangillo/backup/releases/download/v${version}/backup.sh \
    && sudo chmod +x backup.sh \
    && sudo mv backup.sh /bin/backup
```
All versions are available on the releases page. You can also check the version you currently have on your machine by running `backup -v`.