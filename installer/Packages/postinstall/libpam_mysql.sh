#!/bin/sh
# i-MSCP - internet Multi Server Control Panel
# Copyright 2010-2017 by Laurent Declercq <l.declercq@nuxwin.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

set -e

CONFFDIR="$1"
DISTRO=$(lsb_release -cs)
PAM_MYSQL_VERSION=`dpkg-query --show --showformat '${Version}' libpam-mysql`
SRC_PKG=pam_mysql
PBUILDERCONF="$CONFFDIR/$DISTRO/pbuilder/pbuilderrc";
PATCHESDIR="$CONFFDIR/$DISTRO/libpam-mysql"

if dpkg --compare_version "$PAM_MYSQL_VERSION" lt 0.8.0 ; then
    if [ ! -f "/usr/sbin/pbuilder" ]; then
        apt-get -y install pbuilder patch
    fi

    # Creating/Updating pbuilder environment
    if [ ! -f '/var/cache/pbuilder/base.tgz' ] ; then
        pbuilder --create --distribution ${DISTRO} --configfile ${PBUILDERCONF} --override-config
    else
        pbuilder --update --autocleanaptcache --distribution ${DISTRO} --configfile ${PBUILDERCONF}--override-config
    fi

    MKTEMP=$(mktemp)
    cd ${MKTEMP}
    apt-get -y source pam_mysql
    cd pam-mysql-*

    dch--local '~i-mscp-' 'Automatically patched by i-MSCP for compatibility.'
    pdebuild --use-pdebuild-internal --conffile ${PBUILDERCONF}
    cd ..
    apt-mark unhold libpam-mysql
    dpkg --force-confnew -i /var/cache/pbuilder/result/libpam_mysql_*.deb
    apt-mark hold libpam_mysql
    cd /
    rm -rf ${MKTEMP}
elif "${PAM_MYSQL_VERSION#*imscp}" != "$PAM_MYSQL_VERSION" ; then
    apt-mark unhold libpam-mysql
    apt-get -y install libpam-mysql
fi
