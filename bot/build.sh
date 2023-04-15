#!/bin/bash
#
# script to build the EESSI compatibility layer. Intended use is that it is called
# by a (batch) job running on a compute node.
#
# This script is part of the EESSI compatibility layer, see
# https://github.com/EESSI/compatibility-layer.git
#
# author: Bob Droege (@bedroge)
# author: Thomas Roeblitz (@trz42)
#
# license: GPLv2
#

# ASSUMPTIONs:
#  - working directory has been prepared by the bot with a checkout of a
#    pull request (OR by some other means)
#  - the working directory contains a directory 'cfg' where the main config
#    file 'job.cfg' has been deposited
#  - the directory may contain any additional files referenced in job.cfg

# stop as soon as something fails
set -e

# source utils.sh and cfg_files.sh
source scripts/utils.sh
source scripts/cfg_files.sh

JOB_CFG_FILE=
MODE=batch
RESUME=
STORAGE=
VERBOSE=

# defaults
export JOB_CFG_FILE="${JOB_CFG_FILE_OVERRIDE:=./cfg/job.cfg}"

declare -a SCRIPT_OPTS=()
SCRIPT=./install_compatibility_layer.sh

display_help() {
  echo "usage: $0 [OPTIONS]"
  echo "OPTIONS:"
  echo "    -f | --cfg JOB_CONFIG_FILE"
  echo "        path to job config file"
  echo "        [default: value of JOB_CFG_FILE_OVERRIDE or cfg/job.cfg]"
  echo ""
  echo "    -g | --storage DIRECTORY"
  echo "        directory space on host machine (used for"
  echo "        temporary data) [default: 1. TMPDIR, 2. /tmp]"
  echo ""
  echo "    -m | --mode MODE"
  echo "        run mode for the session, either 'batch' or 'interactive'"
  echo "        [default: batch]"
  echo ""
  echo "    -h | --help"
  echo "        display this usage information"
  echo ""
  echo "    -t | --resume TMPDIR/TGZ"
  echo "        tmp directory or tarball to resume from [default: None]"
  echo ""
  echo "    --verbose"
  echo "        increase verbosity of output [default: not set]"
  echo
}

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--cfg)
      JOB_CONFIG_FILE="$2"
      shift 2
      ;;
    -g|--storage)
      STORAGE="$2"
      shift 2
      ;;
    -h|--help)
      display_help
      exit 0
      ;;
    -m|--mode)
      MODE="$2"
      shift 2
      ;;
    -t|--resume)
      RESUME="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE="-vvv"
      shift 1
      ;;
    -*|--*)
      fatal_error "Unknown option: $1" "${CMDLINE_ARG_UNKNOWN_EXITCODE}"
      ;;
    *)  # No more options
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

# check if ${JOB_CFG_FILE} exists
if [[ ! -r "${JOB_CFG_FILE}" ]]; then
    fatal_error "job config file (JOB_CFG_FILE=${JOB_CFG_FILE}) does not exist or not readable"
fi
echo "bot/build.sh: showing ${JOB_CFG_FILE} from software-layer side"
cat ${JOB_CFG_FILE}

echo "bot/build.sh: obtaining configuration settings from '${JOB_CFG_FILE}'"
cfg_load ${JOB_CFG_FILE}

# if http_proxy is defined in ${JOB_CFG_FILE} use it, if not use env var $http_proxy
HTTP_PROXY=$(cfg_get_value "site_config" "http_proxy")
HTTP_PROXY=${HTTP_PROXY:-${http_proxy}}
echo "bot/build.sh: HTTP_PROXY='${HTTP_PROXY}'"

# if https_proxy is defined in ${JOB_CFG_FILE} use it, if not use env var $https_proxy
HTTPS_PROXY=$(cfg_get_value "site_config" "https_proxy")
HTTPS_PROXY=${HTTPS_PROXY:-${https_proxy}}
echo "bot/build.sh: HTTPS_PROXY='${HTTPS_PROXY}'"

LOCAL_TMP=$(cfg_get_value "site_config" "local_tmp")
echo "bot/build.sh: LOCAL_TMP='${LOCAL_TMP}'"

if [[ -z ${STORAGE} ]]; then
    # only set STORAGE from LOCAL_TMP if it wasn't provided as cmd line arg
    echo -n "setting \$STORAGE by replacing any var in '${LOCAL_TMP}' -> "
    # replace any env variable in ${LOCAL_TMP} with its
    #   current value (e.g., a value that is local to the job)
    STORAGE=$(envsubst <<< ${LOCAL_TMP})
    echo "'${STORAGE}'"
fi

# make sure ${STORAGE} exists
mkdir -p ${STORAGE}
SCRIPT_OPTS+=("--storage" "${STORAGE}")

# obtain list of modules to be loaded
LOAD_MODULES=$(cfg_get_value "site_config" "load_modules")
echo "bot/build.sh: LOAD_MODULES='${LOAD_MODULES}'"

# load modules if LOAD_MODULES is not empty
if [[ ! -z ${LOAD_MODULES} ]]; then
    for mod in $(echo ${LOAD_MODULES} | tr ',' '\n')
    do
        echo "bot/build.sh: loading module '${mod}'"
        module load ${mod}
    done
else
    echo "bot/build.sh: no modules to be loaded"
fi

cpu_target_arch=$(cfg_get_value "architecture" "software_subdir" | cut -d/ -f1)
host_arch=$(uname -m)
eessi_arch=${cpu_target_arch:-${host_arch}}
SCRIPT_OPTS+=("--arch" "${eessi_arch}")

eessi_os=linux
job_version=$(cfg_get_value "repository" "repo_version")
eessi_version=${job_version:-2023.04}
SCRIPT_OPTS+=("--version" "${eessi_version}")

job_repo=$(cfg_get_value "repository" "repo_name")
eessi_repo=${job_repo:-pilot.eessi-hpc.org}
SCRIPT_OPTS+=("--repository" "${eessi_repo}")

tar_topdir=/cvmfs/${eessi_repo}/versions

if [ "${eessi_arch}" != "${host_arch}" ]; then
  echo "Requested architecture (${eessi_arch}) is different from this machine's architecture ($(uname -m))!"
  exit 1
fi


if [[ ! -z ${RESUME} ]]; then
    SCRIPT_OPTS+=("--resume" "${RESUME}")
fi

if [[ ${MODE} == interactive ]]; then
    SCRIPT_OPTS+=("--mode" "${MODE}")
else
    SCRIPT_OPTS+=("--mode" "batch")
fi

export SCRIPT_OPTS

# option -k is used for retaining ${eessi_tmp}
echo "Running: ${SCRIPT} ${SCRIPT_OPTS[@]} -k"
${SCRIPT} "${SCRIPT_OPTS[@]}" -k

# create tarball -> should go into a separate script when this is supported by the bot
target_tgz=eessi-${eessi_version}-compat-linux-${eessi_arch}-$(date +%s).tar.gz
if [ -d ${eessi_tmp}/${tar_topdir}/${eessi_version} ]; then
  echo ">> Creating tarball ${target_tgz} from ${eessi_tmp}/${tar_topdir}..."
  tar cfvz ${target_tgz} -C ${eessi_tmp}/${tar_topdir} ${eessi_version}/compat/${eessi_os}/${eessi_arch}
  echo ${target_tgz} created!
else
  echo "Directory ${eessi_tmp}/${tar_topdir}/${eessi_version} was not created, not creating tarball."
  exit 1
fi
