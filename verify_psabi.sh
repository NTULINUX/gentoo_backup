#!/usr/bin/env bash

# Checks for x86-64-v3 psABI support
# Written by Alec Ari

set -eou pipefail

	printf "\\n\\tChecking CPU requirements...\\n"

	X86_64_V3="
		abm
		avx
		avx2
		bmi1
		bmi2
		f16c
		fma
		mmx
		movbe
		pni
		popcnt
		sse
		sse2
		ssse3
		sse4_1
		sse4_2
		xsave
	"

	mapfile -s 1 -t FLAGS < <(printf "%s" "${X86_64_V3}" | sed 's/\t//g')

	for (( i=0 ; i < "${#FLAGS[@]}" ; i++ )) ; do
		printf "\\tChecking for: %s\\n" "${FLAGS[$i]}"

		lscpu | grep -o " ${FLAGS[$i]} " >> /dev/null 2>&1 || \
		{
			printf "\\tError: Missing: %s\\n" "${FLAGS[$i]}" ;
			exit 1 ;
		}
	done

	printf "\\n\\tDone. Your processor is x86-64-v3 or newer.\\n"
	printf "\\tYou may safely use the Gentoo image for LinuxCNC.\\n"

exit 0
