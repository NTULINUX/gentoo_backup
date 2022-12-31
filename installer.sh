#!/usr/bin/env bash

# Gentoo stage4 installation script for LinuxCNC
# Written by Alec Ari

# Yes, I'm writing an installer for something that doesn't exist yet.

set -eou pipefail

printf "\\033[0;33m
\\tGentoo stage4 installation script for LinuxCNC.
\\tWritten by Alec Ari
\\033[0m"

if [[ "${EUID}" -ne 0 ]] ; then
	printf "\\n\\tError: Must have root privileges.\\n"
	exit 1
fi

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

	type mkfs.fat >> /dev/null 2>&1 || \
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

	read -r "INSTALL_TYPE_ARG"

	if [[ "${INSTALL_TYPE_ARG}" == "LEGACY" || \
		"${INSTALL_TYPE_ARG}" == "Legacy" || \
		"${INSTALL_TYPE_ARG}" == "legacy" ]]
	then
		INSTALL_TYPE="LEGACY"
		printf "\\n\\tInstallation type: Legacy BIOS\\n"
	elif [[ "${INSTALL_TYPE_ARG}" == "UEFI" || \
		"${INSTALL_TYPE_ARG}" == "uefi" ]]
	then
		INSTALL_TYPE="UEFI"
		printf "\\n\\tInstallation type: UEFI
\\033[0;33m
\\tIMPORTANT: Please be sure CSM is disabled in BIOS before continuing!
\\033[0m\\n" ; sleep 5

		printf "\\tEnsuring system has booted with UEFI Runtime Services...\\n"
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

check_drive_prompt()
{
	printf "\\n\\tPreparing drives...\\n\\n"

	printf "\\tPlease choose your device for the installation
\\ti.e. /dev/sda or /dev/nvme0n1 etc.
\\033[0;33m
\\tIMPORTANT: Do not specify a partition, an entire drive is required.
\\033[0m
\\tTo bring up a list of possible devices, type: list
\\tIf the list is too long to fully see, try: shortlist
\\033[0;31m
\\tWARNING: ALL DATA ON THE SPECIFIED DEVICE WILL BE REMOVED!
\\tTHIS ACTION CANNOT BE UNDONE!
\\033[0m\\n"

	read -r "ENTIRE_DRIVE"

	printf "\\n"
}

check_drive()
{
	check_drive_prompt

	while [[ "${ENTIRE_DRIVE}" == "list" || \
		"${ENTIRE_DRIVE}" == "LIST" || \
		"${ENTIRE_DRIVE}" == "shortlist" || \
		"${ENTIRE_DRIVE}" == "SHORTLIST" ]]
	do
		case "${ENTIRE_DRIVE}" in
			list|LIST)
				fdisk -l
				check_drive_prompt
				;;
			shortlist|SHORTLIST)
				fdisk -l | grep "Disk" -A 0
				check_drive_prompt
				;;
		esac
	done

	printf "\\tVerifying entry...\\n"
	if [[ "${ENTIRE_DRIVE}" == *"nvme"* ]] ; then
		if [[ "${INSTALL_TYPE}" != "UEFI" ]] ; then
			printf "\\n\\tError: UEFI must be selected for NVMe.\\n"
			exit 1
		fi

		if [[ "${ENTIRE_DRIVE}" == *"p"[0-9]* ]] ; then
			printf "\\n\\tError: NVMe Partition has been specified.\\n"
			exit 1
		fi
	elif [[ "${ENTIRE_DRIVE}" == *[0-9]* ]] ; then
		printf "\\n\\tError: Partition has been specified.\\n"
		exit 1
	fi

	if [[ -b "${ENTIRE_DRIVE}" ]] ; then
		printf "\\tBlock device: %s is valid.\\n" "${ENTIRE_DRIVE}"
	else
		printf "\\n\\tError: Invalid block device: %s\\n" "${ENTIRE_DRIVE}"
		exit 1
	fi

	if ! grep -e "${ENTIRE_DRIVE}" "/proc/mounts" >> /dev/null 2>&1 && \
		! mount | grep "${ENTIRE_DRIVE}" >> /dev/null 2>&1
	then
		printf "\\tNo partitions mounted on: %s\\n" "${ENTIRE_DRIVE}"
	else
		printf "\\n\\tError: %s has partitions mounted.\\n" "${ENTIRE_DRIVE}"
		exit 1
	fi
}

wipe_drive()
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

	if [[ "${ENTIRE_DRIVE}" == *"nvme"* ]] ; then
		blkdiscard "${ENTIRE_DRIVE}"
	fi

	sleep 5 && sync

	printf "\\tDone.\\n"
}

partition_sizes()
{
	# Use sane defaults for both legacy BIOS and UEFI
	if [[ "${INSTALL_TYPE}" == "LEGACY" ]] ; then
		BIOS_PART_SIZE="2M"
	elif [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		EFI_PART_SIZE="100M"
	fi

	# Sane default for boot partition
	BOOT_PART_SIZE="1G"

	printf "\\n\\tPlease specify the size for the home partition ( /home )
\\tin gigabytes (GB.)\\n
\\tValue must be between 2 and 16000 (2 = 2GB, 16000 = 16TB)
\\tValue must be an exact integer.
\\tDo not specify a unit (i.e. m/M/MB g/G/GB t/T/TB)\\n\\n"

	read -r "HOME_PART_SIZE"

	if [[ "${HOME_PART_SIZE}" == [!0-9] || \
		"${HOME_PART_SIZE}" == *[!0-9]* ]]
	then
		printf "\\n\\tError: Value must be an integer.\\n"
		exit 1
	elif [[ "${HOME_PART_SIZE}" -lt 2 || \
		"${HOME_PART_SIZE}" -gt 16000 ]]
	then
		printf "\\n\\tError: Value: %s out of range.\\n" "${HOME_PART_SIZE}"
		exit 1
	fi

	printf "\\n\\tPlease specify the size for the root partition ( / )
\\tin gigabytes (GB.)\\n
\\tValue must be between 10 and 16000 (10 = 10GB, 16000 = 16TB)
\\tValue must be an exact integer.
\\tDo not specify a unit (i.e. m/M/MB g/G/GB t/T/TB)\\n\\n"

	read -r "ROOT_PART_SIZE"

	if [[ "${ROOT_PART_SIZE}" == [!0-9] || \
		"${ROOT_PART_SIZE}" == *[!0-9]* ]]
	then
		printf "\\n\\tError: Value must be an integer.\\n"
		exit 1
	elif [[ "${ROOT_PART_SIZE}" -lt 10 || \
		"${ROOT_PART_SIZE}" -gt 16000 ]]
	then
		printf "\\n\\tError: Value: %s out of range.\\n" "${ROOT_PART_SIZE}"
		exit 1
	fi
}

partition_drive()
{
	if [[ "${INSTALL_TYPE}" == "LEGACY" ]] ; then
		BIOS_GUID="21686148-6449-6E6F-744E-656564454649"
	elif [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		EFI_GUID="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
	fi

	BOOT_GUID="BC13C2FF-59E6-4262-A352-B275FD6F7172"
	HOME_GUID="933AC7E1-2EB4-4F13-B844-0E14E2AEF915"
	ROOT_GUID="4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709"

	printf "\\n\\tPartitioning device: %s using the following layout:\\n\\n" \
		"${ENTIRE_DRIVE}"

	if [[ "${INSTALL_TYPE}" == "LEGACY" ]] ; then
		printf "\\tBIOS boot partition: %s\\n" "${BIOS_PART_SIZE}"
	elif [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		printf "\\tEFI system partition: %s\\n" "${EFI_PART_SIZE}"
	fi

	printf "\\tLinux extended boot partition ( /boot ): %s
\\tLinux home partition ( /home ): %sG
\\tLinux root (x86-64) partition ( / ): %sG\\n\\n" \
	"${BOOT_PART_SIZE}" "${HOME_PART_SIZE}" "${ROOT_PART_SIZE}"

	if [[ "${INSTALL_TYPE}" == "LEGACY" ]] ; then
		sfdisk -w always -W always "${ENTIRE_DRIVE}" <<-EOF
			label :gpt
			,"${BIOS_PART_SIZE}","${BIOS_GUID}"
			,"${BOOT_PART_SIZE}","${BOOT_GUID}"
			,"${HOME_PART_SIZE}G","${HOME_GUID}"
			,"${ROOT_PART_SIZE}G","${ROOT_GUID}"
		EOF
	elif [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		sfdisk -w always -W always "${ENTIRE_DRIVE}" <<-EOF
			label :gpt
			,"${EFI_PART_SIZE}","${EFI_GUID}"
			,"${BOOT_PART_SIZE}","${BOOT_GUID}"
			,"${HOME_PART_SIZE}G","${HOME_GUID}"
			,"${ROOT_PART_SIZE}G","${ROOT_GUID}"
		EOF
	fi
}

choose_filesystem()
{
	printf "\\n\\tPlease select either EXT4 or XFS.
\\tFor NVMe, XFS is recommended (I think...)\\n
\\tValid options:
\\t\\tEXT4/ext4
\\t\\tXFS/xfs\\n\\n"

	read -r "FSTYPE_ARG"

	if [[ "${FSTYPE_ARG}" == "EXT4" || \
		"${FSTYPE_ARG}" == "ext4" ]]
	then
		FSTYPE="EXT4"
	elif [[ "${FSTYPE_ARG}" == "XFS" || \
		"${FSTYPE_ARG}" == "xfs" ]]
	then
		FSTYPE="XFS"
	fi

	printf "\\n\\tSelected filesystem: %s\\n\\n" "${FSTYPE}"
}

format_partitions()
{
	if [[ "${ENTIRE_DRIVE}" == *"nvme"* ]] ; then
		# UEFI is always true for NVMe installations
		mkfs.fat -F 32 "${ENTIRE_DRIVE}p1"
		if [[ "${FSTYPE}" == "EXT4" ]] ; then
			mkfs.ext4 "${ENTIRE_DRIVE}p2"
			mkfs.ext4 "${ENTIRE_DRIVE}p3"
			mkfs.ext4 "${ENTIRE_DRIVE}p4"
		elif [[ "${FSTYPE}" == "XFS" ]] ; then
			mkfs.xfs "${ENTIRE_DRIVE}p2"
			mkfs.xfs "${ENTIRE_DRIVE}p3"
			mkfs.xfs "${ENTIRE_DRIVE}p4"
		fi
	# (Not NVMe) Only if UEFI is enabled do we format the first partition
	elif [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		mkfs.fat -F 32 "${ENTIRE_DRIVE}1"
	fi

	if [[ "${FSTYPE}" == "EXT4" ]] ; then
		mkfs.ext4 "${ENTIRE_DRIVE}2"
		mkfs.ext4 "${ENTIRE_DRIVE}3"
		mkfs.ext4 "${ENTIRE_DRIVE}4"
	elif [[ "${FSTYPE}" == "XFS" ]] ; then
		mkfs.xfs "${ENTIRE_DRIVE}2"
		mkfs.xfs "${ENTIRE_DRIVE}3"
		mkfs.xfs "${ENTIRE_DRIVE}4"
	fi
}

check_deps

legacy_or_uefi

check_drive

# wipe_drive

partition_sizes

# partition_drive

choose_filesystem

# format_partitions
