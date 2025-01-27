add_gpg_conf_option() {
        local conffile=$1; shift
        if ! grep -q "^[[:space:]#]*$*\([[:space:]].*\)*$" "$conffile" &>/dev/null; then
                printf '%s\n' "$*" >> "$conffile"
        fi
}
initialize() {
        local conffile keyserv
        # Check for simple existence rather than for a directory as someone
        # may want to use a symlink here
        [[ -e ${PACMAN_KEYRING_DIR} ]] || mkdir -p -m 755 "${PACMAN_KEYRING_DIR}"

        # keyring files
        [[ -f ${PACMAN_KEYRING_DIR}/pubring.gpg ]] || touch ${PACMAN_KEYRING_DIR}/pubring.gpg
        [[ -f ${PACMAN_KEYRING_DIR}/secring.gpg ]] || touch ${PACMAN_KEYRING_DIR}/secring.gpg
        [[ -f ${PACMAN_KEYRING_DIR}/trustdb.gpg ]] || "${GPG_PACMAN[@]}" --update-trustdb
        chmod 644 ${PACMAN_KEYRING_DIR}/{pubring,trustdb}.gpg
        chmod 600 ${PACMAN_KEYRING_DIR}/secring.gpg

        # gpg.conf
        conffile="${PACMAN_KEYRING_DIR}/gpg.conf"
        [[ -f $conffile ]] || touch "$conffile"
        chmod 644 "$conffile"
        add_gpg_conf_option "$conffile" 'no-greeting'
        add_gpg_conf_option "$conffile" 'no-permission-warning'
        add_gpg_conf_option "$conffile" 'keyserver-options' 'timeout=10'
        add_gpg_conf_option "$conffile" 'keyserver-options' 'import-clean'

        local gpg_ver=$(gpg --version | awk '{print $3; exit}')
        if (( $(vercmp "$gpg_ver" 2.2.17) >= 0 )); then
                add_gpg_conf_option "$conffile" 'keyserver-options' 'no-self-sigs-only'
        fi

        # gpg-agent.conf
        agent_conffile="${PACMAN_KEYRING_DIR}/gpg-agent.conf"
        [[ -f $agent_conffile ]] || touch "$agent_conffile"
        chmod 644 "$agent_conffile"
        add_gpg_conf_option "$agent_conffile" 'disable-scdaemon'

        # set up a private signing key (if none available)
        if [[ $(secret_keys_available) -lt 1 ]]; then
                generate_master_key
                UPDATEDB=1
        fi
}
secret_keys_available() {
        "${GPG_PACMAN[@]}" -K --with-colons | wc -l
}
generate_master_key() {
        # Generate the master key, which will be in both pubring and secring

        "${GPG_PACMAN[@]}" --gen-key --batch <<-NEOF
%echo Generating pacman keyring master key...
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: Pacman Keyring Master Key
Name-Email: pacman@localhost
Expire-Date: 0
%no-protection
%commit
%echo Done
NEOF
}
updatedb() {
        if ! "${GPG_PACMAN[@]}" --batch --check-trustdb ; then
                echo "$(gettext "Trust database could not be updated.")"
                exit 1
        fi
}
PACMAN_KEYRING_DIR=$PWD/test
initialize
updatedb
