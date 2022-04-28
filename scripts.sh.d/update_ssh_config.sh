#! /bin/bash

# Add running Vagrant servers to ~/.ssh/config, so that they can be
# accessed with 'ssh $server_name' or from inside Emacs.
# The ~/.ssh/config entries for Vagrant virtual machines are held
# inside a block, which is delimited with $start_line and $end_line.


#Debugging variables
#set -e
#set -x
debug_flag=1

# GLOBAL VARIABLES
# Define start and end line strings for the ~/.ssh/config block
# managed by this script.
start_line="#Vagrant Projects START"
end_line="#Vagrant Projects END"
# User's SSH config file.
config_file="$HOME/.ssh/config"

# FUNCTIONS
die(){
# Exit on fail.
  local error_msg="${*}"
  echo -e "Error in '${0##*/}':\n $error_msg" >&2
  echo "Exiting $0." >&2
  exit 1
}

debug(){
# Print debug messages if in debug mode.
  if [[ debug_flag -eq 1 ]]; then
    local debug_message="${*}"
    echo -e "debug: $debug_message" >&2
  fi
}


# Search for a config backup created less than 60 minutes ago.
config_dir="$(dirname "${config_file}")"
N_backups_last_hour=$( find "${config_dir}" \
                            -type f \
                            -name "config.bak*" \
                            -mmin -60 \
                            -print \
                         | wc -l )
debug "ssh config backups in the last hour: ${N_backups_last_hour}."

# Backup "${config_file}" if the last backup is older than 1 hour.
# TODO: Only backup if the config file differs from the last backup.
if [[ N_backups_last_hour -lt 1 ]]; then
  debug "Backing up ssh config."
  cp "${config_file}" "${config_file}.bak.$(date +%F+%T)" \
    || die "Failed to backup '${config_file}'."
else
  debug "${config_file} already backed up this hour."
fi

# Create an array with names of running servers.
unset servers_array
while read -r line; do
  # Check if the machine got a name instead of the original 'default'.
  server_name="$(awk '{print $2}' <<< "${line}")"
  if [[ "${server_name}" == "default" ]]; then
    # If the name = 'default', we use the dirname as the name.
    server_name="$(awk '{ print $5 }' <<< "${line}")"
    server_name="${server_name##*/}"
  fi
  servers_array+=( "${server_name}" )
done < <( vagrant global-status --prune | grep running )
debug "Servers list: ${servers_array[*]}."

# Check if the config file exists and is not empty.
if [[ ! -s "${config_file}" ]]; then
  debug "${config_file} is empty, but this script should still work."
fi
   
# Check if there is at most one of START and STOP lines.
for line in "$start_line" "$end_line"; do
  how_many_lines="$(grep -c "$line" "${config_file}")"
  if [[ $how_many_lines -gt 1 ]]; then
    die "There are ${how_many_lines} of ${line}."
  fi
done

# Check if script is run for the first time
# (by checking if $start_line exists in the file)
if [[ how_many_lines -eq 0 ]]; then
  echo "Welcome aboard!"
  where_it_started=$(sed -n "$ =" "${config_file}")
  if [[ where_it_started -lt 1 ]]; then
    where_it_started=1
  fi
else
  # Remember where_it_started (the Vagrant block in "${config_file}")
  where_it_started=$(sed -n  "/$start_line/ =" "${config_file}")
  debug "Block starts at: $where_it_started"
fi
# Remove old entries.
sed -i "/$start_line/,/$end_line/ d" "${config_file}" 

# Use tempfile to hold wagrant output to be able to catch errors when
# calling the wagrant script.
wagrant_output=$(mktemp) || die "Failed to create a tempfile."
trap 'rm -f ${wagrant_output}; exit' EXIT

# Add new entries to .ssh/config and put it in a temp file.
{
  # This will "save" the content of "${config_file}"
  head -"$((where_it_started - 1))" "${config_file}"
  echo "$start_line"
  for sys in "${servers_array[@]}"
  do
    # Run wagrant outside a pipe to allow using || to catch errors.
    wagrant status "$sys" > "$wagrant_output" \
	    || die "Failed to run 'wagrant status $sys'"
    # Do nothing if VM's status is not "running"
    if [[ $(grep -c running "$wagrant_output") -lt 1 ]]; then
	    continue
    fi
    # Use wagrant to print the VM-specific ssh config
      printf "$( wagrant ssh-config "$sys" \
      	          | sed "s/Host default/Host $sys/" )\n\n"
  done
  echo "$end_line"
  tail -n +${where_it_started} "${config_file}"
} > "${config_file}-tmp"

mv "${config_file}-tmp" "${config_file}" \
  || die "Failed to move temp conf file onto ${config_file}."

# Finished successfully :)
exit 0
