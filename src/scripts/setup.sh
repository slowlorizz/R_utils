#!/bin/bash

#
#
#   Defaulting to Debian 12 / Ubuntu 22 currently
#   Supports RHEL systems and Ubuntu
#

PACKMAN="apt"
LOG_PAD=0
LOG_PADDING=""

DO_UPDATE=1
RS_D_URL="https://download1.rstudio.org/electron/jammy/amd64/rstudio-2023.12.0-369-amd64.deb"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -nu|--no-update)
            DO_UPDATE=0
            shift;;
        -durl|--rstudio-d-url)
            RS_D_URL="${2}"
            shift;;
        *) 
            echo "Unknown parameter passed: $1"; 
            exit 1;;
    esac
    shift
done

function rgb {
    R="${1}"
    G="${2}"
    B="${3}"

    echo "${R};${G};${B}"
}

function get_log_padding {
    PADDING=""

    for (( i=0 ; i<$LOG_PAD ; i++ )); 
    do
        PADDING="${PADDING} |  ";
    done

    echo "${PADDING}"
}

function print_empty_line {
    printf "           ${LOG_PADDING}\n"
}

function log {
    TYPE="${1}"
    MSG="${2}"
    TAG=""
    COLOR=""
    TIMESTAMP=$(date +%T)

    case $TYPE in
        job)
            TAG="#"; COLOR="$(rgb 191 0 230)";
            LOG_PAD=$(($LOG_PAD + 1));
            ;;
        task)
            TAG="*"; COLOR="$(rgb 156 183 214)";
            ;;
        info)
            TAG="?"; COLOR="$(rgb 0 170 255)";
            ;;
        success)
            TAG="+"; COLOR="$(rgb 85 255 0)";
            ;;
        warning)
            TAG="!"; COLOR="$(rgb 255 191 0)";
            ;;
        error)
            TAG="x"; COLOR="$(rgb 255 0 43)";
            ;;
        *)
            TAG="${TYPE}"; COLOR="$(rgb 255 255 255)";
            ;;
    esac

    printf "\033[3m${TIMESTAMP}\033[0m   ${LOG_PADDING}\033[1;38;2;${COLOR}m[${TAG}]\033[0m ${MSG}\n"

    [[ "$TYPE" = "job" ]] && LOG_PADDING=$(get_log_padding)
}

function start_job { log "job" "${1}"; }
function log_task { log "task" "${1}"; }
function log_info { log "info" "${1}"; }
function log_success { log "success" "${1}"; }
function log_warning { log "warning" "${1}"; }
function log_error { log "error" "${1}"; }
function end_job {
    [[ $LOG_PAD -gt 0 ]] && LOG_PAD=$(($LOG_PAD - 1))

    LOG_PADDING=$(get_log_padding)
}

function eval_packman {
    start_job "evaluate the Package-Manager for this system"
    if command -v apt-get &> /dev/null; then
        log_info "found Package-Manager \'apt\'"
        PACKMAN="apt"
    elif command -v dnf &> /dev/null; then
        log_info "found Package-Manager \'dnf\'"
        PACKMAN="dnf"
    elif command -v yum &> /dev/null; then
        log_info "found Package-Manager \'yum\'"
        log_warning "\'yum\' is marked as deprecated" 
        log_task "attempting to install \'dnf\'"
        sudo yum install dnf -y &> /dev/null && {
            log_success "successfully installed \'dnf\'"
            PACKMAN="dnf"
        } || {
            log_error "\'dnf\' could not be installed"
            log_info "fall back to using \'yum\'"
            PACKMAN="yum"
        }
    else
        log_error "Unknown package manager"
        log_warning "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    fi

    end_job
}

function update_packman {
    start_job "Update all Packages to their newest available Version"
    log_task "update all packages"
    sudo $PACKMAN update -y &> /dev/null || {
        log_error "Packages-Update ran into an error";
        log_warning "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    }

    log_task "upgrade all packages"
    sudo $PACKMAN upgrade -y &> /dev/null || {
        log_error "Packages-Upgrade ran into an error";
        log_task "Attempting to fix Error with \'--fix-broken install\'"

        sudo $PACKMAN --fix-broken install -y &> /dev/null || {
            printf "\033[0m"
            log_error "issues could not be solved"
            log_warning "Setup ran into a Fatal Error --> exiting with code 1"
            exit 1
        }

        sudo $PACKMAN upgrade -y &> /dev/null || {
            log_error "Packages-Upgrade ran into an error";
            log_warning "Setup ran into a Fatal Error --> exiting with code 1"
            exit 1
        }
    }

    log_success "All Packages are now on the newest available Version"

    end_job
}

function check_R_installation {
    VAL=1
    start_job "Check if R is installed"
    
    R --version &> /dev/null && { 
        log_success "R is installed"
        VAL=0
    } || {
        log_warning "R is not installed"
        VAL=1
    }

    end_job

    return $VAL
}

function install_R {
    PKG_NAME=""
    start_job "installing R-Package"
    log_task "download Package"

    case $PACKMAN in
        dnf|yum)
            PKG_NAME="R"
            ;;
        apt)
            PKG_NAME="r-base"
            ;;
    esac

    sudo $PACKMAN install $PKG_NAME -y &> /dev/null || {
        log_error "Could not install R-Package"
        log_warning "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    }

    log_success "Successfully installed R-Package"

    check_R_installation || {
        log_warning "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    }

    end_job
}

function check_Rstudio_installation {
    start_job "Check if rstudio-server is installed"
    systemctl status rstudio-server &> /dev/null
    VAL=$?

    [[ $VAL -eq 0 ]] && log_success "rstudio-server service exists" || log_warning "rstudio-server service does not exist"

    return $VAL

    end_job
}

function install_Rstudio {
    start_job "Install R-Studio"

    FILE_TYPE="deb"
    (echo "$RS_D_URL" | grep -Eq ^.*\.deb$) && FILE_TYPE="deb" || FILE_TYPE="rpm"

    log_info "Package Recognized as .${FILE_TYPE}"

    log_task "Downloading Package from URL: ${RS_D_URL} to /tmp/rstudio_installer.${FILE_TYPE}"
    wget -O "/tmp/rstudio_installer.${FILE_TYPE}" $RS_D_URL &> /dev/null || {
        log_error "Error Occured while downloading Package from URL: ${RS_D_URL}"
        log_warning "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    } 

    log_success "Successfully downloaded Package"

    log_task "install R-Studio dependencies"
    sudo $PACKMAN install libssl-dev libclang-dev libxkbcommon-x11-0 -y &> /dev/null || {
        log_error "Error Occured while installing R-Studio dependencies"
        log_warning "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    }

    log_task "installing Package"
    [[ "$FILE_TYPE" == "deb" ]] && {
        sudo dpkg -i /tmp/rstudio_installer.deb &> /dev/null || {
            log_error "Package could not be installed"
            log_warning "Setup ran into a Fatal Error --> exiting with code 1"
            exit 1
        }

        
    } || {
        sudo rpm -ivh /tmp/rstudio_installer.rpm &> /dev/null || {
            log_error "Package could not be installed"
            log_warning "Setup ran into a Fatal Error --> exiting with code 1"
            exit 1
        }
    }

    log_success "Installed Package"

    log_task "verify Package installation"
    check_Rstudio_installation || {
        log_error "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    }

    start_job "Install and configure Firewall"
    [[ "$FILE_TYPE" == "deb" ]] && {
        log_task "disable Firewall entirely"
        sudo ufw disable &> /dev/null || {
            log_error "Setup ran into a Fatal Error --> exiting with code 1"
            exit 1
        }

    } || {
        log_task "Allow incomming requests from PORT: 8787/tcp"
        sudo firewall-cmd --permanent --zone=public --add-port=8787/tcp &> /dev/null || {
            log_error "Setup ran into a Fatal Error --> exiting with code 1"
            exit 1
        }

        log_task "Reload Firewall"
        sudo firewall-cmd –reload &> /dev/null || {
            log_error "Could not reload firewall"
        }
    }

    log_success "Firewall Configured"

    end_job
    end_job
}

function start_Rstudio_service {
    log_task "Starting RStudio-Server Service"
    sudo systemctl start rstudio-server &> /dev/null || {
        log_error "Encounterd Non 0 Return-Code while starting \'rstudio-server\' service"
        log_warning "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    }
}

function enable_Rstudio_service {
    log_task "Enabling RStudio-Server Service"
    sudo systemctl enable rstudio-server &> /dev/null || {
        log_error "Encounterd Non 0 Return-Code while enabling \'rstudio-server\' service"
        log_warning "Setup ran into a Fatal Error --> exiting with code 1"
        exit 1
    }
}

function get_Rstudio_service_status {
    log_task "Check status of RStudio-Server Service"
    sudo systemctl status rstudio-server || log_error "Encounterd Non 0 Return-Code while receiving the status of \'rstudio-server\' service"
}


function check_dependencies {
    start_job "Ensure all Dependencies are available"
    log_task "checking the R Language Dependency"
    check_R_installation || {
        log_warning "R Language Dependency did not fullfill Requirements"
        log_task "trying to solve R Language issue"
        install_R
    }

    update_packman

    log_task "checking the R-Studio Dependency"
    check_Rstudio_installation || {
        log_warning "R-Studio Dependency did not fullfill Requirements"
        log_task "trying to solve R-Studio issue"
        install_Rstudio
    }

    log_success "All Dependencies are installed and available"

    update_packman

    end_job
}


########################################################################


printf "\n"
eval_packman
[[ $DO_UPDATE -eq 1 ]] && update_packman

check_dependencies
start_Rstudio_service
enable_Rstudio_service

printf "\n------------------------------------\nService Available at: http://<IP or FQDN>:8787\n"


printf "\n"