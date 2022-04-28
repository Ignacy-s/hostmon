#!/bin/bash
# Script helping with automating of Icinga deployment v3.
#
# Substitute placeholder values inside config files with secrets.

# $1 is the root of the config directory (originally /etc/icingaweb2).

while read -r -d $'\0' ini_file; do
  while read -r line; do
    var_name="${line%%=*}"
    var_content="${line#*\"}"
    var_content="${var_content%\"}"
    var_placeholder="${var_name}_placeholder"

    if grep --silent "${var_placeholder}" "${ini_file}" ; then
      sed -i "s/${var_placeholder}/${var_content}/"\
	  "${ini_file}"
      echo "Replaced ${var_name} in ${ini_file}."
    fi
  done < /vagrant/secrets
done < <(find "${1:-/etc/icingaweb2/}" -type f -print0)
exit 0
