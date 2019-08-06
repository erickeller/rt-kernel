#!/bin/sh

ENABLED_KERNEL_OPTION="CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y
CONFIG_DEFAULT_NOOP=y
CONFIG_HZ_1000=y
CONFIG_HZ_PERIODIC=y"
DISABLED_KERNEL_OPTION="CONFIG_EARLY_PRINTK=y
CONFIG_X86_VERBOSE_BOOTUP=y"

#kernel randomize_va_space

if [ $# -ne 1 ]
then
    echo "please specify a path to a kernel configuration to check"
    exit 1
elif [ -e $1 -a ! -z $1 ]
then
    KERNEL_CONFIG=$1
else
    echo "the given $1 file does not exist or is empty"
    exit 1
fi
# check if config are enabled
for config in ${ENABLED_KERNEL_OPTION}
do
    echo -n "checking ${config}"
    if ! grep -qa ${config} ${KERNEL_CONFIG}
    then
        echo "------------------> NOT OK"
    else
        echo "------------------> OK"
    fi
done

# check if config are disabled
for config in ${DISABLED_KERNEL_OPTION}
do
    echo -n "checking not enabled ${config}"
    if ! grep -qa ${config} ${KERNEL_CONFIG}
    then
        echo "------------------> OK"
    else
        echo "------------------> NOT OK"
    fi
done
