#!/usr/bin/env bats
# 
#+Bats tests for qcrypt.
#+
#+Copyright (C) 2019  David Hobach  GPLv3
#+0.6

load "test_common"

#size of the containers to test luksInit with in MB
QCRYPT_CSIZE="5"
QCRYPT_CSIZE_BYTES="$(( $QCRYPT_CSIZE * 1024 * 1024 ))"

function setup {
	setupQcryptTesting 
}

@test "usage" {
	runSL "$QCRYPT"
	[ $status -ne 0 ]
	[[ "$output" == *"Usage: qcrypt"* ]]
	[[ "$output" == *"open"* ]]
	[[ "$output" == *"status"* ]]
	[[ "$output" == *"luksInit"* ]]
	[[ "$output" == *"close"* ]]
	[[ "$output" == *"help"* ]]

	#some with incorrect parameters
	runSL "$QCRYPT" open -rincorrect -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/pstest" "tstkey-ps" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[ -n "$output" ]

	runSL "$QCRYPT" invalidCmd
	[ $status -ne 0 ]
	[[ "$output" == *"Usage: "* ]]

	runSL "$QCRYPT" close --
	[ $status -ne 0 ]
	[ -n "$output" ]
}

#postInitChecks [working dir] [key backup dir] [key size] [expected md5 sums] [src vm] [src file] [key] [dst vm 1] ... [dst vm n]
#[key backup dir]: Must _only_ contain keys that are related to the last init. Otherwise this check may fail.
#[key size]: optional
#[expected md5 sums]: optional
function postInitChecks {
	local wd="$1"
	local bak="$2"
	local keySize="${3:-100}"
	local eMd5s="$4"
	local src="$5"
	local srcFile="$6"
	local key="$7"
	shift 7

	#compute the key md5s in dom0
	local keyMd5s="$(md5sum "$bak"/* | cut -f1 -d' ')"
	if [ -n "$eMd5s" ] ; then
		[[ "$keyMd5s" == "$eMd5s" ]]
	fi

	#ensure working dir is empty
	[ -d "$wd" ]
	runSL ls -1 "$wd"
	[ $status -eq 0 ]
	[ -z "$output" ]

	#ensure the source VM received the source container in the right place and of the right size
	local srcFileEsc=
	printf -v srcFileEsc '%q' "$srcFile"
	runSL b_dom0_qvmRun "$src" "stat -c %s $srcFileEsc"
	[ $status -eq 0 ]
	[[ "$output" == "$QCRYPT_CSIZE_BYTES" ]]

	#check backed up key size & #keys
	local bfile=
	local cnt=0
	for bfile in "$bak"/* ; do
		[[ "$bfile" == *"*" ]] && continue
		[ -z "$bfile" ] && continue
		[ -f "$bfile" ]
		cnt=$(( $cnt +1 ))
		local bfSize="$(stat -c %s "$bfile")"
		[ $bfSize -eq $keySize ]
	done
	[ $cnt -eq $# ]

	#check md5s in VMs to match the ones in dom0
	local vm=
	for vm in "$@" ; do
		local keyFolder="$(getQcryptKeyFolder "$vm")"
		runSL b_dom0_qvmRun "$vm" "md5sum $keyFolder/$key | cut -f1 -d' '"
		echo "ref MD5s:"
		echo "$keyMd5s"
		echo "$vm MD5s:"
		echo "$output"
		[ $status -eq 0 ]
		[ -n "$output" ]

		runSL b_listContains "$keyMd5s" "$output"
		[ $status -eq 0 ]
		[ -z "$output" ]
	done

	return 0
}

@test "luksInit (have a coffee...)" {
	skipIfNotRoot

	#failing tests
	
	#nonexisting VMs
	runSL "$QCRYPT" "luksInit" -- "nonex-src" "/tmp/foobar" "tstkey" "dst1" "dst2"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	runSL "$QCRYPT" "luksInit" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/foobar" "tstkey" "nonexisting-dst1"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#existing VMs, not overwriting files
	runSL "$QCRYPT" "luksInit" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/etc/hosts" "host-test-key" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#shut down VMs
	qvm-shutdown --wait "$UTD_QUBES_TESTVM"
	runSL b_dom0_isRunning "$UTD_QUBES_TESTVM"
	[ $status -ne 0 ]

	runSL "$QCRYPT" "luksInit" -- "$UTD_QUBES_TESTVM" "/tmp/rand" "tstkey" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#make sure the above didn't start anything
	sleep 1
	runSL b_dom0_isRunning "$UTD_QUBES_TESTVM"
	[ $status -ne 0 ]

	runSL "$QCRYPT" "luksInit" -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/rand" "tstkey" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#make sure the above didn't start anything
	sleep 1
	runSL b_dom0_isRunning "$UTD_QUBES_TESTVM"
	[ $status -ne 0 ]

	#(mostly) succeeding tests
	
	#NOTE: dm-crypt requires at least ~5M containers
	local wd="$(mktemp -d)"
	local bak="$(mktemp -d)"
	local s="${QCRYPT_CSIZE}M"
	runSL "$QCRYPT" "luksInit" -s "$s" -wd "$wd" -bak "$bak" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/foobar" "tstkey" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -eq 0 ]
	[ -n "$output" ]
	[[ "$output" != *"ERROR"* ]]
	local keyMd5="$(md5sum "$bak"/* | cut -f1 -d ' ')"
	postInitChecks "$wd" "$bak" "" "" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/foobar" "tstkey" "${TEST_STATE["QCRYPT_VM_2"]}"

	#key overwrite shouldn't happen
	#NOTE: container overwrite was checked above already
	runSL "$QCRYPT" "luksInit" -s "$s" -wd "$wd" -bak "$bak" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/foobar2" "tstkey" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]
	#make sure that nothing changed with the old directories
	postInitChecks "$wd" "$bak" "" "$keyMd5" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/foobar" "tstkey" "${TEST_STATE["QCRYPT_VM_2"]}"

	#try again with empty bak
	local bak2="$(mktemp -d)"
	runSL "$QCRYPT" "luksInit" -s "$s" -wd "$wd" -bak "$bak2" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/foobar3" "tstkey" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]
	#make sure that nothing changed with the old directories
	postInitChecks "$wd" "$bak" "" "$keyMd5" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/foobar" "tstkey" "${TEST_STATE["QCRYPT_VM_2"]}"

	runSL ls -1 "$bak2"
	[ $status -eq 0 ]
	[ -z "$output" ]

	#autostart
	runSL b_dom0_isRunning "$UTD_QUBES_TESTVM"
	[ $status -ne 0 ]

	rm -f "$bak"/*
	runSL "$QCRYPT" "luksInit" -s "$s" -wd "$wd" -a -bak "$bak" -- "$UTD_QUBES_TESTVM" "/tmp/foobar" "tstkey2" "${TEST_STATE["QCRYPT_VM_1"]}"
	echo "$output"
	[ $status -eq 0 ]
	[ -n "$output" ]
	[[ "$output" != *"ERROR"* ]]
	postInitChecks "$wd" "$bak" "" "" "$UTD_QUBES_TESTVM" "/tmp/foobar" "tstkey2" "${TEST_STATE["QCRYPT_VM_1"]}"

	runSL b_dom0_isRunning "$UTD_QUBES_TESTVM"
	[ $status -eq 0 ]

	#different key size, cryptsetup parameter & 2 layers
	rm -f "$bak"/*
	runSL "$QCRYPT" "luksInit" --hash sha256 -s "$s" -k 70 -wd "$wd" -bak "$bak" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -eq 0 ]
	[ -n "$output" ]
	[[ "$output" != *"ERROR"* ]]
	postInitChecks "$wd" "$bak" 70 "" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	
	#test open & close for the one we just initiated
	echo "open & close checks for the container that was just created:"
	runSL "$QCRYPT" open -mp "/mnt" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Open done."* ]]
	[[ "$output" != *"ERROR"* ]]
	postOpenChecks 1 1 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"

	#test close
	runSL "$QCRYPT" close -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Close done."* ]]
	[[ "$output" != *"ERROR"* ]]
	postCloseChecks 0 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"

	#reopen to check whether the file we created after the first open is still there
	runSL "$QCRYPT" open -mp "/mnt" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Open done."* ]]
	[[ "$output" != *"ERROR"* ]]
	postOpenChecks 1 0 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"

	runSL "$QCRYPT" close -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Close done."* ]]
	[[ "$output" != *"ERROR"* ]]
	postCloseChecks 0 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/kstest" "tstkey-ks" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"

	#cleanup
	rm -rf "$bak" "$bak2" "$wd"
}

@test "open (have another coffee...)" {
	#NOTE: luksInit didn't necessarily run, if we're not root --> we cannot depend on it (that's also why open & close are tested there as well)
	local fixturePath="$(getFixturePath "1layer01")"
	
	#non-existing source VM
	runSL "$QCRYPT" open -mp "/mnt" -- "nonexisting-src" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#missing key
	copyFixture "1layer01" "${TEST_STATE["QCRYPT_VM_1"]}"
	runSL "$QCRYPT" open -mp "/mnt" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#missing source container
	runSL "$QCRYPT" open -inj "${TEST_STATE["QCRYPT_VM_2"]}" "$fixturePath/keys/target" -mp "/mnt" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/nonexisting" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#incorrect target
	runSL "$QCRYPT" open -inj "${TEST_STATE["QCRYPT_VM_2"]}" "$fixturePath/keys/target" -mp "/mnt" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "nonexisting-target"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#correct open with a single layer
	runSL "$QCRYPT" open -inj "${TEST_STATE["QCRYPT_VM_2"]}" "$fixturePath/keys/target" -mp "/mnt" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Open done."* ]]
	[[ "$output" != *"ERROR"* ]]
	postOpenChecks 1 0 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	
	#correct open with two layers, r/o and call syntax as in help
	copyFixture "2layer01" "${TEST_STATE["QCRYPT_VM_1"]}"
	local fixturePath="$(getFixturePath "2layer01")"
	runSL "$QCRYPT" -a --ro -inj "${TEST_STATE["QCRYPT_VM_2"]}" "$fixturePath/keys/middle" -inj "$UTD_QUBES_TESTVM" "$fixturePath/keys/target" -mp "/mnt" open "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Open done."* ]]
	[[ "$output" != *"ERROR"* ]]
	postOpenChecks 0 0 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
}

function testStatusAll {
	runSL "$QCRYPT" status
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" != *"ERROR"* ]]

	local re=
	re="${TEST_STATE["QCRYPT_VM_1"]}\:loop0 \-\-> ${TEST_STATE["QCRYPT_VM_2"]}\:[a-z0-9\-]+ \(r/w\)"
	echo "$re"
	[[ "$output" =~ $re ]]
	re="qcrypt status -- ${TEST_STATE["QCRYPT_VM_1"]} /tmp/1layer01 (UNKNOWN-KEY|1layer01) ${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$re"
	[[ "$output" =~ $re ]]
	re="${TEST_STATE["QCRYPT_VM_1"]}\:loop1 \-\-> ${TEST_STATE["QCRYPT_VM_2"]}\:dm-1 --> ${UTD_QUBES_TESTVM}\:xvdi \(r/o\)"
	echo "$re"
	[[ "$output" =~ $re ]]
	re="qcrypt status -- ${TEST_STATE["QCRYPT_VM_1"]} /tmp/2layer01 2layer01 ${TEST_STATE["QCRYPT_VM_2"]} ${UTD_QUBES_TESTVM}"
	echo "$re"
	[[ "$output" =~ $re ]]
}

@test "status - all" {
	testStatusAll

	#Qubes OS qvm-block ls has a slightly different output when the target device is not mounted --> we need to test that as well
	#update: apparently not (unsure as to why it sometimes has the last hop and sometimes not), but we can check for the future ^^
	runSL b_dom0_qvmRun "$UTD_QUBES_TESTVM" "umount /mnt"
	[ $status -eq 0 ]
	[ -z "$output" ]

	testStatusAll

	#cleanup
	runSL b_dom0_qvmRun "$UTD_QUBES_TESTVM" "mount /dev/mapper/2layer01 /mnt"
	echo "$output"
	[ $status -eq 0 ]
}

#testSuccStatus [# of dst VMs] [status parameters]
function testSuccStatus {
	local re=
	local dstCnt="$1"
	shift

	runSL "$QCRYPT" status "$@"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" != *"no"* ]]
	[[ "$output" == *"yes"* ]]
	re='device mounted:[[:space:]]+yes'
	[[ "$output" =~ $re ]]
	re='source:[[:space:]]+file, loop device'
	[[ "$output" =~ $re ]]

	#count all "yes"
	local yesCnt="$(echo "$output" | grep -E '\s\syes\s' | wc -l)"
	local maxCnt=$(( $dstCnt * 4 +2 ))
	echo "yesCnt = $yesCnt"
	echo "maxCnt = $maxCnt"
	[ $yesCnt -eq $maxCnt ]

	return 0
}

#testFailStatus [expected status] [# of dst VMs] [status parameters]
function testFailStatus {
	local eStatus="$1"
	local dstCnt="$2"
	shift 2
	runSL "$QCRYPT" status "$@"
	echo "$output"
	[ $status -ne 0 ]
	
	if [ -n "$eStatus" ] ; then
		[ $status -eq $eStatus ]
	fi

	[[ "$output" == *"no"* ]] || [[ "$output" == *"ERROR"* ]] || [[ "$output" == *"Usage: qcrypt"* ]]

	if [[ "$output" != *"ERROR"* ]] && [[ "$output" != *"Usage"* ]] ; then
		local yesCnt="$(echo "$output" | grep -E '\s\s+yes\s+' | wc -l)"
		local maxCnt=$(( $dstCnt * 4 +2 ))
		local noCnt="$(echo "$output" | grep -E '\s\s+no\s+' | wc -l)"
		echo "yesCnt = $yesCnt"
		echo "noCnt = $noCnt"
		echo "maxCnt = $maxCnt"
		echo "status = $status"

		[ $yesCnt -ge 0 ]
		[ $yesCnt -lt $maxCnt ]

		[ $noCnt -gt 0 ]
		[ $(( $yesCnt + $noCnt )) -eq $maxCnt ]

		[ $status -ge $noCnt ]
	fi
	
	return 0
}

@test "status - single" {
	#correct status for the two open chains
	testSuccStatus 1 -mp "/mnt" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	testSuccStatus 2 -mp "/mnt" -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	testSuccStatus 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	testSuccStatus 2 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"

	#status should also work with // somewhere (happens quite often in programs)
	testSuccStatus 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "//tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	testSuccStatus 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp//1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	testSuccStatus 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "//tmp//1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	
	
	#status for invalid & incomplete chains
	testFailStatus "" 1 -- "nonexisting-src" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	testFailStatus "" 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "nonexisting-dst"
	testFailStatus "" 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "invalid-key" "${TEST_STATE["QCRYPT_VM_2"]}"
	testFailStatus "" 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/nonexisting" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	testFailStatus "" 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01"
	testFailStatus "" 2 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "nonexisting-key" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	testFailStatus "" 1 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	testFailStatus "" 1 -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/2layer01" "2layer01" "$UTD_QUBES_TESTVM"
	testFailStatus "" 2 -- "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_1"]}" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	testFailStatus "" 2 -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_1"]}" "$UTD_QUBES_TESTVM"
	testFailStatus "" 3 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "incorr-vm" "$UTD_QUBES_TESTVM"
	testFailStatus "" 3 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM" "incorr-vm"
	
	#partially close & check status (the close test below should work with partial closes anyway)
	runSL b_dom0_qvmRun "$UTD_QUBES_TESTVM" "umount /mnt"
	[ $status -eq 0 ]
	[ -z "$output" ]
	testFailStatus 1 2 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	runSL b_dom0_qvmRun "$UTD_QUBES_TESTVM" "cryptsetup close /dev/mapper/2layer01"
	[ $status -eq 0 ]
	[ -z "$output" ]
	testFailStatus 2 2 -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
}

@test "close" {
	#invalid options
	runSL "$QCRYPT" close -invalid -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" != *"Close done."* ]]
	
	#wrong src VM
	runSL "$QCRYPT" close -- "$UTD_QUBES_TESTVM" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]
	
	#wrong target VM
	runSL "$QCRYPT" close -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]
	
	#wrong key
	runSL "$QCRYPT" close -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "invalidkey" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#wrong source file
	runSL "$QCRYPT" close -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/foobar" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#make sure the closes above didn't have an effect
	postOpenChecks 1 0 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"

	#successful close with the ones that were opened during the open test
	runSL "$QCRYPT" close -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Close done."* ]]
	[[ "$output" != *"ERROR"* ]]
	postCloseChecks 0 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"

	#partial closes shouldn't work
	runSL "$QCRYPT" close -sd -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	runSL "$QCRYPT" close -sd -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	runSL "$QCRYPT" close -sd -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/2layer01" "2layer01" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	#for some reason this currently requires -sd (which is strange since it works @luksInit): otherwise I keep getting a libxenlight error
	#we need --force because it was partially closed by the status test
	#TODO: identify the root cause
	runSL "$QCRYPT" close --force -sd -- "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Close done."* ]]
	[[ "$output" != *"ERROR"* ]]
	
	#sleep 2
	#if qvm-check --running "${TEST_STATE["QCRYPT_VM_1"]}" && qvm-check --running "${TEST_STATE["QCRYPT_VM_2"]}" && qvm-check --running "$UTD_QUBES_TESTVM" ; then
	#	postCloseChecks 0 "/mnt" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/2layer01" "2layer01" "${TEST_STATE["QCRYPT_VM_2"]}" "$UTD_QUBES_TESTVM"
	#fi
}

@test "partial close (VM down)" {
	#this deserves an extra test as it is _very_ important for qcryptd

	#open, this time VM_2 as source --> VM_1
	copyFixture "1layer01" "${TEST_STATE["QCRYPT_VM_2"]}"
	runSL "$QCRYPT" open --ro -inj "${TEST_STATE["QCRYPT_VM_1"]}" "$(getFixturePath "1layer01/keys/target")" -mp "/mntpartial" -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_1"]}"
	echo "$output"
	[ $status -eq 0 ]
	[[ "$output" == *"Open done."* ]]
	[[ "$output" != *"ERROR"* ]]
	postOpenChecks 1 0 "/mntpartial" "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_1"]}"
	testSuccStatus 1 -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_1"]}"

	run qvm-shutdown --timeout 10 --wait "${TEST_STATE["QCRYPT_VM_1"]}"
	echo "$output"
	runSL b_dom0_isRunning "${TEST_STATE["QCRYPT_VM_1"]}"
	echo "$output"
	[ $status -ne 0 ]

	#status should not just error out
	testFailStatus 5 1 -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_1"]}"
	[[ "$output" != *"ERROR"* ]]

	#partial close should work
	#(status will be nonzero though as the close is only partial)
	runSL "$QCRYPT" close --force -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_1"]}"
	echo "$output"
	[ $status -ne 0 ]
	[[ "$output" == *"Close done."* ]]
	[[ "$output" != *"ERROR"* ]]

	testFailStatus 6 1 -- "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/1layer01" "1layer01" "${TEST_STATE["QCRYPT_VM_1"]}"
	[[ "$output" != *"ERROR"* ]]
}

@test "cleanup" {
	runCleanup
}
