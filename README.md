# backup
Back up an entire linux system to google cloud storage.
1. [Usages](#usages)
2. [Commands](#commands)
3. [Init](#init)
4. [Start](#start)
5. [Schedule](#schedule)
6. [Show](#show)
7. [Unschedule](#unschedule)
8. [Reschedule](#reschedule)
9. [Snapshots](#snapshots)
10. [Restore](#restore)
11. [Conf Example](#conf-example)
12. [Dependencies](#dependencies)
13. [restic](#restic)
14. [mikefarah yq](#mikefarah-yq)



## Usages
```bash
backup <command>
backup [-cevh]
```
- command : Operation to perform. Next section has details on the possible commands.
- -c, --conf : Shows path to conf file if it exists.
- -e, --edit : Open conf in editor to add or change file. Editor used is vim if installed or vi otherwise.
- -v, --version : Show version info.
- -h, --help : Show help text. In case you forget how to use.

## Commands
There are a number of operations that can be performed in relation to the backup which can be specified as the command. Most commands will get the data they need from the conf file if there is one. If no conf file exists or required fields are missing, then it will prompt you to input the missing data and will update the conf file accordingly. Alternatively, you can also run `backup -e` or `backup --edit` first and add all the necessary configuration manually.

### Init
```bash
backup init
```
Initialize the google cloud storage (gs) repository (will be referred to as "the repository" from here on). This must be run first. After initializing the repository, it will also ask if you would want to schedule a regular backup and if you want to start the initial backup now.

### Start
```bash
backup start
```
Starts a backup. The repository must be initialized first. Backed up data will be encrypted using the repository password provided in the conf. Also provided in the conf is a list of files and directories to include and a list of regex patterns to exclude. This combination is used to determine what should be backed up. Backups are also incremental, so it won't re-upload duplicate data in the repository every backup and each subsequent backup won't take as much time. At the end of the backup, it will also forget old backups and delete data from the repository that isn't used anymore in order to reduce consumed memory and likewise cost.

### Schedule
```bash
backup schedule
```
This will add a cron job on your machine which will run `backup start` at a regular interval. It will also pipe the output to a custom command. This is useful in sending yourself the output logs by email or notification. The output command must support taking input from stdin. The cron time and output command can be specified in the conf. This will error if the cron job already exists.

### Show
```bash
backup show
```
The show command will output the backup cron job if it exists. If it doesn't exist, then nothing will be outputted and a non-zero exit code is returned.

### Unschedule
```bash
backup unschedule
```
This will remove the cron job from your machine and will error if the cron job doesn't exist.

### Reschedule
```bash
backup reschedule
```
This will update the cron job with the current configuration. Changing the cron time or output command will NOT update the cron job. The reschedule command will need to be run if you change the conf.

### Snapshots
```bash
backup snapshots
```
The snapshots command will output the list of saved snapshots.

### Restore
```bash
backup restore [-s <snapshot-id>]
```
- -s, --snapshot : The snapshot id to restore to. The default is latest.

This will restore your system using one of the saved snapshots. Use `backup snapshots` to get the list of snapshot ids. If no snapshot id is provided, then the latest snapshot will be restored.

## Conf Example
The conf file is in yaml format and is placed at the path returned by `backup -c`.
```yaml
backup:
	google:
		project-id: my-google-project
		credentials: /home/user/.config/backup.json
	restic:
		repository: gs:my-google-backup-bucket:/
		password: my_random_password
	includes:
		- /
		- /home
	excludes: #optional
		- .*/.cache/.*
		- .*/.local/share/gvfs-metadata/.*
		- .*/.local/share/Trash/.*
		- .*/.local/share/Steam/steamapps/.*
		- .*/.xsession-errors
		- .*/tmp/.*
		- .*/temp/.*
	job:
		cron: 0 2 * * *
		output-cmd: mail #optional
```
NOTE: This is only an example and you are expected to change it to meet your requirements. Fields that are optional are marked as optional. Inclusions have to be there, even if the only included directory is root. This tool will only backup the current filesystem. If there are mounted filesystems or separate partitions that you want to backup as well, then they have to be listed separately. For example, if home and usr are separate partitions here, then everything in root that is on the same filesystem and /home is backed up, but /usr isn't backed up because it is not included.

## Dependencies
These must be installed before using this tool.

### restic
This is used as the backend for handling the backup operations. For more information, please see the restic documentation [here](https://restic.readthedocs.io/en/stable/index.html).
```bash
apt install restic
```

### mikefarah yq
Used for yaml parsing with the conf file. For more information and the published versions, please see the yq github [here](https://github.com/mikefarah/yq).
```bash
wget https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_amd64.tar.gz -O - |\
	tar xz && mv yq_linux_amd64 /usr/bin/yq
./install-man-page.sh
rm install-man-page.sh
rm yq.1
```



