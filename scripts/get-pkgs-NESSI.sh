#!/bin/bash

function log() {
    echo -e "$1" | tee -a ${GLSA_LOG}
}

function error() {
    echo -e "$1" | tee -a ${GLSA_LOG}
    exit 1
}

glsa_tmp_dir=$(mktemp -d $TMPDIR/glsa_check.XXX)
mkdir -p ${glsa_tmp_dir}
echo "glsa_tmp_dir: '${glsa_tmp_dir}'"
GLSA_LOG=${glsa_tmp_dir}/glsa.log
GLSA_CHECK_LOG=${glsa_tmp_dir}/glsa_check.log

# Check if an EESSI version has been specified
if [ "$#" -eq 0 ]; then
    error "usage: $0 <EESSI version> [EESSI architecture]"
fi

version="$1"

# Determine architecture
if [ ! -z "$2" ]
then
    arch="$2"
else
    arch="$(uname -m)"
fi

# Check if the EESSI version number encoded in the filename
# is a valid, i.e. matches the format YYYY.DD
if ! echo "${version}" | egrep -q '^20[0-9][0-9]\.(0[0-9]|1[0-2])$'
then
    error "${version} is not a valid EESSI version."
fi

compat_dir="/cvmfs/pilot.nessi.no/versions/${version}/compat/linux/${arch}"
export PATH="${compat_dir}/usr/bin:${compat_dir}/bin"

echo "Determining installed packages..."
QLIST="qlist -IRv"
if [ -f ${compat_dir}/startprefix ]; then
    ${compat_dir}/startprefix <<< ${QLIST} | sort > ${glsa_tmp_dir}/qlist_installed_packages.log
fi

echo "Searching for updates to ${compat_dir}..."
echo " - PATH set to '${PATH}'"

# Set the gentoo repo dir to a temporary directory to prevent it from having to compare
# all the existing files (which also means that CVMFS has to retrieve them) with new ones.
# Also use the mirror repo, which already contains all metadata.
gentoo_dir=${GENTOO_OVERLAY_DIR:-${glsa_tmp_dir}/gentoo}

if [ -f "${compat_dir}/etc/portage/repos.conf/gentoo.conf" ];
then
    sed -i "s|location  = .*|location = ${gentoo_dir}|" "${compat_dir}/etc/portage/repos.conf/gentoo.conf"
    sed -i "s|sync-uri\s*= .*|sync-uri  = https://github.com/gentoo-mirror/gentoo.git|" "${compat_dir}/etc/portage/repos.conf/gentoo.conf"
else
    cat > "${compat_dir}/etc/portage/repos.conf/gentoo.conf" <<EOF
[DEFAULT]
main-repo = gentoo
sync-git-pull-extra-opts = --quiet

[gentoo]
priority  = 1
location  = ${gentoo_dir}
sync-uri  = https://github.com/gentoo-mirror/gentoo.git
sync-type = git
auto-sync = Yes
clone-depth = 1
EOF
fi

echo "Remove existing sync'ed repo data..."
rm -f ${compat_dir}/etc/portage/repo.postsync.d/sync_gentoo_*

echo "Update the gentoo overlay by downloading a tarball of the git repo to ${gentoo_dir} ..."
mkdir -p "${gentoo_dir}"
wget -q "https://github.com/gentoo-mirror/gentoo/archive/refs/heads/stable.tar.gz"
tar -xzf "stable.tar.gz" --strip-components=1 -C "${gentoo_dir}"

echo "Run glsa-check (see log files in '${glsa_tmp_dir}')..."
glsa-check -n -p affected > ${GLSA_CHECK_LOG}
echo "Checking if there are any packages without an upgrade path (processing '${GLSA_CHECK_LOG}')"
cat ${GLSA_CHECK_LOG} | grep -A2 "No upgrade path exists for these packages"

updates=$(cat ${GLSA_CHECK_LOG} | grep vulnerable | awk '{print "="$1}' | paste -s -d ' ')
if [ ! -z "${updates}" ];
then
    log "Security vulnerabilities found in EESSI version ${version} for ${arch}!"
    log "Run the following command to solve them:"
    log '```'
    log "emerge --ask --oneshot --verbose ${updates}"
    log '```'
    exitcode=1
else
    log "No security vulnerabilities found in EESSI version ${version} for ${arch}!"
    exitcode=0
fi
echo "For details see log file '${GLSA_CHECK_LOG}'"

exit ${exitcode}
