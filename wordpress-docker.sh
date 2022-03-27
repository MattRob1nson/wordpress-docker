#!/bin/bash

## Globals #####################################################################

PWD="$( cd "$(dirname "$0")" || exit >/dev/null 2>&1 ; pwd -P )"

DOCKER_PROXY_PROJECT="wordpress-docker"
DOCKER_PROXY_COMPOSE_PATH="${PWD}"/proxy/docker-compose.yml

SITE_FILES_DIRECTORY="${PWD}"/sites/site-files

declare -a PROXY_CONTAINER_NAMES=("${DOCKER_PROXY_PROJECT}_reverse-proxy_1" \
                                  "${DOCKER_PROXY_PROJECT}_docker-gen_1" \
                                  "${DOCKER_PROXY_PROJECT}_letsencrypt_1")

declare -a ACTIONS=("Start proxy" \
                    "Stop proxy" \
                    "Restart proxy" \
                    "Start all sites (will also start proxy)" \
                    "Stop all sites" \
                    "Restart all sites (will also start proxy)" \
                    "Specify specific site (will also start proxy)" \
                    "Add new site")

declare -a SITE_ACTIONS=("Start site" \
                         "Stop site" \
                         "Restart site")

declare -a SITES=()
for site in "${SITE_FILES_DIRECTORY}"/*/; do
    site="${site%"${site##*[!/]}"}" # Remove trailing slash.
    site="${site##*/}" # Remove everything before last slash.
    SITES+=("${site}")
done


## Helper Functions ############################################################

function ensureProxyRunning {
    docker-compose -f "${DOCKER_PROXY_COMPOSE_PATH}" -p "${DOCKER_PROXY_PROJECT}" up --build -d
}

function do_select() {
    local select_message; select_message=${1}
    local options; options=("${@:2}");

    local PS3="${select_message}"
    local selected_option;
    while [ -z "${selected_option}" ]; do
        select site in "${options[@]}"; do
            selected_option=${site}
            break
        done
    done
    echo "${selected_option}"
}

function print_spacer {
    echo "--------------------------------------------------------------------------------"
}

function isRunning() {
    local docker_container_name; docker_container_name=${1}
    [[ $(docker ps -q -f status=running -f name="${docker_container_name}") ]]
}

function run_proxy_docker_command() {
    local docker_command_options; docker_command_options=${1}
    docker-compose -f "${DOCKER_PROXY_COMPOSE_PATH}" -p "${DOCKER_PROXY_PROJECT}" ${docker_command_options}
}

function run_site_docker_command() {
    local site_domain; site_domain=${1}
    local docker_command_options; docker_command_options=${2}
    PUID="$(id -u)" PGID="$(id -g)" SITE_DOMAIN="${site_domain}" SITE_DIRECTORY="${PWD}"/sites/site-files/"${site_domain}" \
        docker-compose -f "${PWD}"/sites/docker-compose.yml \
                       --env-file "${PWD}"/sites/site-files/"${site_domain}"/.env \
                       -p "${DOCKER_PROXY_PROJECT}-${site_domain}" \
                       ${docker_command_options}
}

function generate_password {
    echo "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 50; echo '')"
}

function add_new_site() {
    local site_domain; site_domain=${1}
    local letsencrypt_email; letsencrypt_email=${2}

    local site_directory; site_directory="${PWD}/sites/site-files/${site_domain}"
    local env_file_path; env_file_path="${site_directory}/.env"
    local nginx_config_path; nginx_config_path="${site_directory}/nginx-conf/default.conf"
    local web_files_path; web_files_path="${site_directory}/www"

    cp -r "${PWD}"/sites/example.com "${site_directory}"

    sed -i -e 's/<DOMAIN>/'"${site_domain}"'/g' "${env_file_path}"
    sed -i -e 's/<LETSENCRYPT_EMAIL>/'"${letsencrypt_email}"'/g' "${env_file_path}"
    sed -i -e 's/<MYSQL_PASSWORD>/'"$(generate_password)"'/g' "${env_file_path}"
    sed -i -e 's/<MYSQL_ROOT_PASSWORD>/'"$(generate_password)"'/g'  "${env_file_path}"
    sed -i -e 's/<DOMAIN>/'"${site_domain}"'/g' "${nginx_config_path}"

    cd "${web_files_path}" \
        && wget https://wordpress.org/latest.zip \
        && unzip latest.zip -d "${web_files_path}" \
        && mv wordpress/* . \
        && rm latest.zip \
        && rmdir wordpress
}


## Main Functions ##############################################################

function select_action {
    local IFS=$'\n'
    do_select "Select action #: " "${ACTIONS[@]}"
}

function select_site_action {
    local IFS=$'\n'
    do_select "Select site action #: " "${SITE_ACTIONS[@]}"
}

function select_site {
    local IFS=$'\n'
    do_select "Select site #: " "${SITES[@]}"
}

function start_site() {
    local site_domain; site_domain=${1}
    run_site_docker_command "${site_domain}" "up --build -d"
}

function stop_site() {
    local site_domain; site_domain=${1}
    run_site_docker_command "${site_domain}" "down"
}

function start_all_sites {
    for site_domain in "${SITES[@]}"; do
        start_site "${site_domain}"
    done
}

function stop_all_sites {
    for site_domain in "${SITES[@]}"; do
        stop_site "${site_domain}"
    done
}

function print_header() {
    local header_text; header_text=${1}

    print_spacer
    echo "${header_text}"
    print_spacer
}

function print_selected_operation() {
    local action; action=${1}
    local site; site=${2}

    print_spacer
    echo "Performing action '${action}'$([[ ! -z "${site}" ]] && echo " for '${site}'")"
    print_spacer
}

function proxy_is_running {
    for proxy_container_name in "${PROXY_CONTAINER_NAMES[@]}"; do
        if ! isRunning "${proxy_container_name}"; then
            return 1
        fi
    done
    return 0
}

function site_exists() {
    local site_domain; site_domain=${1}
    [ -d "${SITE_FILES_DIRECTORY}/${site_domain}" ]
}

function start_proxy {
    run_proxy_docker_command "up --build -d"
}

function stop_proxy {
    run_proxy_docker_command "down"
}

function restart_proxy {
    stop_proxy
    start_proxy
}

function ensure_proxy_running {
    print_header "Ensuring proxy is running"
    if proxy_is_running; then
        echo "Proxy is running"
    else
        echo "Proxy is not running, restarting..."
        restart_proxy
        echo "Proxy is running"
    fi
}

function at_least_one_site_exists {
    ls ${SITE_FILES_DIRECTORY}/*/ &>/dev/null
}

function create_new_site {
    read -p "Enter domain for new site (e.g. example.com): " site_domain
    if site_exists "${site_domain}"; then
        echo "Site with domain '${site_domain}' already exists"
    else
        read -p "Enter an email address for LetsEncrypt notifications (e.g. name@gmail.com): " letsencrypt_email
        add_new_site "${site_domain}" "${letsencrypt_email}"
        echo "Added site '${site_domain}' using '${letsencrypt_email}' as the email for LetsEncrypt notifications"
    fi
    echo " - See site files at ${SITE_FILES_DIRECTORY}/${site_domain}"
}


## Entrypoint ##################################################################

which unzip >/dev/null 2>/dev/null || (echo "Installing required dependency (unzip). You may need to enter your sudo password" \
                                       && sudo apt-get -qq -y install unzip)

if at_least_one_site_exists; then
    print_header "Select action"
    action=$(select_action)

    print_selected_operation "${action}"

    if [ "${action}" == "${ACTIONS[0]}" ]; then # Start proxy
        start_proxy
    elif [ "${action}" == "${ACTIONS[1]}" ]; then # Stop proxy
        stop_proxy
    elif [ "${action}" == "${ACTIONS[2]}" ]; then # Restart proxy
        restart_proxy
    elif [ "${action}" == "${ACTIONS[3]}" ]; then # Start all sites
        ensure_proxy_running
        start_all_sites
    elif [ "${action}" == "${ACTIONS[4]}" ]; then # Stop all sites
        stop_all_sites
    elif [ "${action}" == "${ACTIONS[5]}" ]; then # Restart all sites
        ensure_proxy_running
        stop_all_sites
        start_all_sites
    elif [ "${action}" == "${ACTIONS[6]}" ]; then # Specify specific site
        ensure_proxy_running
        print_header "Select site"
        site=$(select_site)
        print_header "Select site action"
        site_action=$(select_site_action)

        print_selected_operation "${site_action}" "${site}"
        if [ "${site_action}" == "${SITE_ACTIONS[0]}" ]; then # Start site
            start_site "${site}"
        elif [ "${site_action}" == "${SITE_ACTIONS[1]}" ]; then # Stop site
            stop_site "${site}"
        else # Restart site
            stop_site "${site}"
            start_site "${site}"
        fi
    else # Add new site
        create_new_site
    fi
else
    print_header "First run"
    echo "As this is the first run, you must create at least one site"
    create_new_site
fi
