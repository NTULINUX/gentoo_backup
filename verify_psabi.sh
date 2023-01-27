#!/usr/bin/env bash

# Checks for x86-64-v2 psABI support
# Written by Alec Ari

set -eou pipefail

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

exit 0
