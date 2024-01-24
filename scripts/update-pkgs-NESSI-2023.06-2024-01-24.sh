#!/usr/bin/env bash

set -e

mytmpdir=$(mktemp -d --tmpdir=/tmp)

if [ -z "$EPREFIX" ]; then
    # this assumes we're running in a Gentoo Prefix environment
    EPREFIX=$(dirname $(dirname $SHELL))
fi
echo "EPREFIX=${EPREFIX}"

# collect list of installed packages before updating packages
list_installed_pkgs_pre_update=${mytmpdir}/installed-pkgs-pre-update.txt
echo "Collecting list of installed packages to ${list_installed_pkgs_pre_update}..."
qlist -IRv | sort | tee ${list_installed_pkgs_pre_update}

# update checkout of gentoo repository to sufficiently recent commit
# this is required because we pin to a specific commit when bootstrapping the compat layer
# see gentoo_git_commit in ansible/playbooks/roles/compatibility_layer/defaults/main.yml;

# https://gitweb.gentoo.org/repo/gentoo.git/commit/?id=3d2cb88c7568aa483b465e1988756e64857b41b1 (2024-01-24)
gentoo_commit='3d2cb88c7568aa483b465e1988756e64857b41b1'
echo "Updating $EPREFIX/var/db/repos/gentoo to recent commit (${gentoo_commit})..."
cd $EPREFIX/var/db/repos/gentoo
time git fetch origin
echo "Checking out ${gentoo_commit} in ${PWD}..."
time git checkout ${gentoo_commit}
cd -

# update libarchive due to https://glsa.gentoo.org/glsa/202309-14
emerge --update --oneshot --verbose '=app-arch/libarchive-3.7.2'  # was app-arch/libarchive-3.6.2-r1

# update glibc due to https://glsa.gentoo.org/glsa/202310-03
emerge --update --oneshot --verbose '=sys-libs/glibc-2.37-r7'  # was sys-libs/glibc-2.37-r3

# update binutils due to https://glsa.gentoo.org/glsa/202310-12
emerge --update --oneshot --verbose '=net-misc/curl-8.4.0'  # was net-misc/curl-8.1.2

# update openssl due to https://glsa.gentoo.org/glsa/202401-18
emerge --update --oneshot --verbose '=sys-libs/zlib-1.3-r2'  # was sys-libs/zlib-1.2.13-r1

# collect list of installed packages after updating packages
list_installed_pkgs_post_update=${mytmpdir}/installed-pkgs-post-update.txt
echo "Collecting list of installed packages to ${list_installed_pkgs_post_update}..."
qlist -IRv | sort | tee ${list_installed_pkgs_post_update}

echo
echo "diff in installed packages:"
diff -u ${list_installed_pkgs_pre_update} ${list_installed_pkgs_post_update}

rm -rf ${mytmpdir}
