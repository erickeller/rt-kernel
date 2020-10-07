#!/bin/sh

# this script automatically builds a real-time kernel combining:
# a version from kernel.org and the corresponding patch from osadl.org
set -e

# default codename
CODENAME=bionic
OSADL_RT_URL=https://www.kernel.org/pub/linux/kernel/projects/rt
KERNEL_ORG_URL=https://www.kernel.org/pub/linux/kernel
UBUNTU_KERNEL_URL=http://kernel.ubuntu.com/~kernel-ppa/mainline
PREFIX=""
REVISION=1

print_usage()
{
    cat << EOF

Build RT-Kernel automatically

usage: $0 --rt-kernel-version an-rt-kernel-version [--codename adistcodename, --kernel-config aconfig, -r|--revision arevision]

--rt-kernel-version version: full version including the mainline kernel and rt patch
--codename acodename: a codename from ubuntu or debian
--kernel-config aconfig: a specific kernel configuration
--revision arevision: a revision, especially needed when rebuilding the same kernel with same rt-patch (default=1)

Note:

* The real time kernel version have to match the following patter: "\d+[.]\d+([.]\d+)?-rt\d+"
  example: 4.19.15-rt12
  more example can be found on: https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt

* there is no exhaustive list of codename we can refer to means this needs to be updated over time.
  The default codename is set to bionic.

Sample usage:
$(basename $0) --rt-kernel-version 4.19.15-rt12
$(basename $0) --rt-kernel-version 4.19.15-rt12 --codename stretch
$(basename $0) --rt-kernel-version 4.19.15-rt12 --codename stretch --kernel-config ../bionic/config
EOF
}

check_kernel_version()
{
    VERSION=$1
    echo $VERSION | grep -P "\d+[.]\d+([.]\d+)?-rt\d+"
    if [ $? -ne 0 ]
    then
        echo "version missmatch required pattern: \d+[.]\d+([.]\d+)?-rt\d+"
        print_usage
        exit 1
    fi
}

define_kernel_versions()
{
    VERSION=$1
    # 4.4.132-rt15 --> 4.4.132
    VANILA_KERNEL_VERSION=$(echo ${VERSION} | sed -e "s/\(.*\)-.*/\1/g")
    # 4.4.132-rt15 --> 15
    RT_KERNEL_PATCH_VERSION=$(echo ${VERSION} | sed -e "s/.*-rt\(.*\)/\1/g")
    # 4.4.132-rt15 --> 4.4
    RT_KERNEL_VERSION_DIR=$(echo ${VANILA_KERNEL_VERSION} | cut -d. -f1-2)
    # 4.4.132-rt15 --> v4.x
    VANILA_KERNEL_VERSION_DIR=v$(echo ${RT_KERNEL_VERSION_DIR} | cut -d . -f1).x

    RT_PATCH_ARCHIVE_EXT="gz"
    OSADL_RT_PATCH="patch-${VERSION}.patch"
    OSADL_RT_ARCHIVE="${OSADL_RT_PATCH}.${RT_PATCH_ARCHIVE_EXT}"
    OSADL_RT_ARCHIVE_SIGN="${OSADL_RT_PATCH}.sign"
    OSADL_RT_PATCH_LEVEL=$(echo ${VERSION} | sed -e "s/.*rt\([0-9]\+\)/\1/g")

    KERNEL_ARCHIVE_TAR="tar"
    KERNEL_ARCHIVE_COMPRESSED="${KERNEL_ARCHIVE_TAR}.gz"
    KERNEL_ARCHIVE_SIGN="${KERNEL_ARCHIVE_TAR}.sign"
    KERNEL_ORG_ARCHIVE_TAR="linux-${VANILA_KERNEL_VERSION}.${KERNEL_ARCHIVE_TAR}"
    KERNEL_ORG_ARCHIVE="linux-${VANILA_KERNEL_VERSION}.${KERNEL_ARCHIVE_COMPRESSED}"
    KERNEL_ORG_ARCHIVE_SIGN="linux-${VANILA_KERNEL_VERSION}.${KERNEL_ARCHIVE_SIGN}"

    echo "RT_KERNEL_VERSION_DIR: ${RT_KERNEL_VERSION_DIR}
VANILA_KERNEL_VERSION: ${VANILA_KERNEL_VERSION}
VANILA_KERNEL_VERSION_DIR: ${VANILA_KERNEL_VERSION_DIR}
OSADL_RT_ARCHIVE: ${OSADL_RT_ARCHIVE}
KERNEL_ORG_ARCHIVE: ${KERNEL_ORG_ARCHIVE}
"
}

# TODO parametrize this to be executed inside LXD/Chroot container
install_dependencies()
{
# install dependencies
    sudo sh -c "apt-get update && apt-get --no-install-recommends \
                                            -o Dpkg::Options::=--force-confnew install -y fakeroot \
                                                                                        curl \
                                                                                        bison flex \
                                                                                        devscripts \
                                                                                        libssl-dev \
                                                                                        make \
                                                                                        gcc \
                                                                                        build-essential \
                                                                                        dpkg-dev curl \
                                                                                        wget \
                                                                                        libncurses5-dev \
                                                                                        libncursesw5-dev \
                                                                                        bc \
                                                                                        kernel-package \
                                                                                        cpio \
                                                                                        debhelper \
                                                                                        dput \
                                                                                        liblz4-tool"
}

import_kernel_signature_key()
{
    KEY=$1
    KEYSERVER=hkp://keyserver.ubuntu.com
    SERVER_PORT=80
    # add kernel signature
    gpg --keyserver ${KEYSERVER}:${SERVER_PORT} --recv-keys ${KEY}
}

# arg 1: url
# arg 2: archive
download()
{
    CURL_OPTIONS="-L --insecure -O -C -"
    URL=$1
    ARCHIVE=$2
    if [ -f ${ARCHIVE} ]
    then
        echo "Skipping already downloaded file ${URL}/${ARCHIVE}..."
    else
        CMD="curl ${CURL_OPTIONS} ${URL}/${ARCHIVE}"
        echo "${CMD}"
        eval ${CMD}
    fi
    return 0
}

get_files()
{
    download ${OSADL_RT_URL}/${RT_KERNEL_VERSION_DIR} ${OSADL_RT_ARCHIVE}
    if egrep "404:" ${OSADL_RT_ARCHIVE}
    then
        # some patch are moved to the older directory
        rm -f ${OSADL_RT_ARCHIVE}
        download ${OSADL_RT_URL}/${RT_KERNEL_VERSION_DIR}/older ${OSADL_RT_ARCHIVE}
        download ${OSADL_RT_URL}/${RT_KERNEL_VERSION_DIR}/older ${OSADL_RT_ARCHIVE_SIGN}
    fi
    download ${OSADL_RT_URL}/${RT_KERNEL_VERSION_DIR} ${OSADL_RT_ARCHIVE_SIGN}
    download ${KERNEL_ORG_URL}/${VANILA_KERNEL_VERSION_DIR} ${KERNEL_ORG_ARCHIVE}
    download ${KERNEL_ORG_URL}/${VANILA_KERNEL_VERSION_DIR} ${KERNEL_ORG_ARCHIVE_SIGN}
}

get_ubuntu_patches()
{
    UBUNTU_PATCHES=$(curl -L --insecure ${UBUNTU_KERNEL_URL}/v${VANILA_KERNEL_VERSION}/ | grep "\.patch" | sed -e  's#.*<a href="\(.*\.patch\)".*#\1#g' | sort -u)

    for p in ${UBUNTU_PATCHES}
    do
        echo download ${p}
        download ${UBUNTU_KERNEL_URL}/v${VANILA_KERNEL_VERSION} ${p}
    done
}

extract_files()
{
    if [ ! -d linux-${VANILA_KERNEL_VERSION} ]
    then
        gunzip -f -c ${KERNEL_ORG_ARCHIVE} > ${KERNEL_ORG_ARCHIVE_TAR}
        gpg --verify ${KERNEL_ORG_ARCHIVE_SIGN}
        tar xf ${KERNEL_ORG_ARCHIVE}
    fi

    if [ ! -f ${OSADL_RT_PATCH} ]
    then
        gunzip ${OSADL_RT_ARCHIVE}
        gpg --verify ${OSADL_RT_ARCHIVE_SIGN}
    fi
}

gather_artifacts()
{
    tar caf kernel-${VANILA_KERNEL_VERSION}-artifacts.tar.gz *.patch *.sign linux-${VANILA_KERNEL_VERSION}.tar lowlatency.config ${PREFIX}rtkernel rt-config-fragment
}

apply_patches()
{
    cd linux-${VANILA_KERNEL_VERSION}
    if patch -p1 -N --dry-run --silent < ../${OSADL_RT_PATCH}
    then
        patch -p1 < ../${OSADL_RT_PATCH}
    else
        echo "${OSADL_RT_PATCH} patch did not aply..."
    fi

    #cp ../../${CODENAME}/config .config

    for p in $(ls ../*.patch | grep '../[0-9]\+-')
    do
        echo "applying patch: ${p}"
        if patch -p1 -N --dry-run --silent < ${p}
        then
            patch -p1 < ${p}
        else
            echo "${p} patch did not apply..."
        fi
    done
    cd -
}

get_lowlatency_config()
{
set -x
    LOW_LATENCY_HEADER_DEB=$(curl -L --insecure ${UBUNTU_KERNEL_URL}/v${VANILA_KERNEL_VERSION}/ | grep ".*headers.*lowlatency.*amd64" | sed -e 's#.*href="\(.*.deb\)".*#\1#g' | head -n1)
    if [ -z ${LOW_LATENCY_HEADER_DEB} ]
    then
        LOW_LATENCY_HEADER_DEB=$(curl -L --insecure ${UBUNTU_KERNEL_URL}/v${RT_KERNEL_VERSION_DIR}/ | grep ".*headers.*lowlatency.*amd64" | sed -e 's#.*href="\(.*.deb\)".*#\1#g' | head -n1)
        download ${UBUNTU_KERNEL_URL}/v${RT_KERNEL_VERSION_DIR} ${LOW_LATENCY_HEADER_DEB}
    else
        download ${UBUNTU_KERNEL_URL}/v${VANILA_KERNEL_VERSION} ${LOW_LATENCY_HEADER_DEB}
    fi

    # extract debian package data content
    ar xv $(basename ${LOW_LATENCY_HEADER_DEB})
    tar xaf data.tar.xz
    cp $(find  usr/src/ -name .config | head -n1) lowlatency.config
    cp -f lowlatency.config linux-${VANILA_KERNEL_VERSION}/.config
}

build_kernel()
{
    cd linux-${VANILA_KERNEL_VERSION}
    # inject RT configuration
    ./scripts/kconfig/merge_config.sh .config ../rt-config-fragment
    if ! grep -q "CONFIG_PREEMPT_RT=y" .config
    then
        echo "No RT PREEMPT configuration applied to .config... Aborting..."
        exit 1
    fi
    make oldconfig
    # TODO check config matching RT kernel parameters
    CMD="make -j `nproc` deb-pkg LOCALVERSION=-${PREFIX}${CODENAME} KDEB_PKGVERSION=${REVISION}"
    echo "${CMD}" | tee kernel.build.cmd
    eval ${CMD}
    cd -
}

create_meta_package()
{
    # create meta package ${PREFIX}rtkernel
    LINUXIMAGE=$(ls linux-image-${VANILA_KERNEL_VERSION}-rt${RT_KERNEL_PATCH_VERSION}-${CODENAME}_${REVISION}*.deb | sed -e "s/${CODENAME}.*deb/${CODENAME}/")
    LINUXHEADERS=$(ls linux-headers-${VANILA_KERNEL_VERSION}-rt${RT_KERNEL_PATCH_VERSION}-*.deb | sed -e "s/${CODENAME}.*deb/${CODENAME}/")
    rm -rf ${PREFIX}rtkernel
    cp -rf ${PREFIX}rtkernel.template ${PREFIX}rtkernel
    cd ${PREFIX}rtkernel
    # replace control struff for linux-image and linux-headers packages
    sed -i "s/__LINUXIMAGE__/${LINUXIMAGE}/g" debian/control
    sed -i "s/__LINUXHEADERS__/${LINUXHEADERS}/g" debian/control
    # create changelog
    dch --create --packag=${PREFIX}rtkernel -v ${VANILA_KERNEL_VERSION}-rt${RT_KERNEL_PATCH_VERSION}~${REVISION} --distribution ${CODENAME} --empty --controlmaint "integrate ${VANILA_KERNEL_VERSION}-rt${RT_KERNEL_PATCH_VERSION}_${REVISION} rt kernels"
    debuild -uc -us -rfakeroot
    # cleanup for artifact gathering
    debclean
    cd ..
}

# options definition
if ! options=$(getopt -o hn:k:c:r: -l help,codename:,rt-kernel-version:,kernel-config:,revision: -- "$@")
then
    print_usage
    exit 1
fi
eval set -- "$options"

while true
do
    case "$1" in
        -h|--help)                   print_usage && exit 0;;
        -n|--codename)               CODENAME=$2; shift 2;;
        -k|--rt-kernel-version)      RTKERNELVERSION=$2; shift 2;;
        -c|--kernel-config)          KERNELCONFIG=$2; shift 2;;
        -r|--revision)               REVISION=$2; shift 2;;
        *)                           break;;
    esac
done

echo "CODENAME: ${CODENAME} RTKERNELVERSION: ${RTKERNELVERSION} KERNELCONFIG: ${KERNELCONFIG}"
check_kernel_version ${RTKERNELVERSION}
define_kernel_versions ${RTKERNELVERSION}
install_dependencies
# Vanila kernel signature
import_kernel_signature_key 6092693E
# OSADL signature
import_kernel_signature_key 647F28654894E3BD457199BE38DBBDC86092693E
get_files
get_ubuntu_patches
extract_files
get_lowlatency_config
apply_patches
build_kernel
create_meta_package
gather_artifacts

exit 0

