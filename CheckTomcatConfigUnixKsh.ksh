#!/bin/ksh
# CheckTomcatInstallUnixKsh.sh
# Check if Apache Tomcat is installed on AIX, Linux, or SunOS

# Detect OS type and release
OS=$(uname)
HOSTNAME=$(uname -n)
DATE=$(date +"%Y-%m-%d %H:%M:%S")

case ${OS} in
AIX)
    OS_TYPE=${OS}
    OS_RELEASE="$(uname -v).$(uname -r)"
    OPTION=k
    ;;
Linux)
    OS_TYPE=${OS}
    grep Ootpa /etc/redhat-release > /dev/null 2>&1
    if [[ $? = 0 ]]; then
        OS_RELEASE=$(cat /etc/redhat-release | awk '{ print $6 }')
    else
        OS_RELEASE=$(cat /etc/redhat-release | awk '{ print $7 }')
    fi
    OPTION=Ph
    ;;
SunOS)
    head -1 /etc/release | grep Oracle > /dev/null 2>&1
    if [[ $? = 0 ]]; then
        OS_TYPE=$(head -1 /etc/release | awk '{ print $1, $2 }')
        OS_RELEASE=$(head -1 /etc/release | awk '{ print $3 }')
    else
        OS_TYPE=$(head -1 /etc/release | awk '{ print $1 }')
        OS_RELEASE=$(head -1 /etc/release | awk '{ print $2 }')
    fi
    OPTION=k
    ;;
*)
    OS_TYPE="Unknown"
    OS_RELEASE="Unknown"
    print "${DATE},${HOSTNAME},${OS_TYPE},${OS_RELEASE},NO"
    exit 1
    ;;
esac

# Function to detect Tomcat path
get_tomcat_config_path() {
    if [[ -n "${CATALINA_HOME}" && -d "${CATALINA_HOME}/conf" && -f "${CATALINA_HOME}/conf/server.xml" ]]; then
        print "${CATALINA_HOME}/conf"
        return
    fi
    for path in \
        "/opt/tomcat/conf" \
        "/usr/local/tomcat/conf" \
        "/var/lib/tomcat7/conf" \
        "/var/lib/tomcat8/conf" \
        "/var/lib/tomcat9/conf" \
        "/var/lib/tomcat10/conf" \
        "/usr/share/tomcat7/conf" \
        "/usr/share/tomcat8/conf" \
        "/usr/share/tomcat9/conf" \
        "/usr/share/tomcat10/conf"; do
        if [[ -d "${path}" && -f "${path}/server.xml" ]]; then
            print "${path}"
            return
        fi
    done
    print ""
}

# Main check
if [[ $(id -u) -ne 0 ]]; then
    print "${DATE},${HOSTNAME},${OS_TYPE},${OS_RELEASE},NO"
    exit 1
fi

conf_path=$(get_tomcat_config_path)
if [[ -n "$conf_path" ]]; then
    print "${DATE},${HOSTNAME},${OS_TYPE},${OS_RELEASE},YES"
else
    print "${DATE},${HOSTNAME},${OS_TYPE},${OS_RELEASE},NO"
fi