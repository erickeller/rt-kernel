#!/bin/sh
set -e
KERNELORG=https://www.kernel.org/
RTKERNEL=https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/
VANILA=$(curl -s ${KERNELORG} | grep -C 2 "<td>longterm:</td>" -m 1 | grep  -P "<td>.*\d+[.]\d+[.]\d+.*</td>"|tr -d " " |sed -e "s#.*\([0-9]\+[.][0-9]\+[.][0-9]\+\).*#\1#")
echo ${VANILA}
# depending on the kernel version one need to extract only 2 digit
NUM_OF_VERSION=$(echo ${VANILA} | grep -o  '[.]' | wc -l)
KERNEL_VERSION_2DIGITS=${VANILA}
if [ ${NUM_OF_VERSION} -eq 2 ]
then
    KERNEL_VERSION_2DIGITS=`echo ${VANILA} | sed -e 's/\(.*\)[.].*/\1/'`
fi
echo ${KERNEL_VERSION_2DIGITS}
RTVERSION=$(curl -s ${RTKERNEL}/${KERNEL_VERSION_2DIGITS}/ | grep -C 1 sums.asc | grep patches | sed -e "s#.*>patches-\([0-9]\+[.][0-9]\+[.][0-9]\+-rt[0-9]\+\).*#\1#")
echo ${RTVERSION}
#docker pull node:latest 2>&1 > /dev/null
#docker run -ti --rm node:latest bash -c "npm install cheerio-cli -g &> /dev/null
#curl -s https://www.kernel.org/ | cheerio '#releases td:nth-child(1):contains(stable:)+td:nth-child(2)>strong'
#"
