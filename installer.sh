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

ROOT_MOUNT="/mnt/gentoo-cnc"
HOME_USER="lcnc"
HOME_MOUNT_SUBDIR="${ROOT_MOUNT}/home/${HOME_USER}"

STAGE4_TAG="v0.1-alpha"
STAGE4_NAME="lcnc-x86_64-v2-stage4"
STAGE4_SRCURI="https://github.com/NTULINUX/gentoo_backup/releases/download/${STAGE4_TAG}/${STAGE4_NAME}.tar.xz"
STAGE4_CHECKSUM="https://github.com/NTULINUX/gentoo_backup/releases/download/${STAGE4_TAG}/${STAGE4_NAME}.sha1sum"

verbose_prompt()
{
	printf "\\n\\tEnable verbose installation?\\n
\\tThis may help diagnose problems with installation but may produce
\\texcessive terminal scrollback.\\n
\\tValid options (Enter for default):
\\t\\tYES/yes
\\t\\tNO/no (default)\\n\\n"

	read -r "VERBOSE_ARG" ; printf "\\n"

	if [[ "${VERBOSE_ARG}" == "N" || \
		"${VERBOSE_ARG}" == "NO" || \
		"${VERBOSE_ARG}" == "n" || \
		"${VERBOSE_ARG}" == "no" || \
		"${VERBOSE_ARG}" == "DEFAULT" || \
		"${VERBOSE_ARG}" == "default" || \
		-z "${VERBOSE_ARG}" ]]
	then
		VERBOSE_INSTALL="FALSE"
		printf "\\tVerbose install disabled.\\n"
	elif [[ "${VERBOSE_ARG}" == "Y" || \
		"${VERBOSE_ARG}" == "YES" || \
		"${VERBOSE_ARG}" == "y" || \
		"${VERBOSE_ARG}" == "yes" ]]
	then
		VERBOSE_INSTALL="TRUE"
		printf "\\tVerbose install enabled.\\n"
	else
		printf "\\n\\tError: Invalid selection: %s\\n" \
			"${VERBOSE_ARG}"
		exit 1
	fi
}

verbose_prompt

if_log()
{
	if [[ "${VERBOSE_INSTALL}" == "FALSE" ]] ; then
		"${@}" >> /dev/null 2>&1
	elif [[ "${VERBOSE_INSTALL}" == "TRUE" ]] ; then
		"${@}"
	fi
}

verify_psabi()
{
	printf "\\n\\tChecking CPU requirements...\\n"

	X86_64_V2="
		mmx
		mmxext
		popcnt
		sse
		sse2
		sse3
		ssse3
		sse4_1
		sse4_2
	"

	mapfile -s 1 -t FLAGS < <(printf "%s" "${X86_64_V2}" | sed 's/\t//g')

	for (( i=0 ; i < "${#FLAGS[@]}" ; i++ )) ; do
		printf "\\tChecking for: %s\\n" "${FLAGS[$i]}"

		lscpu | grep "${FLAGS[$i]}" >> /dev/null 2>&1 || \
		{
			printf "\\tError: Missing: %s\\n" "${FLAGS[$i]}" ;
			exit 1 ;
		}
	done

	printf "\\n\\tDone. Your processor is x86-64-v2 or newer.\\n"
	printf "\\tYou may safely use the Gentoo image for LinuxCNC.\\n"
}

linux_ver()
{
	printf "\\tChecking Linux kernel version...\\n"

	LINUX_MAJOR_VER=$(uname -r | cut -d '.' -f1)
	LINUX_MINOR_VER=$(uname -r | cut -d '.' -f2)

	if [[ "${LINUX_MAJOR_VER}" -lt 5 || \
		"${LINUX_MAJOR_VER}" -eq 5 && \
		"${LINUX_MINOR_VER}" -lt 15 ]]
	then
		printf "\\n\\tError: Linux kernel version must be at least 5.15.0\\n"
		exit 1
	elif [[ "${LINUX_MAJOR_VER}" -gt 6 ||
		"${LINUX_MAJOR_VER}" -eq 6 && \
		"${LINUX_MINOR_VER}" -gt 5 ]]
	then
		printf "\\n\\tError: Linux kernel version must not be newer than 6.5.\\n"
		exit 1
	else
		printf "\\tLinux kernel version: %s\\n" "$(uname -r)"
	fi
}

# If unable to locate config, skip checking for filesystem support. If options
# are disabled, do not error out until all options have been gathered.
linux_config_check()
{
	if [[ -r "/proc/config.gz" ]] ; then
		KCONFIG="/proc/config.gz"
	elif [[ -r "/boot/config-$(uname -r)" ]] ; then
		KCONFIG="/boot/config-$(uname -r)"
	else
		printf "\\tKernel configuration not found.\\n"
		return 0 ;
	fi

	printf "\\n\\tCurrent kernel configuration found.
\\tEnsuring Linux kernel has proper filesystem support...\\n"

	BTRFS_OPTIONS="
		BTRFS_FS
		BTRFS_FS_POSIX_ACL
	"

	EXT4_OPTIONS="
		EXT4_FS
		EXT4_FS_POSIX_ACL
	"

	F2FS_OPTIONS="
		F2FS_FS
		F2FS_FS_XATTR
		F2FS_FS_POSIX_ACL
	"

	XFS_OPTIONS="
		XFS_FS
		XFS_POSIX_ACL
	"

	mapfile -s 1 -t BTRFS_STRINGS < <(printf "%s" "${BTRFS_OPTIONS}" | \
		sed -e 's/\t//g' -e '$d')

	mapfile -s 1 -t EXT4_STRINGS < <(printf "%s" "${EXT4_OPTIONS}" | \
		sed -e 's/\t//g' -e '$d')

	mapfile -s 1 -t F2FS_STRINGS < <(printf "%s" "${F2FS_OPTIONS}" | \
		sed -e 's/\t//g' -e '$d')

	mapfile -s 1 -t XFS_STRINGS < <(printf "%s" "${XFS_OPTIONS}" | \
		sed -e 's/\t//g' -e '$d')

	# Throw all errors first before exiting
	set +e

	for (( i=0 ; i < "${#BTRFS_STRINGS[@]}" ; i++ )) ; do
		if ! zgrep "CONFIG_${BTRFS_STRINGS[$i]}=m" \
			"${KCONFIG}" >> /dev/null 2>&1 && \
			! zgrep "CONFIG_${BTRFS_STRINGS[$i]}=y" \
			"${KCONFIG}" >> /dev/null 2>&1
		then
			printf "\\n\\tError: %s is not set.\\n" \
				"CONFIG_${BTRFS_STRINGS[$i]}"
			BTRFS_ERROR_THROWN=1
		else
			BTRFS_ERROR_THROWN=0
		fi
	done

	for (( i=0 ; i < "${#EXT4_STRINGS[@]}" ; i++ )) ; do
		if ! zgrep "CONFIG_${EXT4_STRINGS[$i]}=m" \
			"${KCONFIG}"  >> /dev/null 2>&1 && \
			! zgrep "CONFIG_${EXT4_STRINGS[$i]}=y" \
			"${KCONFIG}" >> /dev/null 2>&1
		then
			printf "\\n\\tError: %s is not set.\\n" \
				"CONFIG_${EXT4_STRINGS[$i]}"
			EXT4_ERROR_THROWN=1
		else
			EXT4_ERROR_THROWN=0
		fi
	done

	for (( i=0 ; i < "${#F2FS_STRINGS[@]}" ; i++ )) ; do
		if ! zgrep "CONFIG_${F2FS_STRINGS[$i]}=m" \
			"${KCONFIG}" >> /dev/null 2>&1 && \
			! zgrep "CONFIG_${F2FS_STRINGS[$i]}=y" \
			"${KCONFIG}" >> /dev/null 2>&1
		then
			printf "\\n\\tError: %s is not set.\\n" \
				"CONFIG_${F2FS_STRINGS[$i]}"
			F2FS_ERROR_THROWN=1
		else
			F2FS_ERROR_THROWN=0
		fi
	done

	for (( i=0 ; i < "${#XFS_STRINGS[@]}" ; i++ )) ; do
		if ! zgrep "CONFIG_${XFS_STRINGS[$i]}=m" \
			"${KCONFIG}" >> /dev/null 2>&1 && \
			! zgrep "CONFIG_${XFS_STRINGS[$i]}=y" \
			"${KCONFIG}" >> /dev/null 2>&1
		then
			printf "\\n\\tError: %s is not set.\\n" \
				"CONFIG_${XFS_STRINGS[$i]}"
			XFS_ERROR_THROWN=1
		else
			XFS_ERROR_THROWN=0
		fi
	done

	set -e

	if [[ "${BTRFS_ERROR_THROWN}" -eq 1 || \
		"${EXT4_ERROR_THROWN}" -eq 1 || \
		"${F2FS_ERROR_THROWN}" -eq 1 || \
		"${XFS_ERROR_THROWN}" -eq 1 ]]
	then
		printf "\\n\\tErrors detected. Exiting...\\n\\n"
		exit 1
	else
		printf "\\tAll filesystems enabled.\\n\\n"
	fi
}

# Put version checks into their own section for ease of maintenance
btrfs_ver()
{
	BTRFS_MAJOR_VER=$(mkfs.btrfs -V | grep -o "[0-9]" | sed -n '1p')
	BTRFS_MINOR_VER=$(mkfs.btrfs -V | grep -o "[0-9]" | sed -n '2p')
	BTRFS_PATCH_VER=$(mkfs.btrfs -V | grep -o "[0-9]" | sed -n '3p')

	if [[ "${BTRFS_MAJOR_VER}" -lt 5 || \
		"${BTRFS_MAJOR_VER}" -eq 5 && \
		"${BTRFS_MINOR_VER}" -lt 15 || \
		"${BTRFS_MINOR_VER}" -eq 15 && \
		"${BTRFS_PATCH_VER}" -lt 1 ]]
	then
		printf "\\n\\tError: btfrs-progs must be 5.15.1 or newer.\\n"
		exit 1
	else
		printf "\\tbtrfs-progs version: %s\\n" \
			"${BTRFS_MAJOR_VER}.${BTRFS_MINOR_VER}.${BTRFS_PATCH_VER}"
	fi
}

f2fs_ver()
{
	F2FS_MAJOR_VER=$(mkfs.f2fs -V | cut -d ' ' -f2 | cut -d '.' -f1)
	F2FS_MINOR_VER=$(mkfs.f2fs -V | cut -d ' ' -f2 | cut -d '.' -f2)

	if [[ "${F2FS_MAJOR_VER}" -lt 1 || \
		"${F2FS_MAJOR_VER}" -eq 1 && \
		"${F2FS_MINOR_VER}" -lt 15 ]]
	then
		printf "\\n\\tError: f2fs-tools must be 1.15.0 or newer.\\n"
		exit 1
	else
		printf "\\tf2fs-progs version: %s\\n" \
			"${F2FS_MAJOR_VER}.${F2FS_MINOR_VER}"
	fi
}

check_deps()
{
	printf "\\n\\tChecking dependencies...\\n\\n"

	# This is necessary to ensure we don't create a BTRFS or F2FS filesystem
	# with an ancient kernel, but also that the kernel is not newer than that
	# used to mount the F2FS filesystem (the PREEMPT_RT kernel)
	# https://bugzilla.opensuse.org/show_bug.cgi?id=1109665#c0
	linux_ver

	# Make sure the running kernel supports BTRFS, EXT4, F2FS and XFS
	linux_config_check

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

	type mkfs.btrfs >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: btrfs-progs not installed.\\n" ;
		exit 1 ;
	} ; printf "\\tChecking version of btrfs-progs...\\n" ; btrfs_ver

	type mkfs.f2fs >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: f2fs-tools not installed.\\n" ;
		exit 1 ;
	} ; printf "\\tChecking version of f2fs-tools...\\n" ; f2fs_ver

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

	type partprobe >> /dev/null 2>&1 || \
	{
		printf "\\n\\tError: partprobe (GNU parted) not installed.\\n" ;
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

	printf "\\n\\tDone.\\n"
}

legacy_or_uefi()
{
	printf "\\n\\tPlease choose legacy or UEFI for installation.\\n
\\tValid options:
\\t\\tLEGACY/Legacy/legacy
\\t\\tUEFI/uefi
\\033[0;33m
\\tIMPORTANT:
\\tFor NVMe installation media, UEFI _MUST_ be selected!
\\033[0m\\n"

	read -r "INSTALL_TYPE_ARG"

	if [[ "${INSTALL_TYPE_ARG}" == "LEGACY" || \
		"${INSTALL_TYPE_ARG}" == "Legacy" || \
		"${INSTALL_TYPE_ARG}" == "legacy" ]]
	then
		INSTALL_TYPE="LEGACY"
		printf "\\n\\tInstallation type: Legacy BIOS
\\033[0;33m
\\tIMPORTANT:
\\tPlease be sure CSM is enabled (if applicable) in BIOS before continuing!
\\033[0m\\n" ; sleep 3
	elif [[ "${INSTALL_TYPE_ARG}" == "UEFI" || \
		"${INSTALL_TYPE_ARG}" == "uefi" ]]
	then
		INSTALL_TYPE="UEFI"
		printf "\\n\\tInstallation type: UEFI
\\033[0;33m
\\tIMPORTANT:
\\tPlease be sure CSM is disabled in BIOS before continuing!
\\033[0m\\n" ; sleep 3

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
			printf "\\n\\tError: UEFI Runtime Services not supported.
\\tIf you are using a PREEMPT_RT kernel, you may need to pass: \`efi=runtime\`
\\ton the kernel command line.\\n"
			exit 1
		fi
	elif [[ -z "${INSTALL_TYPE_ARG}" ]] ; then
		printf "\\n\\tError: Must make a selection.\\n"
		exit 1
	else
		printf "\\n\\tError: Invalid selection: %s\\n" \
			"${INSTALL_TYPE_ARG}"
		exit 1
	fi
}

check_drive_prompt()
{
	printf "\\n\\tPlease choose your device for the installation
\\ti.e. /dev/sda or /dev/nvme0n1 etc.
\\033[0;33m
\\tIMPORTANT:
\\tDo not specify a partition, an entire drive is required.
\\033[0m
\\tTo bring up a list of possible devices, type: list
\\tIf the list is too long to fully see, try: shortlist
\\033[0;31m
\\tWARNING:
\\tALL DATA ON THE SPECIFIED DEVICE WILL BE REMOVED!
\\tTHIS ACTION CANNOT BE UNDONE!
\\033[0m\\n"

	read -r "ENTIRE_DRIVE" ; printf "\\n"
}

removable_prompt()
{
	printf "\\n\\tIs this a removable device such as a flash drive?\\n
\\tThis is used to determine how GRUB will be installed (--removable)
\\tIf this is a device which will be used only on this system, say no. (default)
\\tSee: grub-install(8)\\n
\\tValid options (Enter for default):
\\t\\tYES/yes
\\t\\tNO/no (default)\\n\\n"

	read -r "REMOVABLE_ARG" ; printf "\\n"
}

check_drive()
{
	printf "\\n\\tPreparing drives...\\n"

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

	if [[ "${ENTIRE_DRIVE}" == "/dev/nvme"* ]] ; then
		if [[ "${INSTALL_TYPE}" != "UEFI" ]] ; then
			printf "\\n\\tError: UEFI must be selected for NVMe.\\n"
			exit 1
		fi

		if [[ "${ENTIRE_DRIVE}" == *"p"* ]] ; then
			printf "\\n\\tError: NVMe Partition has been specified.\\n"
			exit 1
		fi

		# Used to determine if we need `p` used in partitions or not
		P="p"
	elif [[ "${ENTIRE_DRIVE}" == *[0-9]* ]] ; then
		printf "\\n\\tError: Partition has been specified.\\n"
		exit 1
	else
		P=""
	fi

	if [[ "${ENTIRE_DRIVE}" == "/dev/"* && \
		-b "${ENTIRE_DRIVE}" ]]
	then
		printf "\\tBlock device: %s is valid.\\n" "${ENTIRE_DRIVE}"
	else
		printf "\\n\\tError: Invalid block device: %s\\n" "${ENTIRE_DRIVE}"
		exit 1
	fi

	if ! grep -e "${ENTIRE_DRIVE}" "/proc/mounts" >> /dev/null 2>&1 && \
		! mount | grep "${ENTIRE_DRIVE}" >> /dev/null 2>&1
	then
		printf "\\tNo mount points found on: %s\\n" "${ENTIRE_DRIVE}"
	else
		printf "\\n\\tError: %s is or has partitions mounted.\\n" \
			"${ENTIRE_DRIVE}"
		exit 1
	fi

	printf "\\n\\tDone.\\n"

	# GRUB's `--removable` flag is only applicable to UEFI platforms
	if [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		removable_prompt

		if [[ "${REMOVABLE_ARG}" == "Y" || \
			"${REMOVABLE_ARG}" == "YES" || \
			"${REMOVABLE_ARG}" == "y" || \
			"${REMOVABLE_ARG}" == "yes" ]]
		then
			REMOVABLE="TRUE"
			printf "\\t%s: Removable media.
\\tWill pass \`--removable\` to UEFI GRUB installation.\\n" "${ENTIRE_DRIVE}"
		elif [[ "${REMOVABLE_ARG}" == "N" || \
			"${REMOVABLE_ARG}" == "NO" || \
			"${REMOVABLE_ARG}" == "n" || \
			"${REMOVABLE_ARG}" == "no" || \
			"${REMOVABLE_ARG}" == "DEFAULT" || \
			"${REMOVABLE_ARG}" == "default" || \
			-z "${REMOVABLE_ARG}" ]]
		then
			REMOVABLE="FALSE"
			printf "\\t%s: Persistent drive, non-removable.
\\tUsing standard UEFI GRUB installation.\\n" "${ENTIRE_DRIVE}"
		else
			printf "\\n\\tError: Invalid selection: %s\\n" \
				"${REMOVABLE_ARG}"
			exit 1
		fi
	else
		REMOVABLE="FALSE"
		printf "\\n\\tRemovable media not applicable.\\n"
	fi
}

choose_filesystem()
{
	printf "\\n\\tPlease select your choice of filesystem.
\\tFor NVMe and SSDs, F2FS may give best performance.\\n
\\tValid options (Enter for default):
\\t\\tBTRFS/btrfs
\\t\\tEXT4/ext4 (default for non-NVMe drives)
\\t\\tF2FS/f2fs (default for NVMe drives)
\\t\\tXFS/xfs\\n\\n"

	read -r "FSTYPE_ARG"

	if [[ "${FSTYPE_ARG}" == "BTRFS" || \
		"${FSTYPE_ARG}" == "btrfs" ]]
	then
		FSTYPE="BTRFS"
	elif [[ "${FSTYPE_ARG}" == "EXT4" || \
		"${FSTYPE_ARG}" == "ext4" || \
		"${FSTYPE_ARG}" == "DEFAULT" && \
		"${ENTIRE_DRIVE}" != "/dev/nvme"* || \
		"${FSTYPE_ARG}" == "default" && \
		"${ENTIRE_DRIVE}" != "/dev/nvme"* || \
		"${ENTIRE_DRIVE}" != "/dev/nvme"* && \
		-z "${FSTYPE_ARG}" ]]
	then
		FSTYPE="EXT4"
	elif [[ "${FSTYPE_ARG}" == "F2FS" || \
		"${FSTYPE_ARG}" == "f2fs" || \
		"${FSTYPE_ARG}" == "DEFAULT" && \
		"${ENTIRE_DRIVE}" == "/dev/nvme"* || \
		"${FSTYPE_ARG}" == "default" && \
		"${ENTIRE_DRIVE}" == "/dev/nvme"* || \
		"${ENTIRE_DRIVE}" == "/dev/nvme"* && \
		-z "${FSTYPE_ARG}" ]]
	then
		FSTYPE="F2FS"
	elif [[ "${FSTYPE_ARG}" == "XFS" || \
		"${FSTYPE_ARG}" == "xfs" ]]
	then
		FSTYPE="XFS"
	else
		printf "\\n\\tError: Invalid selection: %s\\n" "${FSTYPE_ARG}"
		exit 1
	fi

	printf "\\n\\tSelected filesystem: %s\\n" "${FSTYPE}"
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
	BOOT_PART_SIZE="500M"

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
		printf "\\n\\tError: Value: %s out of range.\\n" \
			"${HOME_PART_SIZE}"
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
		printf "\\n\\tError: Value: %s out of range.\\n" \
			"${ROOT_PART_SIZE}"
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

	printf "\\n\\tRemoving data on: %s\\n" "${ENTIRE_DRIVE}"

	if_log wipefs -a -f "${ENTIRE_DRIVE}" ; printf "\\n"

	if [[ "${ENTIRE_DRIVE}" == "/dev/nvme"* ]] ; then
		if_log blkdiscard "${ENTIRE_DRIVE}"
	else
		if_log dd if=/dev/zero of="${ENTIRE_DRIVE}" bs=8M count=16 \
			oflag=sync status=progress
	fi

	sleep 5 && sync

	printf "\\tDone.\\n"
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
\\tLinux home partition ( /home ): %sG ( %s )
\\tLinux root (x86-64) partition ( / ): %sG ( %s )\\n" \
	"${BOOT_PART_SIZE}" "${HOME_PART_SIZE}" "${FSTYPE}" \
	"${ROOT_PART_SIZE}" "${FSTYPE}"

	sfdisk_die()
	{
		printf "\\n\\tError: Failed to partition: %s\\n" \
			"${ENTIRE_DRIVE}" ;
		exit 1 ;
	}

	if [[ "${INSTALL_TYPE}" == "LEGACY" ]] ; then
		if_log sfdisk -w always -W always "${ENTIRE_DRIVE}" <<-EOF || \
			sfdisk_die

			label :gpt
			,"${BIOS_PART_SIZE}","${BIOS_GUID}"
			,"${BOOT_PART_SIZE}","${BOOT_GUID}"
			,"${HOME_PART_SIZE}G","${HOME_GUID}"
			,"${ROOT_PART_SIZE}G","${ROOT_GUID}"
		EOF
	elif [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		if_log sfdisk -w always -W always "${ENTIRE_DRIVE}" <<-EOF || \
			sfdisk_die

			label :gpt
			,"${EFI_PART_SIZE}","${EFI_GUID}"
			,"${BOOT_PART_SIZE}","${BOOT_GUID}"
			,"${HOME_PART_SIZE}G","${HOME_GUID}"
			,"${ROOT_PART_SIZE}G","${ROOT_GUID}"
		EOF
	fi

	if [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		EFI_PART="${ENTIRE_DRIVE}${P}1"
	fi

	BOOT_PART="${ENTIRE_DRIVE}${P}2"
	HOME_PART="${ENTIRE_DRIVE}${P}3"
	ROOT_PART="${ENTIRE_DRIVE}${P}4"

	# Required for properly parsing PARTUUIDs
	sleep 5 ; sync ; partprobe

	# Make sure all PARTUUIDs are valid before proceeding

	if [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		EFI_PARTUUID=$(lsblk -n -o PARTUUID "${EFI_PART}")

		if [[ $(grep -o "-" <<< "${EFI_PARTUUID}" | wc -l) -ne 4 ]] ; then
			printf "\\n\\tError: Invalid PARTUUID on: %s\\n" \
				"${EFI_PART}"
			exit 1
		fi
	fi

	BOOT_PARTUUID=$(lsblk -n -o PARTUUID "${BOOT_PART}")

	if [[ $(grep -o "-" <<< "${BOOT_PARTUUID}" | wc -l) -ne 4 ]] ; then
		printf "\\n\\tError: Invalid PARTUUID on: %s\\n" \
			"${BOOT_PART}"
		exit 1
	fi

	HOME_PARTUUID=$(lsblk -n -o PARTUUID "${HOME_PART}")

	if [[ $(grep -o "-" <<< "${HOME_PARTUUID}" | wc -l) -ne 4 ]] ; then
		printf "\\n\\tError: Invalid PARTUUID on: %s\\n" \
			"${HOME_PART}"
		exit 1
	fi

	ROOT_PARTUUID=$(lsblk -n -o PARTUUID "${ROOT_PART}")

	if [[ $(grep -o "-" <<< "${ROOT_PARTUUID}" | wc -l) -ne 4 ]] ; then
		printf "\\n\\tError: Invalid PARTUUID on: %s\\n" \
			"${ROOT_PART}"
		exit 1
	fi

	printf "\\n\\tDone.\\n"
}

format_partitions()
{
	printf "\\n\\tFormatting partitions...\\n\\n"

	# Only if UEFI is enabled do we format the first partition
	if [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		if_log mkfs.fat -F 32 "${EFI_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: FAT32\\n" \
				"${BOOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}
	fi

	if [[ "${FSTYPE}" == "BTRFS" ]] ; then
		if_log mkfs.btrfs "${BOOT_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${BOOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}

		if_log mkfs.btrfs "${HOME_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${HOME_PART}" "${FSTYPE}" ;
			exit 1 ;
		}

		if_log mkfs.btrfs "${ROOT_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${ROOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}
	elif [[ "${FSTYPE}" == "EXT4" ]] ; then
		if_log mkfs.ext4 "${BOOT_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${BOOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}

		if_log mkfs.ext4 "${HOME_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${HOME_PART}" "${FSTYPE}" ;
			exit 1 ;
		}

		if_log mkfs.ext4 "${ROOT_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${ROOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}
	elif [[ "${FSTYPE}" == "F2FS" ]] ; then
		F2FS_DEFAULTS="extra_attr,inode_checksum,sb_checksum"

		printf "\\tF2FS selected. Using safe defaults...\\n"
		# F2FS xattr currently not supported in GRUB, exclude for /boot
		# (no compression)
		if_log mkfs.f2fs "${BOOT_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${BOOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}

		if_log mkfs.f2fs -O "${F2FS_DEFAULTS}" "${HOME_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${HOME_PART}" "${FSTYPE}" ;
			exit 1 ;
		}

		if_log mkfs.f2fs -O "${F2FS_DEFAULTS}" "${ROOT_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${ROOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}
	elif [[ "${FSTYPE}" == "XFS" ]] ; then
		if_log mkfs.xfs "${BOOT_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${BOOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}

		if_log mkfs.xfs "${HOME_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${HOME_PART}" "${FSTYPE}" ;
			exit 1 ;
		}

		if_log mkfs.xfs "${ROOT_PART}" || \
		{
			printf "\\n\\tError: Failed to format: %s as: %s\\n" \
				"${ROOT_PART}" "${FSTYPE}" ;
			exit 1 ;
		}
	fi

	printf "\\tDone.\\n"
}

mount_init_filesystems()
{
	printf "\\n\\tPreparing for installation...\\n"

	printf "\\tEnsuring directory: %s does not exist...\\n" "${ROOT_MOUNT}"

	if [[ ! -d "${ROOT_MOUNT}" ]] ; then
		printf "\\tGood.\\n"
	else
		printf "\\n\\tError: Found: %s\\n" "${ROOT_MOUNT}"
		exit 1
	fi

	printf "\\tEnsuring directory: %s is unmounted...\\n" "${ROOT_MOUNT}"

	if ! grep -e "${ROOT_MOUNT}" "/proc/mounts" >> /dev/null 2>&1 && \
		! mount | grep "${ROOT_MOUNT}" >> /dev/null 2>&1
	then
		printf "\\tNo mount point found on: %s\\n" "${ROOT_MOUNT}"
	else
		printf "\\n\\tError: %s is mounted.\\n" "${ROOT_MOUNT}"
		exit 1
	fi

	# Some distros are OCD about mounting everything ASAP because ADHD
	printf "\\tEnsuring target media is still unmounted...\\n"

	if ! grep -e "${ENTIRE_DRIVE}" "/proc/mounts" >> /dev/null 2>&1 && \
		! mount | grep "${ENTIRE_DRIVE}" >> /dev/null 2>&1
	then
		printf "\\tNo mount points found on: %s\\n" "${ENTIRE_DRIVE}"
	else
		printf "\\n\\tError: %s is or has partitions mounted.\\n" \
			"${ENTIRE_DRIVE}"
		exit 1
	fi

	mkdir -p "${ROOT_MOUNT}" || \
	{
		printf "\\n\\tError: Failed to create: %s\\n" "${ROOT_MOUNT}" ;
		exit 1 ;
	}

	printf "\\tMounting root filesystem...\\n"

	mount "${ROOT_PART}" "${ROOT_MOUNT}" || \
	{
		printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
			"${ROOT_PART}" "${ROOT_MOUNT}" ;
		exit 1 ;
	}

	printf "\\tMounting boot filesystem...\\n"

	mkdir -p "${ROOT_MOUNT}/boot" || \
	{
		printf "\\n\\tError: Failed to create: %s\\n" \
			"${ROOT_MOUNT}/boot" ;
		exit 1 ;
	}

	mount "${BOOT_PART}" "${ROOT_MOUNT}/boot" || \
	{
		printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
			"${BOOT_PART}" "${ROOT_MOUNT}/boot" ;
		exit 1 ;
	}

	printf "\\tMounting home directory...\\n"

	mount "${HOME_PART}" "${ROOT_MOUNT}/home" || \
	{
		printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
			"${HOME_PART}" "${ROOT_MOUNT}/home" ;
		exit 1 ;
	}

	printf "\\n\\tDone.\\n"
}

fetch_stage4()
{
	printf "\\n\\tFetching Gentoo for LinuxCNC files.
\\tThis may take awhile...\\n"

	printf "\\tEntering directory: %s\\n" "${ROOT_MOUNT}"

	cd "${ROOT_MOUNT}" || \
	{
		printf "Failed to change directory to: %s\\n" "${ROOT_MOUNT}" ;
		exit 1 ;
	}

	# 10 second timeout, 5 tries
	if_log wget -T 10 -t 5 "${STAGE4_SRCURI}" || \
	{
		printf "\\n\\tError: Failed to fetch stage4 tarball.\\n" ;
		exit 1 ;
	}

	if_log wget -T 10 -t 5 "${STAGE4_CHECKSUM}" || \
	{
		printf "\\n\\tError: Failed to fetch stage4 checksum.\\n" ;
		exit 1 ;
	}

	printf "\\n\\tDone.\\n"
}

verify_stage4()
{
	printf "\\n\\tVerifying integrity of stage4 tarball...\\n"

	if [[ -r "${ROOT_MOUNT}/${STAGE4_NAME}.sha1sum" ]] ; then
		sha1sum -c "${ROOT_MOUNT}/${STAGE4_NAME}.sha1sum" || \
		{
			printf "\\n\\tError: Failed to verify checksum on: %s\\n" \
				"${ROOT_MOUNT}/${STAGE4_NAME}.tar.xz" 
			exit 1 ;
		}
	else
		printf "\\n\\tUnable to read checksum file: %s\\n" \
			"${ROOT_MOUNT}/${STAGE4_NAME}.sha1sum"
		exit 1
	fi

	printf "\\n\\tDone.\\n"
}

install_stage4()
{
	printf "\\n\\tInstalling Gentoo for LinuxCNC.
\\tThis may take awhile...\\n"

	if [[ -r "${ROOT_MOUNT}/${STAGE4_NAME}.tar.xz" ]] ; then
		tar --numeric-owner --xattrs-include='*.*' \
			-xpf "${ROOT_MOUNT}/${STAGE4_NAME}.tar.xz" -C "${ROOT_MOUNT}/" || \
			{
				printf "\\n\\tError: Failed to decompress: %s to: %s\\n" \
					"${ROOT_MOUNT}/${STAGE4_NAME}.tar.xz" "${ROOT_MOUNT}/" ;
				exit 1 ;
			}
	else
		printf "\\n\\tError: Unable to read stage4 tarball: %s\\n" \
			"${ROOT_MOUNT}/${STAGE4_NAME}.tar.xz"
	fi

	sleep 5 && sync

	printf "\\n\\tDone.\\n"
}

display_keepalive()
{
	printf "\\n\\tKilling all display power savings...\\n"

	mkdir -p "${HOME_MOUNT_SUBDIR}/.config/autostart" || \
	{
		printf "\\n\\tError: Failed to create: %s\\n" \
			"${HOME_MOUNT_SUBDIR}/.config/autostart" ;
		exit 1 ;
	}

	printf "[Desktop Entry]
Exec=xset s 0
Name=xset timeout
Type=Application
Version=1.0" &> "${HOME_MOUNT_SUBDIR}/.config/autostart/xset timeout.desktop"

	printf "[Desktop Entry]
Exec=xset s noblank
Name=xset noblank
Type=Application
Version=1.0" &> "${HOME_MOUNT_SUBDIR}/.config/autostart/xset noblank.desktop"

	printf "[Desktop Entry]
Exec=xset -dpms
Name=xset dpms
Type=Application
Version=1.0" &> "${HOME_MOUNT_SUBDIR}/.config/autostart/xset dpms.desktop"

	printf "\\tFixing permissions on autostart files...\\n"

	chroot "${ROOT_MOUNT}" /bin/bash <<-EOF
		chown -R "${HOME_USER}":"${HOME_USER}" "${HOME_MOUNT_SUBDIR}/.config" || \
		{
			printf "\\n\\tError: Failed to change permissions of: %s\\n" \
				"${HOME_MOUNT_SUBDIR}/.config" ;
			exit 1 ;
		}
	EOF

	printf "\\n\\tDone.\\n"
}

mount_final_filesystems()
{
	printf "\\n\\tMounting final filesystems for GRUB installation...\\n"

	if [[ "${INSTALL_TYPE}" == "LEGACY" ]] ; then
		mount --bind "/dev" "${ROOT_MOUNT}/dev" || \
		{
			printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
				"/dev" "${ROOT_MOUNT}/dev" ;
			exit 1 ;
		}

		mount --bind "/sys" "${ROOT_MOUNT}/sys" || \
		{
			printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
				"/sys" "${ROOT_MOUNT}/sys" ;
			exit 1 ;
		}
	elif [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		mkdir -p "${ROOT_MOUNT}/efi" || \
		{
			printf "\\n\\tError: Failed to create: %s\\n" \
				"${ROOT_MOUNT}/efi" ;
			exit 1 ;
		}

		mount "${EFI_PART}" "${ROOT_MOUNT}/efi" || \
		{
			printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
				"${EFI_PART}" "${ROOT_MOUNT}/efi" ;
			exit 1 ;
		}

		mount --rbind "/dev" "${ROOT_MOUNT}/dev" || \
		{
			printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
				"/dev" "${ROOT_MOUNT}/dev" ;
			exit 1 ;
		}

		mount --rbind "/sys" "${ROOT_MOUNT}/sys" || \
		{
			printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
				"/sys" "${ROOT_MOUNT}/sys" ;
			exit 1 ;
		}
	fi

	mount -t proc none "${ROOT_MOUNT}/proc" || \
	{
		printf "\\n\\tError: Failed to mount proc filesystem to: %s\\n" \
			"${ROOT_MOUNT}/proc" ;
		exit 1 ;
	}

	mount --bind "/run" "${ROOT_MOUNT}/run" || \
	{
		printf "\\n\\tError: Failed to mount: %s to: %s\\n" \
			"/run" "${ROOT_MOUNT}/run" ;
		exit 1 ;
	}

	printf "\\n\\tDone.\\n"
}

generate_fstab()
{
	printf "\\n\\tGenerating fstab file...\\n"

	# Safe defaults for F2FS (no compression)
	if [[ "${FSTYPE}" == "F2FS" ]] ; then
		F2FS_MOUNT_OPTS="atgc,gc_merge,lazytime"
	fi

	printf "%b\\n" \
"# /etc/fstab: static file system information.
#
# noatime turns off atimes for increased performance.
#
# The root filesystem should have a pass number of either 0 or 1.
# All other filesystems should have a pass number of 0 or greater than 1.
#
# See the manpage fstab(5) for more information.
#\\n" &> "${ROOT_MOUNT}/etc/fstab"

	printf "%b\\n" \
"# <fs>\\t\\t\\t\\t\\t\\t<mountpoint>\\t<type>\\t<opts>\\t\\t<dump/pass>" \
	>> "${ROOT_MOUNT}/etc/fstab"

	# LEGACY + BTRFS
	if [[ "${INSTALL_TYPE}" == "LEGACY" && \
		"${FSTYPE}" == "BTRFS" ]]
	then
		printf "%b\\n" \
"PARTUUID=${BOOT_PARTUUID}\\t/boot\\t\\tbtrfs\\tdefaults\\t0\\t2
PARTUUID=${HOME_PARTUUID}\\t/home\\t\\tbtrfs\\tdefaults\\t0\\t2
PARTUUID=${ROOT_PARTUUID}\\t/\\t\\tbtrfs\\tdefaults\\t0\\t1" \
	>> "${ROOT_MOUNT}/etc/fstab"

	# LEGACY + EXT4
	elif [[ "${INSTALL_TYPE}" == "LEGACY" && \
		"${FSTYPE}" == "EXT4" ]]
	then
		printf "%b\\n" \
"PARTUUID=${BOOT_PARTUUID}\\t/boot\\t\\text4\\tdefaults\\t0\\t2
PARTUUID=${HOME_PARTUUID}\\t/home\\t\\text4\\tdefaults\\t0\\t2
PARTUUID=${ROOT_PARTUUID}\\t/\\t\\text4\\tdefaults\\t0\\t1" \
	>> "${ROOT_MOUNT}/etc/fstab"

	# LEGACY + F2FS
	elif [[ "${INSTALL_TYPE}" == "LEGACY" && \
		"${FSTYPE}" == "F2FS" ]]
	then
		printf "%b\\n" \
"PARTUUID=${BOOT_PARTUUID}\\t/boot\\t\\tf2fs\\t${F2FS_MOUNT_OPTS}\\t0\\t2
PARTUUID=${HOME_PARTUUID}\\t/home\\t\\tf2fs\\t${F2FS_MOUNT_OPTS}\\t0\\t2
PARTUUID=${ROOT_PARTUUID}\\t/\\t\\tf2fs\\t${F2FS_MOUNT_OPTS}\\t0\\t1" \
	>> "${ROOT_MOUNT}/etc/fstab"

	# LEGACY + XFS
	elif [[ "${INSTALL_TYPE}" == "LEGACY" && \
		"${FSTYPE}" == "XFS" ]]
	then
		printf "%b\\n" \
"PARTUUID=${BOOT_PARTUUID}\\t/boot\\t\\txfs\\tdefaults\\t0\\t2
PARTUUID=${HOME_PARTUUID}\\t/home\\t\\txfs\\tdefaults\\t0\\t2
PARTUUID=${ROOT_PARTUUID}\\t/\\t\\txfs\\tdefaults\\t0\\t1" \
	>> "${ROOT_MOUNT}/etc/fstab"

	# UEFI + BTRFS
	elif [[ "${INSTALL_TYPE}" == "UEFI" && \
		"${FSTYPE}" == "BTRFS" ]]
	then
		printf "%b\\n" \
"PARTUUID=${EFI_PARTUUID}\\t/efi\\t\\tvfat\\tdefaults\\t0\\t2
PARTUUID=${BOOT_PARTUUID}\\t/boot\\t\\tbtrfs\\tdefaults\\t0\\t2
PARTUUID=${HOME_PARTUUID}\\t/home\\t\\tbtrfs\\tdefaults\\t0\\t2
PARTUUID=${ROOT_PARTUUID}\\t/\\t\\tbtrfs\\tdefaults\\t0\\t1" \
	>> "${ROOT_MOUNT}/etc/fstab"

	# UEFI + EXT4
	elif [[ "${INSTALL_TYPE}" == "UEFI" && \
		"${FSTYPE}" == "EXT4" ]]
	then
		printf "%b\\n" \
"PARTUUID=${EFI_PARTUUID}\\t/efi\\t\\tvfat\\tdefaults\\t0\\t2
PARTUUID=${BOOT_PARTUUID}\\t/boot\\t\\text4\\tdefaults\\t0\\t2
PARTUUID=${HOME_PARTUUID}\\t/home\\t\\text4\\tdefaults\\t0\\t2
PARTUUID=${ROOT_PARTUUID}\\t/\\t\\text4\\tdefaults\\t0\\t1" \
	>> "${ROOT_MOUNT}/etc/fstab"

	# UEFI + F2FS
	elif [[ "${INSTALL_TYPE}" == "UEFI" && \
		"${FSTYPE}" == "F2FS" ]]
	then
		printf "%b\\n" \
"PARTUUID=${EFI_PARTUUID}\\t/efi\\t\\tvfat\\tdefaults\\t0\\t2
PARTUUID=${BOOT_PARTUUID}\\t/boot\\t\\tf2fs\\t${F2FS_MOUNT_OPTS}\\t0\\t2
PARTUUID=${HOME_PARTUUID}\\t/home\\t\\tf2fs\\t${F2FS_MOUNT_OPTS}\\t0\\t2
PARTUUID=${ROOT_PARTUUID}\\t/\\t\\tf2fs\\t${F2FS_MOUNT_OPTS}\\t0\\t1" \
	>> "${ROOT_MOUNT}/etc/fstab"

	# UEFI + XFS
	elif [[ "${INSTALL_TYPE}" == "UEFI" && \
		"${FSTYPE}" == "XFS" ]]
	then
		printf "%b\\n" \
"PARTUUID=${EFI_PARTUUID}\\t/efi\\t\\tvfat\\tdefaults\\t0\\t2
PARTUUID=${BOOT_PARTUUID}\\t/boot\\t\\txfs\\tdefaults\\t0\\t2
PARTUUID=${HOME_PARTUUID}\\t/home\\t\\txfs\\tdefaults\\t0\\t2
PARTUUID=${ROOT_PARTUUID}\\t/\\t\\txfs\\tdefaults\\t0\\t1" \
	>> "${ROOT_MOUNT}/etc/fstab"
	fi
}

install_grub()
{
	printf "\\n\\tInstalling GRUB...\\n"

	if [[ "${INSTALL_TYPE}" == "LEGACY" ]] ; then
		chroot "${ROOT_MOUNT}" /bin/bash <<-EOF
			grub-install --no-floppy --recheck "${ENTIRE_DISK}" || \
			{
				printf "\\n\\tError: Failed to install legacy GRUB.\\n" ;
				exit 1 ;
			}
		EOF
	elif [[ "${INSTALL_TYPE}" == "UEFI" && \
		"${REMOVABLE}" == "FALSE" ]]
	then
		chroot "${ROOT_MOUNT}" /bin/bash <<-EOF
			grub-install --target=x86_64-efi --efi-directory=/efi || \
			{
				printf "\\n\\tError: Failed to install UEFI GRUB.\\n" ;
				exit 1 ;
			}
		EOF
	elif [[ "${INSTALL_TYPE}" == "UEFI" && \
		"${REMOVABLE}" == "TRUE" ]]
	then
		chroot "${ROOT_MOUNT}" /bin/bash <<-EOF
			grub-install --target=x86_64-efi --efi-directory=/efi --removable || \
			{
				printf "\\n\\tError: Failed to install UEFI GRUB (--removable)\\n" ;
				exit 1 ;
			}
		EOF
	fi

	if [[ "${FSTYPE}" == "F2FS" ]] ; then
		printf "\\tFixing kernel parameters for F2FS...\\n"

		sed -i "s/#GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"rootflags=atgc\"/" \
			"${ROOT_MOUNT}/etc/default/grub"
	fi

	printf "\\tGenerating grub.cfg via grub-mkconfig...\\n"

	chroot "${ROOT_MOUNT}" /bin/bash <<-EOF
		grub-mkconfig -o /boot/grub/grub.cfg
	EOF

	sleep 5 && sync

	printf "\\n\\tDone.\\n"
}

unmount_all()
{
	printf "\\n\\tUnmouting filesystems...\\n"

	if [[ "${INSTALL_TYPE}" == "UEFI" ]] ; then
		umount "${EFI_PART}" || \
		{
			printf "\\n\\tError: Failed to unmount: %s\\n" \
				"${EFI_PART}" ;
			exit 1 ;
		}
	fi

	# These can fail
	set +e
	umount -l "${ROOT_MOUNT}/dev"
	umount -l "${ROOT_MOUNT}/sys"
	umount -l "${ROOT_MOUNT}/proc"
	umount -l "${ROOT_MOUNT}/run"
	set -e

	umount "${BOOT_PART}" || \
	{
		printf "\\n\\tError: Failed to unmount: %s\\n" \
			"${BOOT_PART}" ;
		exit 1 ;
	}

	sleep 5 && sync

	# Required for unmounting root partition
	cd

	umount "${ROOT_PART}" || \
	{
		printf "\\n\\tError: Failed to unmount: %s\\n" \
			"${ROOT_PART}" ;
		exit 1 ;
	}

	printf "\\n\\tDone.\\n"
}

cleanup()
{
	printf "\\n\\tCleaning up...\\n"

	rm -d "${ROOT_MOUNT}" || \
	{
		printf "\\n\\tError: Failed to remove non-empty directory: %s\\n" \
			"${ROOT_MOUNT}"
		exit 1
	}

	printf "\\n\\tDone.\\n"
}

verify_psabi

check_deps

legacy_or_uefi

check_drive

choose_filesystem

partition_sizes

wipe_drive

partition_drive

format_partitions

mount_init_filesystems

fetch_stage4

verify_stage4

install_stage4

display_keepalive

mount_final_filesystems

generate_fstab

install_grub

unmount_all

cleanup
