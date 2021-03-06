#!/bin/bash
# Script requires that test environment is created already

BASEDIR=`dirname $0`
# Colors
green='\033[0;32m'
light_green='\033[1;32m'
red='\033[1;31m'
nc='\033[0m' # No Color

usage="Script for starting ODL tests against OPNFV instalation. 
Tests to be executed are specified in test_list.txt file.
Make sure you created python virtualenv (create_env.sh script) before execute this.

usage:
[var=value] ./$(basename "$0") [-h]

where:
    -h     show this help text
    var    one of the following: ODL_IP, ODL_PORT, PASS, NEUTRON_IP
    value  new value for var

example:
    ODL_IP=oscontrol1 ODL_PORT=8080 ./$(basename "$0")"

while getopts ':h' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done

echo -e "${green}Current environment parameters for ODL suite.${nc}"
# Following vars might be also specified as CLI params
set -x
ODL_IP=${ODL_IP:-'10.60.17.66'}
ODL_PORT=${ODL_PORT:-8081}
PASS=${PASS:-'admin'}
NEUTRON_IP=${NEUTRON_IP:-10.60.17.66}
MININET_IP=${MININET_IP:-'none'}
MININET_USER=${MININET_USER:-'mininet'}
USER_HOME=${USER_HOME:-$HOME}
set +x
    

function clone_odl_tests()
{
    echo -e "${green}Cloning ODL integration git repo.${nc}"
    if [ -d ${BASEDIR}/integration ]; then
        cd ${BASEDIR}/integration
        git checkout -- .
        git pull
        cd -
    else
        git clone https://github.com/opendaylight/integration.git ${BASEDIR}/integration
    fi
}

function modify_odl_tests()
{
    # Change openstack password for admin tenant in neutron suite
    sed -i "s/\"password\": \"admin\"/\"password\": \"${PASS}\"/" \
           ${BASEDIR}/integration/test/csit/suites/openstack/neutron/__init__.robot    
    
    # add custom tests to suite
    echo -e "${green}Copy custom tests to suite.${nc}"
    cp -vf $BASEDIR/custom_tests/neutron/* $BASEDIR/integration/test/csit/suites/openstack/neutron/

    # Start suite keyword is not used in neutron test (is it bug?)
    sed -i "/\*\*\* Settings \*\*\*/a Suite Setup       Start Suite" \
           $BASEDIR/integration/test/csit/suites/openstack/neutron/__init__.robot
}

function execute_odl_tests()
{
    # List of tests are specified in test_list.txt
    # those are relative paths to test directories from integartion suite
    export no_proxy=$ODL_IP,$NEUTRON_IP
    echo -e "${green}Executing chosen tests:${nc}"
    test_num=0
    while read line
    do
        # skip comments
        [[ ${line:0:1} == "#" ]] && continue
        # skip empty lines
        [[ -z "${line}" ]] && continue
    
        ((test_num++))
        echo -e "${light_green}Starting test: $line ${nc}"
        
        pybot -v OPENSTACK:${NEUTRON_IP} \
	      -v PORT:${ODL_PORT} \
              -v CONTROLLER:${ODL_IP} \
              -v USER_HOME:${USER_HOME} \
              -v MININET:${MININET_IP} \
	      -v MININET_USER:${MININET_USER} ${BASEDIR}/$line
        
        mkdir -p $BASEDIR/logs/${test_num}
        mv log.html $BASEDIR/logs/${test_num}/
        mv report.html $BASEDIR/logs/${test_num}/
        mv output.xml $BASEDIR/logs/${test_num}/
    done < ${BASEDIR}/test_list.txt
}

function create_final_report()
{
    # create final report which includes all partial test reports
    for i in $(seq $test_num); do
        rebot_params="$rebot_params $BASEDIR/logs/$i/output.xml"
    done
    
    echo -e "${green}Final report is located:${nc}"
    rebot $rebot_params
}


## main

# activate venv
if source $BASEDIR/venv/bin/activate; then
    echo -e "${green}Python virtualenv activated.${nc}"
else
    echo -e "${red}ERROR${nc}"
    exit 1
fi

clone_odl_tests
modify_odl_tests
execute_odl_tests
create_final_report
