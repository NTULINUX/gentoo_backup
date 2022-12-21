#!/usr/bin/env bash

# Gentoo stage4 installation script for LinuxCNC
# Written by Alec Ari

# Yes, I'm writing an installer for something that doesn't exist yet.

set -eou pipefail

printf "\\033[0;33m
\\tGentoo stage4 installation script for LinuxCNC.
\\tWritten by Alec Ari
\\033[0m"

check_deps()
{
	printf "\\n\\tChecking dependencies...\\n"

	type mkfs.ext4 >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: e2fsprogs not installed.\\n" ;
		exit 1 ;
	}

	type mkfs.xfs >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: xfsprogs not installed.\\n" ;
		exit 1 ;
	}

	type mkfs.vfat >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: dosfstools not installed.\\n" ;
		exit 1 ;
	}

	type sfdisk >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: sfdisk (util-linux) not installed.\\n" ;
		exit 1 ;
	}

	type blkdiscard >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: blkdiscard (util-linux) not installed.\\n" ;
		exit 1 ;
	}

	type wipefs >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: wipefs (util-linux) not installed.\\n" ;
		exit 1 ;
	}

	type tar >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: tar not installed.\\n" ;
		exit 1 ;
	}

	type wget >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: wget not installed.\\n" ;
		exit 1 ;
	}

	printf "\\tDone.\\n"
}

legacy_or_uefi()
{
	printf "\\n\\tPlease choose legacy or UEFI for installation.\\n
\\tValid options:
\\t\\tLEGACY/Legacy/legacy
\\t\\tUEFI/uefi
\\033[0;33m
\\tIMPORTANT: For NVMe installation media, UEFI _MUST_ be selected!
\\033[0m\\n"

	read -r "INSTALL_TYPE"

	if [[ "${INSTALL_TYPE}" == "LEGACY" || \
		"${INSTALL_TYPE}" == "Legacy" || \
		"${INSTALL_TYPE}" == "legacy" ]]
	then
		printf "\\n\\tInstallation type: Legacy BIOS\\n"
	elif [[ "${INSTALL_TYPE}" == "UEFI" || \
		"${INSTALL_TYPE}" == "uefi" ]]
	then
		printf "\\n\\tInstallation type: UEFI
\\tEnsuring system has booted with UEFI Runtime Services...\\n"

		# This method will not work on ancient kernels or those built
		# with EFI_VARS instead of the replacement, EFIVAR_FS
		# Double-check with mounted filesystems as well
		if [[ $(find /sys/firmware/efi/efivars -type f | wc -l) -gt 1 ]] && \
			grep -e "efivarfs" "/proc/mounts" >> /dev/null 2>&1 && \
			mount | grep "efivarfs" >> /dev/null 2>&1
		then
			printf "\\tUEFI Runtime Services are supported.\\n"
		else
			printf "\\n\\tError: UEFI Runtime Services not supported.\\n"
			exit 1
		fi	
	else
		printf "\\n\\tError: Invalid selection: %s\\n" "${INSTALL_TYPE}"
		exit 1
	fi
}

check_disk()
{
	printf "\\n\\tPreparing disks...\\n\\n"

	printf "\\tPlease choose your device for the installation
\\ti.e. /dev/sda /dev/nvme0n1\\n
\\tDo not specify a partition, partitioning will be handled automatically.
\\033[0;31m
\\tWARNING: ALL DATA ON THE SPECIFIED DEVICE WILL BE REMOVED!
\\tTHIS ACTION CANNOT BE UNDONE!
\\033[0m\\n"

	read -r "ENTIRE_DRIVE"

	printf "\\n\\tVerifying entry...\\n"
	if [[ "${ENTIRE_DRIVE}" == *"nvme"* ]] ; then
		if [[ "${INSTALL_TYPE}" != "UEFI" && \
			"${INSTALL_TYPE}" != "uefi" ]]
		then
			printf "\\n\\tError: UEFI must be selected for NVMe.\\n"
			exit 1
		fi

		if [[ "${ENTIRE_DRIVE}" == *"p"[0-9]* ]] ; then
			printf "\\n\\tError: Partition has been specified.\\n"
			exit 1
		fi

		printf "\\tDisk type: NVMe\\n"
		DISK_TYPE="NVME"
	fi

	if [[ -b "${ENTIRE_DRIVE}" ]] ; then
		printf "\\tBlock device: %s is valid.\\n" "${ENTIRE_DRIVE}"
	else
		printf "\\n\\tError: Invalid block device: %s\\n" "${ENTIRE_DRIVE}"
		exit 1
	fi

	if ! grep -e "${ENTIRE_DRIVE}" "/proc/mounts" && \
		! mount | grep "${ENTIRE_DRIVE}"
	then
		printf "\\tNo partitions mounted on: %s\\n" "${ENTIRE_DRIVE}"
	else
		printf "\\n\\tError: %s has partitions mounted.\\n" "${ENTIRE_DRIVE}"
		exit 1
	fi
}

wipe_disk()
{
	printf "\\n\\tTarget installation media to erase: %s\\n
\\tAllowing 10 seconds to ensure correct device has been selected.
\\tPress Control+C to cancel.\\n
\\t10.\\n" "${ENTIRE_DRIVE}" ; sleep 1
	printf "\\t9.\\n" ; sleep 1
	printf "\\t8.\\n" ; sleep 1
	printf "\\t7.\\n" ; sleep 1
	printf "\\t6.\\n" ; sleep 1
	printf "\\t5.\\n" ; sleep 1
	printf "\\t4.\\n" ; sleep 1
	printf "\\t3.\\n" ; sleep 1
	printf "\\t2.\\n" ; sleep 1
	printf "\\t1.\\n" ; sleep 1

	printf "Removing data on: %s\\n" "${ENTIRE_DRIVE}"

	dd if=/dev/zero of="${ENTIRE_DRIVE}" bs=8M count=128 \
		oflag=sync status=progress

	wipefs -a -f "${ENTIRE_DRIVE}"

	if [[ "${DISK_TYPE}" == "NVME" ]] ; then
		blkdiscard "${ENTIRE_DRIVE}"
	fi
}

check_deps

legacy_or_uefi

check_disk

# wipe_disk
