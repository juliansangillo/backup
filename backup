#! /bin/bash

COMMAND=$1

CONF_FILE=backup.conf
PROJECT_ID_KEY=".backup.google.project-id"
JSON_CREDENTIALS_KEY=".backup.google.credentials"
ACCESS_TOKEN_KEY=".backup.google.access-token"
INCLUDES_KEY=".backup.includes"
INCLUDES_ARR_KEY=".backup.includes[]"
EXCLUDES_KEY=".backup.excludes"
EXCLUDES_ARR_KEY=".backup.excludes[]"

YQ_MAJOR_VERSION=4

IFS=$'\n'

if [ $EUID -ne 0 ]; then
    SUDO=sudo
fi

function get_input {
	local input="$1"
	local expression="$2"
	local optional=$3
	local silent=$4
	local readline=$5
	
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
		read ${flags[@]} -p "Please enter your $input: " result
	fi
	
	echo "$result"
}

function load_credentials {
	local credentials_file_input="Google Credentials File (json)"
	local access_token_input="Google Access Token"

	export JSON_CREDENTIALS_FILE="$(get_input "$credentials_file_input" "$JSON_CREDENTIALS_KEY" true false false)"
	export GOOGLE_APPLICATION_CREDENTIALS="`eval echo ${JSON_CREDENTIALS_FILE//>}`"
	if [[ -z "$GOOGLE_APPLICATION_CREDENTIALS" || ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
		if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
			echo "${LOG_PREFIX}: No credentials provided."
		else
			echo "${LOG_PREFIX}: Credentials file '$GOOGLE_APPLICATION_CREDENTIALS' does not exist."
		fi
		
		read -p "Do you have a JSON Credentials file? (Y/n) " has_credentials
		if [[ $has_credentials =~ ^[Yy] ]]; then
			export JSON_CREDENTIALS_FILE="$(get_input "$credentials_file_input" "$JSON_CREDENTIALS_KEY" false false true)"
			export GOOGLE_APPLICATION_CREDENTIALS="`eval echo ${JSON_CREDENTIALS_FILE//>}`"
			until [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; do
				echo "'$GOOGLE_APPLICATION_CREDENTIALS' does not exist. Verify that the provided path is correct and try again."
				read -e -p "Please enter your ${credentials_file_input}:" JSON_CREDENTIALS_FILE
				export JSON_CREDENTIALS_FILE
				export GOOGLE_APPLICATION_CREDENTIALS="`eval echo ${JSON_CREDENTIALS_FILE//>}`"
			done
			
			export GOOGLE_ACCESS_TOKEN="$(get_input "$access_token_input" "$ACCESS_TOKEN_KEY" true false false)"
		fi
		
		if [[ ! $has_credentials =~ ^[Yy] ]]; then
			echo "${LOG_PREFIX}: Credentials file does not exist. Need access token."
			export JSON_CREDENTIALS_FILE=""
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
		echo -e "\n\e[33mWARNING: If no includes are provided, then ' / ' will be backed up.\e[0m\n" >&2
		read -p "Do you want to provide file and/or directory inclusions? (Y/n) " want_includes
		if [[ $want_includes =~ ^[Yy] ]]; then
			echo -e "\nNOTE: Only the current filesystem is backed up by default. Attached filesystems will not be backed up."
			echo -e "This is including but not limited to attached media, virtual filesystems, and other partitions."
			echo -e "If you want these to be backed up as well, their directories must be manually included.\n"
			
			echo "Please enter each inclusion below. (Press enter again when finished)"
			
			local includes=()
			local include="undefined"
			until [ -z "$include" ]; do
				read -p 'Enter included file or directory: ' -e include
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
		read -p "Do you want to provide exclusions? (Y/n) " want_excludes
		if [[ $want_excludes =~ ^[Yy] ]]; then
			echo -e "\nNOTE: Exclusions are entered as regex patterns. Any file path matching at least one pattern will not be backed up.\n"
			
			echo "Please enter each exclusion below. (Press enter again when finished)"
			
			local excludes=()
			local exclude="undefined"
			until [ -z "$exclude" ]; do
				read -p 'Enter exclude pattern: ' -e exclude
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
	
	if [ ! -z "$JSON_CREDENTIALS_FILE" ]; then
		yq e -i "$JSON_CREDENTIALS_KEY = \"$JSON_CREDENTIALS_FILE\"" $CONF_FILE || exit $?
	fi
	
	if [ ! -z "$GOOGLE_ACCESS_TOKEN" ]; then
		yq e -i "$ACCESS_TOKEN_KEY = \"$GOOGLE_ACCESS_TOKEN\"" $CONF_FILE || exit $?
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
	
	$SUDO touch $CONF_FILE || exit $?
	$SUDO chgrp "$user_group" $CONF_FILE || exit $?
	$SUDO chmod ug=rw $CONF_FILE || exit $?
	$SUDO chmod o-rwx $CONF_FILE || exit $?
}

function load_conf {
	if [ ! -f "$CONF_FILE" ]; then
		echo "${LOG_PREFIX}: $CONF_FILE does not exist. Creating..."
		create_conf
		echo "${LOG_PREFIX}: $CONF_FILE was created."
	fi
	
	export GOOGLE_PROJECT_ID="$(get_input "Google Project ID" "$PROJECT_ID_KEY" false false false)"
	
	load_credentials
	load_inclusions
	load_exclusions
	
	update_conf
}

function needs_updating {
	local command=$1
	local major_version=$2
	local latest_version=$3
	local current_version=$4
	
	local IFS='.'
	read -r -a latest_array <<< "$latest_version"
	read -r -a current_array <<< "$current_version"
	
	needs_updating=false
	if [ ${current_array[0]} -gt $major_version ]; then
		echo -e "\e[33mWARNING: current $command version is greater than '$major_version.x'. Only $major_version.x versions are\e[0m" >&2
		echo -e "\e[33msupported at this time. This may cause instability.\e[0m\n" >&2
	else
		for i in "${!latest_array[@]}"; do
			if [ ${latest_array[i]} -gt ${current_array[i]} ]; then 
				needs_updating=true
				break
			fi
		done
	fi
	
	echo $needs_updating
}

function yq_needs_updating {
	local latest="$(curl -s -X GET -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/mikefarah/yq/releases | grep -w tag_name | sed -rn "s/.*(${YQ_MAJOR_VERSION}\.[0-9]+\.[0-9]+).*/\1/p" | head -n 1)"
	local current="$(yq -V | sed -rn "s/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p")"
	
	echo $(needs_updating yq $YQ_MAJOR_VERSION $latest $current)
}

function install_yq {
	local latest_version="$(curl -s -X GET -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/mikefarah/yq/releases | grep -w tag_name | sed -rn "s/.*(${YQ_MAJOR_VERSION}\.[0-9]+\.[0-9]+).*/\1/p" | head -n 1)"
	
	$SUDO wget https://github.com/mikefarah/yq/releases/download/v${latest_version}/yq_linux_amd64.tar.gz -O - | tar xz && mv yq_linux_amd64 /usr/bin/yq || exit $?
	./install-man-page.sh
	rm install-man-page.sh
	rm yq.1
}

function update_yq {
	install_yq
}

function check {
	local command=$1
	
	if ! command -v $command	&> /dev/null ; then
		echo "${LOG_PREFIX}: $command could not be found. Installing..."
		install_${command}
		echo "${LOG_PREFIX}: $command is now installed."
	elif "$(${command}_needs_updating)" ; then
		echo "${LOG_PREFIX}: $command out of date. Updating..."
		update_${command}
		echo "${LOG_PREFIX}: $command is now updated."
	else
		echo "${LOG_PREFIX}: $command already exists and is up-to-date."
	fi
}

function init {
	echo "${LOG_PREFIX}: init"
	export LOG_PREFIX="backup-init"

	#check restic
	check yq
	
	load_conf
	
	echo "GOOGLE_PROJECT_ID = $GOOGLE_PROJECT_ID"
	echo "JSON_CREDENTIALS_FILE = $JSON_CREDENTIALS_FILE"
	echo "GOOGLE_APPLICATION_CREDENTIALS = $GOOGLE_APPLICATION_CREDENTIALS"
	echo "GOOGLE_ACCESS_TOKEN = $GOOGLE_ACCESS_TOKEN"
	echo "BACKUP_INCLUDES = $BACKUP_INCLUDES"
	echo "BACKUP_EXCLUDES = $BACKUP_EXCLUDES"
}

export LOG_PREFIX="backup"

case $COMMAND in
	init) 
		init
		;;
	*)
		echo "${LOG_PREFIX}: error: \"$COMMAND\" is not a known command."  >&2
		exit 1
esac
