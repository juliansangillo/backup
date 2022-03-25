#! /bin/bash

VERSION=1.0
VERSION_INFO="backup version $VERSION"

CONF_FILE=/etc/backup.conf
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

RESTIC_MAJOR_VERSION=0
YQ_MAJOR_VERSION=4

IFS=$'\n'

if [ $EUID -ne 0 ]; then
    SUDO='sudo -p "Password for $USER: "'
fi

function trim {
	local str="$1"
	
	echo "$str" | sed 's/^ *//g' | sed 's/ *$//g'
}

function read_input {
	local result=""
	local prompt="$1"
	local flags="$2"
	
	read -p "$prompt" ${flags[@]} result
	
	echo "$(trim "$result")"
}

function get_input {
	local input="$1"
	local expression="$2"
	local optional=$3
	local silent=$4
	local readline=$5 #this is for autocompleting paths
	
	local flags=()
	if $silent ; then
		flags+=("-s")
	fi
	if $readline ; then
		flags+=("-e")
	fi
	
	local result="$(yq e "$expression" $CONF_FILE)"
	if [ "$result" == "null" ]; then
		local result=""
	fi
	
	if ! $optional && [ -z "$result" ]; then
		local result="$(read_input "Please enter your $input: " "${flags[@]}")"
	fi
	
	echo "$(trim "$result")"
}

function load_cron_job {
	export BACKUP_JOB_CRON="$(get_input "cron for the backup job" "$CRON_KEY" false false false)"
	
	export BACKUP_JOB_OUTPUT_CMD="$(get_input "job output command" "$OUTPUT_CMD_KEY" true false true)"
	if [ -z "$BACKUP_JOB_OUTPUT_CMD" ]; then
		wants_output_cmd="$(read_input "Do you want to pipe the output of the backup job to a command? (Y/n) ")"
		if [[ $wants_output_cmd =~ ^[Yy] ]]; then
			export BACKUP_JOB_OUTPUT_CMD="$(get_input "job output command" "$OUTPUT_CMD_KEY" false false true)"
		fi
	fi
}

function load_repository {
	export RESTIC_REPOSITORY="$(get_input "repository as a Google Storage Bucket: gs" "$REPOSITORY_KEY" true false false)"
	if [ -z "$RESTIC_REPOSITORY" ]; then
		export RESTIC_REPOSITORY="gs:$(get_input "repository as a Google Storage Bucket: gs" "$REPOSITORY_KEY" false false false)"
	fi
}

function load_password {
	export RESTIC_PASSWORD="$(get_input "password for new repository" "$PASSWORD_KEY" false true false)"
	echo
	
	RESTIC_PASSWORD_CONFIRM="$(get_input "password again" "$PASSWORD_KEY" false true false)"
	echo
	
	if [ "$RESTIC_PASSWORD" != "$RESTIC_PASSWORD_CONFIRM" ]; then
		echo "${LOG_PREFIX}: error: Passwords don't match. Please try again." >&2
		exit 2
	fi
}

function load_credentials {
	local credentials_file_input="Google Credentials File (json)"
	local access_token_input="Google Access Token"

	JSON_CREDENTIALS_FILE="$(get_input "$credentials_file_input" "$JSON_CREDENTIALS_KEY" true false false)"
	export GOOGLE_APPLICATION_CREDENTIALS="`eval echo ${JSON_CREDENTIALS_FILE//>}`"
	export GOOGLE_ACCESS_TOKEN="$(get_input "$access_token_input" "$ACCESS_TOKEN_KEY" true false false)"
	if [[ -z "$GOOGLE_APPLICATION_CREDENTIALS" || ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
		if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
			echo "${LOG_PREFIX}: No credentials provided."
		else
			echo "${LOG_PREFIX}: Credentials file '$GOOGLE_APPLICATION_CREDENTIALS' does not exist."
		fi
		
		has_credentials="$(read_input "Do you have a JSON Credentials file? (Y/n) ")"
		if [[ $has_credentials =~ ^[Yy] ]]; then
			JSON_CREDENTIALS_FILE="$(get_input "$credentials_file_input" "$JSON_CREDENTIALS_KEY" false false true)"
			export GOOGLE_APPLICATION_CREDENTIALS="`eval echo ${JSON_CREDENTIALS_FILE//>}`"
			until [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; do
				echo "'$GOOGLE_APPLICATION_CREDENTIALS' does not exist. Verify that the provided path is correct and try again."
				JSON_CREDENTIALS_FILE="$(read_input "Please enter your ${credentials_file_input}:" "-e")"
				export GOOGLE_APPLICATION_CREDENTIALS="`eval echo ${JSON_CREDENTIALS_FILE//>}`"
			done
		fi
		
		if [[ ! $has_credentials =~ ^[Yy] ]]; then
			echo "${LOG_PREFIX}: Credentials file does not exist. Need access token."
			JSON_CREDENTIALS_FILE=""
			export GOOGLE_APPLICATION_CREDENTIALS=""
			export GOOGLE_ACCESS_TOKEN="$(get_input "$access_token_input" "$ACCESS_TOKEN_KEY" false true false)"
			echo
		fi
	fi
}

function load_inclusions {
	export LOADED_INCLUDES=false

	export BACKUP_INCLUDES="$(get_input "included files" "$INCLUDES_ARR_KEY" true false false)"
	if [ -z "$BACKUP_INCLUDES" ]; then
		echo "${LOG_PREFIX}: No includes provided."
		
		echo -e "\n\e[33mWARNING: If no includes are provided, then ' / ' will be backed up.\e[0m" >&2
		echo -e "\e[33mWARNING: Only the current filesystem is backed up by default. Attached filesystems will not be backed up.\e[0m"
		echo -e "\e[33mThis is including but not limited to attached media, virtual filesystems, and other partitions.\e[0m"
		echo -e "\e[33mIf you want these to be backed up as well, their directories must be manually included.\e[0m\n" >&2
		
		want_includes="$(read_input "Do you want to provide file and/or directory inclusions? (Y/n) ")"
		if [[ $want_includes =~ ^[Yy] ]]; then
			echo "Please enter each inclusion below. (Press enter again when finished)"
			
			local includes=()
			local include="undefined"
			until [ -z "$include" ]; do
				include="$(read_input 'Enter included file or directory: ' '-e')"
				if [ ! -z "$include" ]; then
					includes+=("$include")
				fi
			done
			
			export BACKUP_INCLUDES="${includes[*]}"
			export LOADED_INCLUDES=true
		fi
		
		if [ -z "$BACKUP_INCLUDES" ]; then
			export BACKUP_INCLUDES=('/')
			export LOADED_INCLUDES=true
		fi
	fi
}

function load_exclusions {
	export LOADED_EXCLUDES=false
	
	export BACKUP_EXCLUDES="$(get_input "excluded files" "$EXCLUDES_ARR_KEY" true false false)"
	if [ -z "$BACKUP_EXCLUDES" ]; then
		echo "${LOG_PREFIX}: No excludes provided."
		want_excludes="$(read_input "Do you want to provide exclusions? (Y/n) ")"
		if [[ $want_excludes =~ ^[Yy] ]]; then
			echo -e "\nNOTE: Exclusions are entered as regex patterns. Any file path matching at least one pattern will not be backed up.\n"
			
			echo "Please enter each exclusion below. (Press enter again when finished)"
			
			local excludes=()
			local exclude="undefined"
			until [ -z "$exclude" ]; do
				exclude="$(read_input 'Enter exclude pattern: ' '-e')"
				if [ ! -z "$exclude" ]; then
					excludes+=("$exclude")
				fi
			done
			
			export BACKUP_EXCLUDES="${excludes[*]}"
			export LOADED_EXCLUDES=true
		fi
	fi
}

function update_conf {
	echo "${LOG_PREFIX}: Updating conf file..."
	
	yq e -i "$PROJECT_ID_KEY = \"$GOOGLE_PROJECT_ID\"" $CONF_FILE || exit $?
	yq e -i "$REPOSITORY_KEY = \"$RESTIC_REPOSITORY\"" $CONF_FILE || exit $?
	yq e -i "$PASSWORD_KEY = \"$RESTIC_PASSWORD\"" $CONF_FILE || exit $?
	yq e -i "$CRON_KEY = \"$BACKUP_JOB_CRON\"" $CONF_FILE || exit $?
	
	if [ ! -z "$JSON_CREDENTIALS_FILE" ]; then
		yq e -i "$JSON_CREDENTIALS_KEY = \"$JSON_CREDENTIALS_FILE\"" $CONF_FILE || exit $?
	fi
	
	if [ ! -z "$GOOGLE_ACCESS_TOKEN" ]; then
		yq e -i "$ACCESS_TOKEN_KEY = \"$GOOGLE_ACCESS_TOKEN\"" $CONF_FILE || exit $?
	fi
	
	if [ ! -z "$BACKUP_JOB_OUTPUT_CMD" ]; then
		yq e -i "$OUTPUT_CMD_KEY = \"$BACKUP_JOB_OUTPUT_CMD\"" $CONF_FILE || exit $?
	fi
	
	if $LOADED_INCLUDES ; then
		for include in $BACKUP_INCLUDES; do
			yq e -i "$INCLUDES_KEY |= . + [\"$include\"]" $CONF_FILE || exit $?
		done
	fi
	
	if $LOADED_EXCLUDES ; then
		for exclude in $BACKUP_EXCLUDES; do
			yq e -i "$EXCLUDES_KEY |= . + [\"$exclude\"]" $CONF_FILE || exit $?
		done
	fi
	
	echo "${LOG_PREFIX}: $CONF_FILE was updated."
}

function create_conf {
	local user_group="$(id -gn)"
	
	eval $SUDO touch $CONF_FILE || exit $?
	eval $SUDO chgrp "$user_group" $CONF_FILE || exit $?
	eval $SUDO chmod ug=rw $CONF_FILE || exit $?
	eval $SUDO chmod o-rwx $CONF_FILE || exit $?
}

function load_conf {
	if [ ! -f "$CONF_FILE" ]; then
		echo "${LOG_PREFIX}: $CONF_FILE does not exist. Creating..."
		create_conf
		echo "${LOG_PREFIX}: $CONF_FILE was created."
	fi
	
	echo "${LOG_PREFIX}: Loading conf file..."
	export GOOGLE_PROJECT_ID="$(get_input "Google Project ID" "$PROJECT_ID_KEY" false false false)"
	
	load_cron_job
	
	load_repository
	load_password
	
	load_credentials
	load_inclusions
	load_exclusions
	echo "${LOG_PREFIX}: $CONF_FILE was loaded."
	
	update_conf
}

function restic_init {
	echo "${LOG_PREFIX}: Initializing restic repository..."
	restic init || exit $?
	echo "${LOG_PREFIX}: init done."
}

function restic_backup {
	echo "${LOG_PREFIX}: Backing up to restic repository..."
	local includes=()
	local excludes=()
	
	for include in $BACKUP_INCLUDES; do
		local includes+=("$include")
	done
	
	for exclude in $BACKUP_EXCLUDES; do
		local excludes+=("-e")
		local excludes+=("$exclude")
	done
	
	local IFS=" "
	restic -v backup \
		-x \
		"${includes[@]}" \
		"${excludes[@]}" \
		|| exit $?
	
	echo "${LOG_PREFIX}: backup done."
}

function add_cron_job {
	echo "${LOG_PREFIX}: Adding cron job..."
	if [ -z "$BACKUP_JOB_OUTPUT_CMD" ]; then
		local cron_str="$BACKUP_JOB_CRON $CRON_CMD"
	else
		local cron_str="$BACKUP_JOB_CRON $CRON_CMD | $BACKUP_JOB_OUTPUT_CMD"
	fi
	
	(eval $SUDO crontab -l 2> /dev/null ; echo "$cron_str") | eval $SUDO crontab - || exit $?
	
	echo "${LOG_PREFIX}: done."
}

function show_cron_job {
	eval $SUDO crontab -l 2> /dev/null | grep "$CRON_CMD"
}

function rm_cron_job {
	echo "${LOG_PREFIX}: Removing cron job..."
	
	eval $SUDO crontab -l 2> /dev/null | grep -v "$CRON_CMD" | eval $SUDO crontab - || exit $?
	
	echo "${LOG_PREFIX}: done."
}

function init {
	echo "${LOG_PREFIX}: init"
	LOG_PREFIX="backup-init"
	
	load_conf
	
	restic_init
	
	local wants_cron_job="$(read_input "Do you want to schedule the backup job now? (Y/n) ")"
	if [[ $wants_cron_job =~ ^[Yy] ]]; then
		add_cron_job
	else
		echo "run '$SCRIPT schedule' to schedule the backup job when ready."
	fi
	
	local wants_initial_backup="$(read_input "Do you want to start the initial backup now? (This will take a lot of time to complete) (Y/n) ")"
	if [[ $wants_initial_backup =~ ^[Yy] ]]; then
		exec 5>&1
		restic_backup 2>&1 | tee >(cat - >&5) | eval $BACKUP_JOB_OUTPUT_CMD || exit $?
	else
		echo "run '$SCRIPT start' when ready to start the initial backup, or wait until backup job runs if one is scheduled."
	fi
}

function start {
	echo "${LOG_PREFIX}: start"
	LOG_PREFIX="backup-start"
	
	load_conf
	
	restic_backup
}

function schedule {
	if [ ! -z "$(show_cron_job)" ]; then
		echo "backup-schedule: error: backup job already exists."  >&2
		exit 3
	fi

	echo "${LOG_PREFIX}: schedule"
	LOG_PREFIX="backup-schedule"
	
	load_conf
	
	add_cron_job
}

function show {
	show_cron_job
}

function unschedule {
	if [ -z "$(show_cron_job)" ]; then
		echo "backup-unschedule: error: backup job doesn't exist."  >&2
		exit 3
	fi
	
	echo "${LOG_PREFIX}: unschedule"
	LOG_PREFIX="backup-unschedule"
	
	rm_cron_job
}

function reschedule {
	if [ -z "$(show_cron_job)" ]; then
		echo "backup-reschedule: error: backup job doesn't exist."  >&2
		exit 3
	fi

	echo "${LOG_PREFIX}: reschedule"
	LOG_PREFIX="backup-reschedule"
	
	load_conf
	
	rm_cron_job
	add_cron_job
}

function conf_path {
	if [ ! -f $CONF_FILE ]; then
		echo "no conf file exists" >&2
		return 1
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
CRON_CMD="$SCRIPT start 2>&1"

ARGS=()
while (( $# )); do
	case $1 in
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
		*)
			ARGS+=($1)
			shift
			;;
	esac
done

COMMAND=${ARGS[0]}
LOG_PREFIX="backup"

case $COMMAND in
	init) 
		init
		;;
	start)
		start
		;;
	schedule)
		schedule
		;;
	show)
		show
		;;
	unschedule)
		unschedule
		;;
	reschedule)
		reschedule
		;;
	*)
		echo "${LOG_PREFIX}: error: \"$COMMAND\" is not a known command."  >&2
		exit 1
esac
