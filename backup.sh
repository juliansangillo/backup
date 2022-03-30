#! /bin/bash

set -eo pipefail
set -o noglob

VERSION=1.0
VERSION_INFO="backup version $VERSION"

CONF_FILE=/etc/backup.conf
KEEP_LAST_KEY=".backup.keep"
REPOSITORY_KEY=".backup.restic.repository"
PASSWORD_KEY=".backup.restic.password"
PROJECT_ID_KEY=".backup.google.project-id"
JSON_CREDENTIALS_KEY=".backup.google.credentials"
ACCESS_TOKEN_KEY=".backup.google.access-token"
CRON_KEY=".backup.job.cron"
OUTPUT_CMD_KEY=".backup.job.output-cmd"
INCLUDES_KEY=".backup.includes"
INCLUDES_ARR_KEY=".backup.includes[]"
EXCLUDES_KEY=".backup.excludes"
EXCLUDES_ARR_KEY=".backup.excludes[]"

IFS=$'\n'

PROMPT="SUDO password for $USER: "

function help {
	local help_text="Usage: backup [-d] [-q] <command> [-h]
Usage: backup [-c] [-e] [-v] [-h]

Back up an entire linux system to google cloud storage.

  command may be	init | start | schedule | show | unschedule | 
			reschedule | snapshots | restore

For detailed information on any command and its flags, run:
  backup <command> --help
  
backup.conf:

A yaml conf file is required by most commands. If no conf file exists or 
required fields are missing, then it will prompt you to input the missing 
data and will update the conf file accordingly, unless running in quiet mode. 
To manually create, run 'backup --edit'. Alternatively, you can run the init 
command in dry-run mode so it only prompts you for the required configuration 
and won't actually make changes. This can be done by running 
'backup --dry-run init'.

For detailed information on the conf file and its structure, please see:
  https://github.com/juliansangillo/backup#backupconf

Global Flags:
  -d, --dry-run		Execute the command without making changes to the restic 
			repository or crontab. Any commands that do make changes 
			will not run and will simply be outputted instead. It 
			will also output any variable exports except for 
			password related variables. This is useful for 
			troubleshooting as well as entering missing 
			configuration and walking through the process without 
			actually making changes.
				
  -q, --quiet		Execute the command in quiet mode. This will gaurentee 
			that the user is not prompted for input during runtime. 
			Any configuration that is missing or invalid will cause 
			it to error out instead of prompting the user for 
			information. Must be run as root.
				
  -c, --conf		Shows path to conf file if it exists.
  
  -e, --edit		Open conf in editor to add or change file. Editor used 
			is vim if installed or vi otherwise.
				
  -v, --version		Show version info.
  
  -h, --help		Show this help text."

	echo "$help_text"
}

function help_init {
	local help_text="Usage: backup [-d] [-q] init [-h]

Initialize the google cloud storage (gs) repository (the repository). This must 
be run first. It will also prompt you if you want to start the initial backup 
and if you want to schedule a regular backup. In quiet mode, you won't be 
prompted and the default 'no' response is used for both questions. In this case, 
the initial backup and scheduling a backup job will have to be done manually.

Options:
  -h, --help		Show this help text.
  
Global Flags:
  -d, --dry-run		Execute the command without making changes to the restic 
			repository or crontab. Any commands that do make changes 
			will not run and will simply be outputted instead. It 
			will also output any variable exports except for 
			password related variables. This is useful for 
			troubleshooting as well as entering missing 
			configuration and walking through the process without 
			actually making changes.
				
  -q, --quiet		Execute the command in quiet mode. This will gaurentee 
			that the user is not prompted for input during runtime. 
			Any configuration that is missing or invalid will cause 
			it to error out instead of prompting the user for 
			information.  Must be run as root."
	
	echo "$help_text"
}

function help_start {
	local help_text="Usage: backup [-d] [-q] start [-h]
	
Starts a backup. The repository must be initialized first. Backed up data will 
be encrypted using the repository password provided in the conf. Also provided 
in the conf is a list of files and directories to include and a list of regex 
patterns to exclude. This combination is used to determine what should be 
backed up. Backups are also incremental, so it won't re-upload duplicate data 
in the repository and each subsequent backup won't take as much time. At the 
end of the backup, it will also forget old backups and delete data from the 
repository that isn't used anymore in order to reduce consumed memory and cost.

Options:
  -h, --help		Show this help text.
  
Global Flags:
  -d, --dry-run		Execute the command without making changes to the restic 
			repository or crontab. Any commands that do make changes 
			will not run and will simply be outputted instead. It 
			will also output any variable exports except for 
			password related variables. This is useful for 
			troubleshooting as well as entering missing 
			configuration and walking through the process without 
			actually making changes.
				
  -q, --quiet		Execute the command in quiet mode. This will gaurentee 
			that the user is not prompted for input during runtime. 
			Any configuration that is missing or invalid will cause 
			it to error out instead of prompting the user for 
			information.  Must be run as root."
	
	echo "$help_text"
}

function help_schedule {
	local help_text="Usage: backup [-d] [-q] schedule [-h]
	
This will add a cron job on your machine which will run 'backup -q start' at a 
regular interval. It can also pipe the output to a custom command. This is 
useful in sending yourself the output logs by email or notification. The output 
command must support taking input from stdin. The cron time and output command 
can be specified in the conf. This will error if the cron job already exists.

Options:
  -h, --help		Show this help text.
  
Global Flags:
  -d, --dry-run		Execute the command without making changes to the restic 
			repository or crontab. Any commands that do make changes 
			will not run and will simply be outputted instead. It 
			will also output any variable exports except for 
			password related variables. This is useful for 
			troubleshooting as well as entering missing 
			configuration and walking through the process without 
			actually making changes.
				
  -q, --quiet		Execute the command in quiet mode. This will gaurentee 
			that the user is not prompted for input during runtime. 
			Any configuration that is missing or invalid will cause 
			it to error out instead of prompting the user for 
			information.  Must be run as root."
	
	echo "$help_text"
}

function help_show {
	local help_text="Usage: backup [-d] [-q] show [-h]
	
The show command will output the backup cron job if it exists. If it doesn't 
exist, then nothing will be outputted and a non-zero exit code is returned. 
Unaffected by --dry-run or --quiet.

Options:
  -h, --help		Show this help text."
	
	echo "$help_text"
}

function help_unschedule {
	local help_text="Usage: backup [-d] [-q] unschedule [-h]

This will remove the cron job from your machine and will error if the cron job 
doesn't exist.

Options:
  -h, --help		Show this help text.
  
Global Flags:
  -d, --dry-run		Execute the command without making changes to the restic 
			repository or crontab. Any commands that do make changes 
			will not run and will simply be outputted instead. It 
			will also output any variable exports except for 
			password related variables. This is useful for 
			troubleshooting as well as entering missing 
			configuration and walking through the process without 
			actually making changes.
				
  -q, --quiet		Execute the command in quiet mode. This will gaurentee 
			that the user is not prompted for input during runtime. 
			Any configuration that is missing or invalid will cause 
			it to error out instead of prompting the user for 
			information.  Must be run as root."

	echo "$help_text"
}

function help_reschedule {
	local help_text="Usage: backup [-d] [-q] reschedule [-h]
	
This will update the cron job with the current configuration. Changing the cron 
time or output command in the conf file will NOT automattically update the cron 
job. The reschedule command will need to be run if you change the conf.

Options:
  -h, --help		Show this help text.
  
Global Flags:
  -d, --dry-run		Execute the command without making changes to the restic 
			repository or crontab. Any commands that do make changes 
			will not run and will simply be outputted instead. It 
			will also output any variable exports except for 
			password related variables. This is useful for 
			troubleshooting as well as entering missing 
			configuration and walking through the process without 
			actually making changes.
				
  -q, --quiet		Execute the command in quiet mode. This will gaurentee 
			that the user is not prompted for input during runtime. 
			Any configuration that is missing or invalid will cause 
			it to error out instead of prompting the user for 
			information.  Must be run as root."
	
	echo "$help_text"
}

function help_snapshots {
	local help_text="Usage: backup [-d] [-q] snapshots [-h]

The snapshots command will output the list of saved snapshots. Unaffected by 
--dry-run or --quiet.

Options:
  -h, --help		Show this help text."
	
	echo "$help_text"
}

function help_restore {
	local help_text="backup [-d] [-q] restore [-s <snapshot-id>] [-h]

This will restore your system using one of the saved snapshots. Use 
'backup snapshots' to get the list of snapshot ids.

Options:
  -h, --help		Show this help text.
  
Global Flags:
  -d, --dry-run		Execute the command without making changes to the restic 
			repository or crontab. Any commands that do make changes 
			will not run and will simply be outputted instead. It 
			will also output any variable exports except for 
			password related variables. This is useful for 
			troubleshooting as well as entering missing 
			configuration and walking through the process without 
			actually making changes.
				
  -q, --quiet		Execute the command in quiet mode. This will gaurentee 
			that the user is not prompted for input during runtime. 
			Any configuration that is missing or invalid will cause 
			it to error out instead of prompting the user for 
			information.  Must be run as root."
	
	echo "$help_text"
}

function update_prefix {
	PRIOR_PREFIX="$LOG_PREFIX"
	LOG_PREFIX="$1"
	export SUDO_PROMPT="$1: $PROMPT"
}

function run {
	if $DRY_RUN ; then
		echo + "$@"
	else
		$@
	fi
}

function trim {
	local str="$1"
	
	echo "$str" | sed '/^[[:space:]]*$/d' | sed 's/^ *//g' | sed 's/ *$//g'
}

function load_conf_value {
	local expression=$1
	
	local result="$(yq "$expression" $CONF_FILE)"
	if [ "$result" == "null" ]; then
		local result=""
	fi
	
	echo "$(trim "$result")"
}

function update_conf_string {
	local expression=$1
	local value="$2"
	
	if [ ! -z "$value" ]; then
		yq -i "$expression = \"$value\"" $CONF_FILE 
	fi
}

function update_conf_integer {
	local expression=$1
	local value="$2"
	
	if [ ! -z "$value" ]; then
		yq -i "$expression = $value" $CONF_FILE 
	fi
}

function update_conf_array {
	local expression=$1
	local values="$2"
	
	yq -i "del($expression)" $CONF_FILE 
	for value in $values; do
		yq -i "$expression |= . + [\"$value\"]" $CONF_FILE 
	done
}

function create_conf {
	local user_group="$(id -gn)"
	
	sudo touch $CONF_FILE 
	sudo chgrp "$user_group" $CONF_FILE 
	sudo chmod ug=rw $CONF_FILE 
	sudo chmod o-rwx $CONF_FILE 
}

function restic_init {
	echo "${LOG_PREFIX}: Initializing restic repository..."
	run restic -v init 
	echo "${LOG_PREFIX}: init done."
}

function restic_backup {
	echo "${LOG_PREFIX}: Backing up to restic repository..."
	local includes=()
	local excludes=()
	
	for include in $BACKUP_INCLUDES; do
		local includes+=("$include")
	done
	
	if [ -z "$BACKUP_INCLUDES" ]; then
		local includes+=('/')
	fi
	
	for exclude in $BACKUP_EXCLUDES; do
		local excludes+=("-e")
		local excludes+=("$exclude")
	done
	
	run sudo -E restic -v backup -x \
		"${includes[@]}" \
		"${excludes[@]}" \
		-e $CONF_FILE 
	
	echo "${LOG_PREFIX}: backup done."
}

function restic_prune {
	if [ "$KEEP_LAST" != "*" ]; then
		echo "${LOG_PREFIX}: Pruning old backups..."
		run sudo -E restic -v forget \
			--prune \
			--keep-last $KEEP_LAST 
		echo "${LOG_PREFIX}: prune done."
	fi
}

function restic_check {
	echo "${LOG_PREFIX}: Checking repository health..."
	run sudo -E restic -v check
	echo "${LOG_PREFIX}: all green."
}

function restic_snapshots {
	sudo -E restic -v snapshots
}

function restic_restore {
	echo "${LOG_PREFIX}: Restoring from restic repository..."
	local snapshot=$1
	run sudo -E restic restore $snapshot --target / 
	echo "${LOG_PREFIX}: restore done."
}

function load_cron_job {
	if [ ! -f "$CONF_FILE" ]; then
		echo "${LOG_PREFIX}: $CONF_FILE does not exist. Creating..."
		create_conf
		echo "${LOG_PREFIX}: $CONF_FILE was created."
	fi

	BACKUP_JOB_CRON="$(load_conf_value $CRON_KEY)"
	BACKUP_JOB_OUTPUT_CMD="$(load_conf_value $OUTPUT_CMD_KEY)"
}

function validate_cron_job {
	if [ -z "$BACKUP_JOB_CRON" ]; then
		echo "${LOG_PREFIX}: error: '$CRON_KEY' is a required field but is missing" >&2
		exit 5
	fi
}

function update_cron_job {
	update_conf_string $CRON_KEY "$BACKUP_JOB_CRON"
	update_conf_string $OUTPUT_CMD_KEY "$BACKUP_JOB_OUTPUT_CMD"
}

function read_missing_cron_job {
	if [ -z "$BACKUP_JOB_CRON" ]; then
		BACKUP_JOB_CRON="$(read_input "Please enter your cron for the backup job: ")"
	fi
	
	if [ -z "$BACKUP_JOB_OUTPUT_CMD" ]; then
		wants_output_cmd="$(read_input "Do you want to pipe the output of the backup job to a command? (Y/n) ")"
		if [[ $wants_output_cmd =~ ^[Yy] ]]; then
			BACKUP_JOB_OUTPUT_CMD="$(read_input "Please enter your job output command: " "-e")"
		fi
	fi
}

function add_cron_job {
	load_cron_job
	
	if $QUIET ; then
		validate_cron_job
	else
		read_missing_cron_job
		validate_cron_job
		update_cron_job
	fi
	
	echo "${LOG_PREFIX}: Adding cron job..."
	if [ -z "$BACKUP_JOB_OUTPUT_CMD" ]; then
		local cron_str="$BACKUP_JOB_CRON $CRON_CMD"
	else
		local cron_str="$BACKUP_JOB_CRON $CRON_CMD | $BACKUP_JOB_OUTPUT_CMD"
	fi
	
	if $DRY_RUN ; then
		run sudo crontab -l 2> /dev/null
		run echo "$cron_str"
		run sudo crontab -
	else
		(sudo crontab -l 2> /dev/null ; echo "$cron_str") | sudo crontab - 
	fi
	
	echo "${LOG_PREFIX}: done."
}

function show_cron_job {
	sudo crontab -l 2> /dev/null | grep "$CRON_CMD"
}

function rm_cron_job {
	echo "${LOG_PREFIX}: Removing cron job..."
	
	if $DRY_RUN ; then
		run sudo crontab -l 2> /dev/null
		run grep -v "$CRON_CMD"
		run sudo crontab -
	else
		sudo crontab -l 2> /dev/null | grep -v "$CRON_CMD" | sudo crontab - 
	fi
	
	echo "${LOG_PREFIX}: done."
}

function load_conf {
	if [ ! -f "$CONF_FILE" ]; then
		echo "${LOG_PREFIX}: $CONF_FILE does not exist. Creating..."
		create_conf
		echo "${LOG_PREFIX}: $CONF_FILE was created."
	fi

	echo "${LOG_PREFIX}: Loading conf file..."
	
	GOOGLE_PROJECT_ID="$(load_conf_value $PROJECT_ID_KEY)"
	JSON_CREDENTIALS_FILE="$(load_conf_value $JSON_CREDENTIALS_KEY)"
	GOOGLE_APPLICATION_CREDENTIALS="`eval echo ${JSON_CREDENTIALS_FILE//>}`"
	GOOGLE_ACCESS_TOKEN="$(load_conf_value $ACCESS_TOKEN_KEY)"
	RESTIC_REPOSITORY="$(load_conf_value $REPOSITORY_KEY)"
	RESTIC_PASSWORD="$(load_conf_value $PASSWORD_KEY)"
	BACKUP_INCLUDES="$(load_conf_value $INCLUDES_ARR_KEY)"
	BACKUP_EXCLUDES="$(load_conf_value $EXCLUDES_ARR_KEY)"
	KEEP_LAST="$(load_conf_value $KEEP_LAST_KEY)"
	
	echo "${LOG_PREFIX}: $CONF_FILE was loaded."
}

function validate_conf {
	if [ -z "$GOOGLE_PROJECT_ID" ]; then
		echo "${LOG_PREFIX}: error: '$PROJECT_ID_KEY' is required but it is missing. Please check the conf file and try again." >&2
		exit 5
	fi
	
	if [[ -z "$JSON_CREDENTIALS_FILE" && -z "$GOOGLE_ACCESS_TOKEN" ]]; then
		echo "${LOG_PREFIX}: error: '$JSON_CREDENTIALS_KEY' or '$ACCESS_TOKEN_KEY' is required but both are missing. Please check the conf file and try again." >&2
		exit 5
	fi
	
	if [ -z "$RESTIC_REPOSITORY" ]; then
		echo "${LOG_PREFIX}: error: '$REPOSITORY_KEY' is required but it is missing. Please check the conf file and try again." >&2
		exit 5
	fi
	
	if [ -z "$RESTIC_PASSWORD" ]; then
		echo "${LOG_PREFIX}: error: '$PASSWORD_KEY' is required but it is missing. Please check the conf file and try again." >&2
		exit 5
	fi
	
	if [ -z "$KEEP_LAST" ]; then
		echo "${LOG_PREFIX}: error: '$KEEP_LAST_KEY' is required but it is missing. Please check the conf file and try again." >&2
		exit 5
	elif [[ ! "$KEEP_LAST" =~ ^[0-9]+$ && "$KEEP_LAST" != "*" ]]; then
		echo "${LOG_PREFIX}: error: '$KEEP_LAST_KEY' is invalid. Must be * or a number. Please try again." >&2
		exit 5
	fi
}

function export_conf {
	if $DRY_RUN ; then
		run export GOOGLE_PROJECT_ID="$GOOGLE_PROJECT_ID"
		run export GOOGLE_APPLICATION_CREDENTIALS="$GOOGLE_APPLICATION_CREDENTIALS"
		run export GOOGLE_ACCESS_TOKEN="$GOOGLE_ACCESS_TOKEN"
		run export RESTIC_REPOSITORY="$RESTIC_REPOSITORY"
		run export RESTIC_PASSWORD="[[hidden]]"
	fi
	
	export GOOGLE_PROJECT_ID
	export GOOGLE_APPLICATION_CREDENTIALS
	export GOOGLE_ACCESS_TOKEN
	export RESTIC_REPOSITORY
	export RESTIC_PASSWORD
}

function update_conf {
	echo "${LOG_PREFIX}: Updating conf file..."
	
	update_conf_string $PROJECT_ID_KEY "$GOOGLE_PROJECT_ID"
	update_conf_string $JSON_CREDENTIALS_KEY "$JSON_CREDENTIALS_FILE"
	update_conf_string $ACCESS_TOKEN_KEY "$GOOGLE_ACCESS_TOKEN"
	update_conf_string $REPOSITORY_KEY "$RESTIC_REPOSITORY"
	update_conf_string $PASSWORD_KEY "$RESTIC_PASSWORD"
	
	if [[ "$KEEP_LAST" =~ ^[0-9]+$ ]]; then
		update_conf_integer $KEEP_LAST_KEY "$KEEP_LAST"
	else
		update_conf_string $KEEP_LAST_KEY "$KEEP_LAST"
	fi
	
	update_conf_array $INCLUDES_KEY "$BACKUP_INCLUDES"
	update_conf_array $EXCLUDES_KEY "$BACKUP_EXCLUDES"
	
	echo "${LOG_PREFIX}: $CONF_FILE was updated."
}

function read_input {
	local result=""
	local prompt="$1"
	local flags="$2"
	
	read -p "$prompt" ${flags[@]} result
	
	echo "$(trim "$result")"
}

function read_missing_google_credentials {
	if [ -z "$GOOGLE_PROJECT_ID" ]; then
		GOOGLE_PROJECT_ID="$(read_input "Please enter your Google Project ID: ")"
	fi
	
	if [[ -z "$GOOGLE_APPLICATION_CREDENTIALS" || ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
		if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
			echo "${LOG_PREFIX}: No credentials provided."
		else
			echo "${LOG_PREFIX}: Credentials file '$GOOGLE_APPLICATION_CREDENTIALS' does not exist."
		fi
		
		has_credentials="$(read_input "Do you have a JSON Credentials file? (Y/n) ")"
		if [[ $has_credentials =~ ^[Yy] ]]; then
			JSON_CREDENTIALS_FILE="$(read_input "Please enter your Google Credentials File (json): " "-e")"
			until [ -f "$(eval echo ${JSON_CREDENTIALS_FILE//>})" ]; do
				echo "${LOG_PREFIX}: '$JSON_CREDENTIALS_FILE' does not exist. Verify that the provided path is correct and try again."
				JSON_CREDENTIALS_FILE="$(read_input "Please enter your Google Credentials File (json): " "-e")"
			done
			GOOGLE_APPLICATION_CREDENTIALS="`eval echo ${JSON_CREDENTIALS_FILE//>}`"
		fi
		
		if [[ ! $has_credentials =~ ^[Yy] ]]; then
			echo "${LOG_PREFIX}: Credentials file does not exist. Need access token."
			JSON_CREDENTIALS_FILE=""
			GOOGLE_APPLICATION_CREDENTIALS=""
			if [ -z "$GOOGLE_ACCESS_TOKEN" ]; then
				GOOGLE_ACCESS_TOKEN="$(read_input "Please enter your Google Access Token: " "-s")"
			fi
			echo
		fi
	fi
}

function read_missing_restic_credentials {
	if [ -z "$RESTIC_REPOSITORY" ]; then
		local bucket="$(read_input "Repository: Please enter your Google Storage Bucket: gs:")"
		until [ ! -z "$bucket" ]; do
			echo "${LOG_PREFIX}: Google Storage Bucket is required. Please try again."
			local bucket="$(read_input "Repository: Please enter your Google Storage Bucket: gs:")"
		done
		
		local dir="$(read_input "Repository: Please enter directory (default is /): gs:$bucket:")"
		if [ -z "$dir" ]; then
			local dir="/"
		fi
		
		RESTIC_REPOSITORY="gs:$bucket:$dir"
	fi
	
	if [ -z "$RESTIC_PASSWORD" ]; then
		RESTIC_PASSWORD="$(read_input "Please enter your password for new repository: " "-s")"
		echo
		RESTIC_PASSWORD_CONFIRM="$(read_input "Please enter your password again: " "-s")"
		echo
		until [ "$RESTIC_PASSWORD" == "$RESTIC_PASSWORD_CONFIRM" ]; do
			echo "${LOG_PREFIX}: Passwords don't match. Please try again."
			RESTIC_PASSWORD="$(read_input "Please enter your password for new repository: " "-s")"
			echo
			RESTIC_PASSWORD_CONFIRM="$(read_input "Please enter your password again: " "-s")"
			echo
		done
	fi
}

function read_missing_inclusions {
	if [ -z "$BACKUP_INCLUDES" ];  then
		echo "${LOG_PREFIX}: No includes provided."
		
		echo -e "\n\e[33mWARNING: If no includes are provided, then ' / ' will be backed up.\e[0m" >&2
		echo -e "\e[33mWARNING: Only the current filesystem is backed up by default. Attached filesystems will not be backed up.\e[0m" >&2
		echo -e "\e[33mThis is including but not limited to attached media, virtual filesystems, and other partitions.\e[0m" >&2
		echo -e "\e[33mIf you want these to be backed up as well, their directories must be manually included.\e[0m\n" >&2
		
		want_includes="$(read_input "Do you want to provide file and/or directory inclusions? (Y/n) ")"
		if [[ $want_includes =~ ^[Yy] ]]; then
			local tmp_file=/tmp/backup_includes
			local instructions="Enter each inclusion on a new line. (Save and exit when finished)

Please enter your includes below:
"
			
			echo "$instructions" > $tmp_file
			if command -v vim &> /dev/null ; then
				vim '+ normal GA' $tmp_file
			else
				vi '+ normal GA' $tmp_file
			fi
			
			BACKUP_INCLUDES="$(trim "$(cat $tmp_file | sed -e '1,/includes/d')")"
			rm $tmp_file
		fi
		
		if [ -z "$BACKUP_INCLUDES" ]; then
			BACKUP_INCLUDES=('/')
		fi
	fi
}

function read_missing_exclusions {
	if [ -z "$BACKUP_EXCLUDES" ];  then
		echo "${LOG_PREFIX}: No excludes provided."
		
		want_excludes="$(read_input "Do you want to provide exclusions? (Y/n) ")"
		if [[ $want_excludes =~ ^[Yy] ]]; then
			local tmp_file=/tmp/backup_excludes
			local instructions="Enter each exclusion on a new line. (Save and exit when finished)

Please enter your excludes below:
"
			
			echo "$instructions" > $tmp_file
			if command -v vim &> /dev/null ; then
				vim '+ normal GA' $tmp_file
			else
				vi '+ normal GA' $tmp_file
			fi
			
			BACKUP_EXCLUDES="$(trim "$(cat $tmp_file | sed -e '1,/excludes/d')")"
			rm $tmp_file
		fi
	fi
}

function read_missing_keep {
	if [ -z "$KEEP_LAST" ]; then
		KEEP_LAST="$(read_input 'How many backups do you wish to keep? (old backups and their data will be deleted) (enter * to keep all) ')"
		until [[ "$KEEP_LAST" =~ ^[0-9]+$ || "$KEEP_LAST" == "*" ]]; do
			echo "${LOG_PREFIX}: '$KEEP_LAST' is invalid. Must be * or a number. Please try again."
			KEEP_LAST="$(read_input 'How many backups do you wish to keep? (old backups and their data will be deleted) (enter * to keep all) ')"
		done
	fi
}

function read_missing_conf {
	read_missing_google_credentials
	read_missing_restic_credentials
	read_missing_inclusions
	read_missing_exclusions
	read_missing_keep
}

function load_all_conf {
	load_conf
	
	if $QUIET ; then
		validate_conf
	else
		read_missing_conf
		validate_conf
		update_conf
	fi
	
	export_conf
}

function init {
	update_prefix "backup-init"
	
	while (( $# )); do
		case $1 in
			-h|--help)
				help_init
				exit 0
				;;
			*)
				echo "${LOG_PREFIX}: error: \"$1\" is not a known option."  >&2
				echo >&2
				help_init >&2
				exit 1
		esac
	done

	echo "${PRIOR_PREFIX}: init"
	
	if $QUIET ; then
		local wants_initial_backup='n'
		local wants_cron_job='n'
	else
		local wants_initial_backup="$(read_input "Do you also want to start the initial backup? (Once started, this will take a lot of time to complete) (Y/n) ")"
		local wants_cron_job="$(read_input "Do you also want to schedule a regular backup? (Y/n) ")"
	fi
	
	load_all_conf
	
	restic_init
	
	if [[ $wants_initial_backup =~ ^[Yy] ]]; then
		restic_backup 2>&1
	else
		echo "run '$SCRIPT start' when ready to start the initial backup, or wait until backup job runs if one is scheduled."
	fi
	
	if [[ $wants_cron_job =~ ^[Yy] ]]; then
		add_cron_job
	else
		echo "run '$SCRIPT schedule' to schedule the backup job when ready."
	fi
}

function start {
	update_prefix "backup-start"
	
	while (( $# )); do
		case $1 in
			-h|--help)
				help_start
				exit 0
				;;
			*)
				echo "${LOG_PREFIX}: error: \"$1\" is not a known option."  >&2
				echo >&2
				help_start >&2
				exit 1
		esac
	done
	
	echo "${PRIOR_PREFIX}: start"
	
	load_all_conf
	
	restic_backup
	restic_prune
	restic_check
}

function schedule {
	update_prefix "backup-schedule"
	
	while (( $# )); do
		case $1 in
			-h|--help)
				help_schedule
				exit 0
				;;
			*)
				echo "${LOG_PREFIX}: error: \"$1\" is not a known option."  >&2
				echo >&2
				help_schedule >&2
				exit 1
		esac
	done

	if [ ! -z "$(show_cron_job)" ]; then
		echo "${LOG_PREFIX}: error: backup job already exists."  >&2
		exit 5
	fi
	
	echo "${PRIOR_PREFIX}: schedule"
	
	add_cron_job
}

function show {
	update_prefix "backup-show"
	
	while (( $# )); do
		case $1 in
			-h|--help)
				help_show
				exit 0
				;;
			*)
				echo "${LOG_PREFIX}: error: \"$1\" is not a known option."  >&2
				echo >&2
				help_show >&2
				exit 1
		esac
	done
	
	show_cron_job
}

function unschedule {
	update_prefix "backup-unschedule"
	
	while (( $# )); do
		case $1 in
			-h|--help)
				help_unschedule
				exit 0
				;;
			*)
				echo "${LOG_PREFIX}: error: \"$1\" is not a known option."  >&2
				echo >&2
				help_unschedule >&2
				exit 1
		esac
	done

	if [ -z "$(show_cron_job)" ]; then
		echo "${LOG_PREFIX}: error: backup job doesn't exist."  >&2
		exit 5
	fi
	
	echo "${PRIOR_PREFIX}: unschedule"
	
	rm_cron_job
}

function reschedule {
	update_prefix "backup-reschedule"
	
	while (( $# )); do
		case $1 in
			-h|--help)
				help_reschedule
				exit 0
				;;
			*)
				echo "${LOG_PREFIX}: error: \"$1\" is not a known option."  >&2
				echo >&2
				help_reschedule >&2
				exit 1
		esac
	done

	if [ -z "$(show_cron_job)" ]; then
		echo "${LOG_PREFIX}: error: backup job doesn't exist."  >&2
		exit 5
	fi
	
	echo "${PRIOR_PREFIX}: reschedule"
	
	rm_cron_job
	add_cron_job
}

function snapshots {
	update_prefix "backup-snapshots"
	
	while (( $# )); do
		case $1 in
			-h|--help)
				help_snapshots
				exit 0
				;;
			*)
				echo "${LOG_PREFIX}: error: \"$1\" is not a known option."  >&2
				echo >&2
				help_snapshots >&2
				exit 1
		esac
	done

	load_all_conf
	
	restic_snapshots
}

function restore {
	update_prefix "backup-restore"

	local snapshot=latest
	while (( $# )); do
		case $1 in
			-h|--help)
				help_restore
				exit 0
				;;
			-s|--snapshot)
				if [ ! -z $2 ]; then
					local snapshot=$2
					shift 2
				else
					echo "${LOG_PREFIX}: error: \"$1\" is missing an argument."  >&2
					exit 3
				fi
				;;
			*)
				echo "${LOG_PREFIX}: error: \"$1\" is not a known option."  >&2
				echo >&2
				help_restore >&2
				exit 1
		esac
	done
	
	echo "${PRIOR_PREFIX}: restore"
	
	load_all_conf
	
	restic_restore $snapshot
}

function conf_path {
	if [ ! -f $CONF_FILE ]; then
		echo "no conf file exists" >&2
		return 2
	fi
	
	echo "$CONF_FILE"
	return 0
}

function conf_edit {
	if command -v vim &> /dev/null ; then
		vim -c 'set syntax=yaml' $CONF_FILE
	else
		vi $CONF_FILE
	fi
}

if [ -f "$0" ]; then
	SCRIPT="$(realpath "$0")"
else
	SCRIPT="$0"
fi
CRON_CMD="$SCRIPT -q start 2>&1"

DRY_RUN=false
QUIET=false
while (( $# )); do
	case $1 in
		-h|--help)
			help
			exit 0
			;;
		-v|--version)
			echo "$VERSION_INFO"
			exit 0
			;;
		-c|--conf)
			conf_path
			exit $?
			;;
		-e|--edit)
			conf_edit
			exit 0
			;;
		-d|--dry-run)
			DRY_RUN=true
			shift
			;;
		-q|--quiet)
			QUIET=true
			shift
			;;
		*)
			COMMAND=$1
			shift
			break
	esac
done

update_prefix "backup"

if $QUIET && [ "$EUID" -ne 0 ]; then
	echo "${LOG_PREFIX}: error: Can not run as normal user in quiet mode. If running in quiet mode, please re-run with sudo." >&2
	exit 1
fi

case $COMMAND in
	init) 
		init $@
		;;
	start)
		start $@
		;;
	schedule)
		schedule $@
		;;
	show)
		show $@
		;;
	unschedule)
		unschedule $@
		;;
	reschedule)
		reschedule $@
		;;
	snapshots)
		snapshots $@
		;;
	restore)
		restore $@
		;;
	*)
		echo "${LOG_PREFIX}: error: \"$COMMAND\" is not a known command."  >&2
		echo >&2
		help >&2
		exit 1
esac
