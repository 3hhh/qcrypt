#!/usr/bin/env bats
# 
#+Bats tests for qcryptd. These tests assume that qcrypt is working correctly (qcrypt.bats ran successfully).
#+
#+Copyright (C) 2019  David Hobach  GPLv3
#+0.5

load "test_common"

#used by the start test & its helper functions
OUT_NONEXISTING=
OUT_DEST_DOWN=
OUT_DEV_MISSING=

function setup {
	setupQcryptTesting 
}

@test "usage" {
	runSL "$QCRYPTD"
	[ $status -ne 0 ]
	[[ "$output" == *"Usage: qcryptd"* ]]
	[[ "$output" == *"start"* ]]
	[[ "$output" == *"status"* ]]
	[[ "$output" == *"stop"* ]]
	[[ "$output" == *"restart"* ]]
	[[ "$output" == *"check"* ]]
	[[ "$output" == *"help"* ]]

	runSL "$QCRYPTD" "help"
	[ $status -ne 0 ]
	[[ "$output" == *"Usage: qcryptd"* ]]

	runSL "$QCRYPTD" incorrectCmd
	[ $status -ne 0 ]
	[ -n "$output" ]

	runSL "$QCRYPTD" --qincorrect status
	[ $status -ne 0 ]
	[ -n "$output" ]

	runSL "$QCRYPTD" --qincorrect start
	[ $status -ne 0 ]
	[ -n "$output" ]

	runSL "$QCRYPTD" -v --qincorrect stop
	[ $status -ne 0 ]
	[ -n "$output" ]

	runSL "$QCRYPTD" --qincorrect -v check
	[ $status -ne 0 ]
	[ -n "$output" ]
}

@test "check" {
	runSL "$QCRYPTD" check "nonexisting"
	[ $status -ne 0 ]
	[ -n "$output" ]

	#invalid configs
	local i=
	for ((i=1;i<=6;i++)) ; do
		runSL "$QCRYPTD" -v check "test-invalid-0$i"
		echo "$output"
		[[ "$output" == *"ERROR"* ]]
		[[ "$output" != *"All good."* ]]
		[ $status -ne 0 ]
	done

	#valid configs
	local validConfs=("examples" "test-valid-01" "test-valid-02" "test-valid-03")
	local conf=
	for conf in "${validConfs[@]}" ; do
		runSL "$QCRYPTD" -v check "$conf"
		echo "$output"
		[[ "$output" != *"ERROR"* ]]
		[[ "$output" == *"All good."* ]]
		[ $status -eq 0 ]
	done
}

@test "config parsing" {
	runSL "$QCRYPTD" check -v "test-valid-03"
	[[ "$output" != *"ERROR"* ]]
	[[ "$output" == *"All good."* ]]
	[ $status -eq 0 ]
	local decl="$(echo "$output" | grep "declare" | grep -v "VMS2CHAINS")"
	echo "$decl"
	eval "$decl"

	[[ "${CHAINS[0]}" == "ex01" ]]
	[[ "${CHAINS[1]}" == "valid03" ]]
	echo 0	

	#ex01 chain
	local chain="ex01"
	[[ "${CHAINS2INFO["${chain}_source vm"]}" == "sys-usb" ]]
	[[ "${CHAINS2INFO["${chain}_source device"]}" == "/dev/disk/by-uuid/8c3663c5-b9345-6381-9a67-dd813eb12863" ]]
	[[ "${CHAINS2INFO["${chain}_source mount point"]}" == "/mnt-ex01" ]]
	[[ "${CHAINS2INFO["${chain}_source file"]}" == "/containers/ex01-container.luks" ]]
	echo 1
	[[ "${CHAINS2INFO["${chain}_key"]}" == "ex01-key" ]]
	[[ "${CHAINS2INFO["${chain}_destination vm 1"]}" == "d-testing" ]]
	[[ "${CHAINS2INFO["${chain}_destination inj 1"]}" == "/root/qcrypt-keys/ex01_disp" ]]
	[[ "${CHAINS2INFO["${chain}_destination opt 1"]}" == "--type plain --cipher aes-xts-plain64 -s 512 --hash sha512" ]]
	[[ "${CHAINS2INFO["${chain}_destination vm 2"]}" == "work" ]]
	[[ "${CHAINS2INFO["${chain}_destination inj 2"]}" == "" ]]
	[[ "${CHAINS2INFO["${chain}_destination opt 2"]}" == "" ]]
	[[ "${CHAINS2INFO["${chain}_destination mount point"]}" == "/qcrypt-ex01" ]]
	echo 2
	[[ "${CHAINS2INFO["${chain}_autostart"]}" == "1" ]]
	[[ "${CHAINS2INFO["${chain}_read-only"]}" == "1" ]]
	[[ "${CHAINS2INFO["${chain}_startup interval"]}" == "300" ]]
	[[ "${CHAINS2INFO["${chain}_pre open command"]}" == "" ]]
	echo 3
	[[ "${CHAINS2INFO["${chain}_post open command"]}" == "" ]]
	[[ "${CHAINS2INFO["${chain}_pre close command"]}" == "" ]]
	[[ "${CHAINS2INFO["${chain}_post close command"]}" == "" ]]
	echo a
	local mainCmd="sys-usb /mnt-ex01//containers/ex01-container.luks ex01-key d-testing work"
	[[ "${CHAINS2INFO["${chain}_open"]}" == *"qcrypt  --inj d-testing /root/qcrypt-keys/ex01_disp --cy d-testing '--type plain --cipher aes-xts-plain64 -s 512 --hash sha512' --mp /qcrypt-ex01 open -- $mainCmd" ]]
	echo b
	[[ "${CHAINS2INFO["${chain}_status"]}" == *"qcrypt status --mp \"\" -- $mainCmd" ]]
	[[ "${CHAINS2INFO["${chain}_close"]}" == *"qcrypt close --force -- $mainCmd" ]]
	echo c

	#valid03 chain
	local chain="valid03"
	[[ "${CHAINS2INFO["${chain}_source vm"]}" == "another-usb" ]]
	[[ "${CHAINS2INFO["${chain}_source device"]}" == "/dev/disk/by-uuid/8c3663c5-b9345-6381-9a67-dd813eb12864" ]]
	[[ "${CHAINS2INFO["${chain}_source mount point"]}" == "/mnt-ex03" ]]
	[[ "${CHAINS2INFO["${chain}_source file"]}" == "/containers/ex03-container.luks" ]]
	[[ "${CHAINS2INFO["${chain}_key"]}" == "ex03-key" ]]
	[[ "${CHAINS2INFO["${chain}_destination vm 1"]}" == "d-testing" ]]
	[[ "${CHAINS2INFO["${chain}_destination inj 1"]}" == "/root/qcrypt-keys/ex03_disp" ]]
	[[ "${CHAINS2INFO["${chain}_destination vm 2"]}" == "work" ]]
	[[ "${CHAINS2INFO["${chain}_destination inj 2"]}" == "/another/path.key" ]]
	[[ "${CHAINS2INFO["${chain}_destination vm 3"]}" == "work2" ]]
	[[ "${CHAINS2INFO["${chain}_destination inj 3"]}" == "/another/path2.key" ]]
	[[ "${CHAINS2INFO["${chain}_destination mount point"]}" == "/qcrypt-ex03" ]]
	[[ "${CHAINS2INFO["${chain}_autostart"]}" == "0" ]]
	[[ "${CHAINS2INFO["${chain}_read-only"]}" == "0" ]]
	[[ "${CHAINS2INFO["${chain}_startup interval"]}" == "5" ]]
	[[ "${CHAINS2INFO["${chain}_pre open command"]}" == 'logger "starting the ex03 chain"' ]]
	[[ "${CHAINS2INFO["${chain}_post open command"]}" == 'logger "started the ex03 chain"' ]]
	[[ "${CHAINS2INFO["${chain}_pre close command"]}" == 'logger "attempting to close the ex03 chain"' ]]
	[[ "${CHAINS2INFO["${chain}_post close command"]}" == 'logger "stopped the ex03 chain"' ]]
	echo d
	local mainCmd="another-usb /mnt-ex03//containers/ex03-container.luks ex03-key d-testing work work2"
	[[ "${CHAINS2INFO["${chain}_open"]}" == *"qcrypt  --inj d-testing /root/qcrypt-keys/ex03_disp --cy d-testing '--type luks' --inj work /another/path.key --inj work2 /another/path2.key --cy work2 '--type luks' -a --ro --mp /qcrypt-ex03 open -- $mainCmd" ]]
	echo e
	[[ "${CHAINS2INFO["${chain}_status"]}" == *"qcrypt status --mp \"\" -- $mainCmd" ]]
	[[ "${CHAINS2INFO["${chain}_close"]}" == *"qcrypt close --force -- $mainCmd" ]]
	echo f
}

@test "chains" {
	runSL "$QCRYPTD" chains -v "nonexisting"
	[ $status -ne 0 ]
	[ -n "$output" ]

	runSL "$QCRYPTD" chains -v "test-valid-01"
	[ $status -eq 0 ]
	[[ "$output" == *"qcrypt status"* ]]
	[[ "$output" == *"ex01.ini"* ]]
	[[ "$output" == *"valid01.ini"* ]]
	local cnt="$(echo "$output" | wc -l)"
	[ $cnt -eq 2 ]

	runSL "$QCRYPTD" chains -v -n "test-valid-01"
	[ $status -eq 0 ]
	[[ "$output" == *"qcrypt status"* ]]
	[[ "$output" != *"ex01.ini"* ]]
	[[ "$output" != *"valid01.ini"* ]]
	local cnt="$(echo "$output" | wc -l)"
	[ $cnt -eq 2 ]
	
	runSL "$QCRYPTD" chains -v -e -n "test-valid-01"
	[ $status -eq 2 ]
	[[ "$output" == *"qcrypt status"* ]]
	[[ "$output" == *"state: bad"* ]]
	[[ "$output" != *"state: good"* ]]
	[[ "$output" != *"ex01.ini"* ]]
	[[ "$output" != *"valid01.ini"* ]]
	local cnt="$(echo "$output" | wc -l)"
	[ $cnt -eq 4 ]
}

@test "stop (invalid)" {
	skipIfQcryptdRunning

	#stop a non-running qcrypt instance
	runSL "$QCRYPTD" stop
	[ $status -ne 0 ]
	[[ "$output" == *"wasn't running"* ]]

	runSL "$QCRYPTD" -fooo stop
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	runSL "$QCRYPTD" -c stop
	[ $status -ne 0 ]
	[[ "$output" == *"wasn't running"* ]]
}

@test "start (invalid)" {
	skipIfQcryptdRunning

	runSL "$QCRYPTD" start "nonexisting-hopefully"
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]

	runSL "$QCRYPTD" --incorrect start
	[ $status -ne 0 ]
	[[ "$output" == *"ERROR"* ]]
}

#prepareQcryptdStartTest [target folder]
function prepareQcryptdStartTest {
	local targetFolder="$1"
	[ -d "$targetFolder" ]

	local fixPath="$(getFixturePath)"
	local fix1LayerKey="$fixPath/1layer01/keys/target"
	local fix1LayerContainer="$fixPath/1layer01/container"
	local fixLoopDevKey="$fixPath/loopdev/keys/target"
	local fixLoopDevFile="$fixPath/loopdev/loopfile"

	#available options:
	#source vm=required
	#source device=/
	#source mount point=
	#source file=required
	#key=required
	#destination vm 1  = required
	#destination inj 1 = required
	#destination vm 2  = work
	#destination inj 2 = 
	#destination mount point=/qcrypt-ex01
	#autostart=false
	#read-only=false
	#type=luks
	#pre open command=echo starting
	#post open command=echo started
	#pre close command=echo closing
	#post close command=echo closed
	
	#non-existing destination VM
	echo '
	source vm='"$UTD_QUBES_TESTVM"'
	source file=/tmp/container
	key=nonexisting-key
	destination vm 1  = nonexisting-vm
	destination inj 1 = '"$fix1LayerKey"'
	destination mount point=/mnt-nonexisting
	autostart=false
	read-only=false
	pre open command=echo starting >> '"$OUT_NONEXISTING"'
	post open command=echo started >> '"$OUT_NONEXISTING"'
	pre close command=echo closing >> '"$OUT_NONEXISTING"'
	post close command=echo closed >> '"$OUT_NONEXISTING"'
	' > "$targetFolder/nonexisting.ini"

	#NOTE: the container is not copied (yet) as UTD_QUBES_TESTVM is supposed to be down

	#destination VM down
	echo '
	source vm='"${TEST_STATE["QCRYPT_VM_1"]}"'
	source file=/tmp/container
	key=dest-down-key
	destination vm 1  = '"$UTD_QUBES_TESTVM"'
	destination inj 1 = '"$fix1LayerKey"'
	destination mount point=/mnt-dest-down
	pre open command=echo starting >> '"$OUT_DEST_DOWN"'
	post open command=echo started >> '"$OUT_DEST_DOWN"'
	pre close command=echo closing >> '"$OUT_DEST_DOWN"'
	post close command=echo closed >> '"$OUT_DEST_DOWN"'
	' > "$targetFolder/dest-down.ini"

	runSL b_dom0_copy "$fix1LayerContainer" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/" 0
	[ $status -eq 0 ]
	[ -z "$output" ]

	#source device missing
	#NOTE: we use /dev/loop0 in a fresh disposable VM
	echo '
	source vm='"${TEST_STATE["QCRYPT_VM_2"]}"'
	source device=/dev/loop0
	source mount point=/srcmnt
	source file=/test-folder/container
	key=dev-missing-key
	read-only=false
	destination vm 1  = '"${TEST_STATE["QCRYPT_VM_1"]}"'
	destination inj 1 = '"$fixLoopDevKey"'
	destination mount point=/mnt-dev-missing
	pre open command=echo starting >> '"$OUT_DEV_MISSING"'
	post open command=echo started >> '"$OUT_DEV_MISSING"'
	pre close command=echo closing >> '"$OUT_DEV_MISSING"'
	post close command=echo closed >> '"$OUT_DEV_MISSING"'
	' > "$targetFolder/dev-missing.ini"

	runSL b_dom0_copy "$fixLoopDevFile" "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/" 0
	[ $status -eq 0 ]
	[ -z "$output" ]
}

#assertOutput [output file] [state]
#Check whether the given qcrypt pre/post open/close command output matches the expected one.
#[state]: 0=not started, 1=started, 2=started and stopped already, 3=never started, but force closed, 4=started, stopped and force closed
function assertOutput {
local outFile="$1"
local state="$2"

local out="fail"
out="$(cat "$outFile")"
echo "$out"

local expected=""
[ "$state" -ge 1 ] && expected="starting"$'\n'"started"
[ "$state" -ge 2 ] && expected="$expected"$'\n'"closing"$'\n'"closed"
[ "$state" -eq 3 ] && expected="closing"$'\n'"closed"
[ "$state" -ge 4 ] && expected="$expected"$'\n'"closing"$'\n'"closed"
[[ "$out" == "$expected" ]]
}

#checkTestChains [destination VM down chain state] [source device missing chain state] [nonexisting state] [qcryptd status]
#Check the status of the test chains to match the expected one.
#[... chain state]: 0=never started, 1=started (source file missing), 2=started and stopped already, 3=never started, but force closed, 4=started, stopped and force closed
#[nonexisting state]: 0=source not available, 1=source available, 3=after force close
#[qcryptd status]: expected exit code of qcryptd status (default: 0)
#[UTD_QUBES_TESTVM_UP]: whether the test VM was already started or not
function checkTestChains {
local chainDownState="$1"
local chainMissingState="$2"
local nonexistingState="${3:-0}"
local qcryptdStatus="${4:-0}"

#postCloseChecks [mount point] [source vm] [source device] [key id] [destination vm 1] .. [destination vm n]
#make sure the service is running
runSL "$QCRYPTD" status
[ $status -eq $qcryptdStatus ]
[ -n "$output" ]
[[ "$output" != *"ERROR"* ]]

#nonextising VM chain
echo a
local mod=0
if [ $nonexistingState -ne 1 ] ; then
	#if the source VM is running, we need to account for the missing source file
	qvm-check --running "$UTD_QUBES_TESTVM" &> /dev/null && mod=1
fi
postCloseChecks "$mod" "/mnt-nonexisting" "$UTD_QUBES_TESTVM" "/tmp/container" "nonexisting-key" "nonexisting-vm"
echo b
[ $nonexistingState -eq 3 ] && assertOutput "$OUT_NONEXISTING" 3 || assertOutput "$OUT_NONEXISTING" 0

#destination VM down chain
echo c
if [ "$chainDownState" -eq 1 ] ; then
	postOpenChecks 0 0 "/mnt-dest-down" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/container" "dest-down-key" "$UTD_QUBES_TESTVM"
else
	postCloseChecks 0 "/mnt-dest-down" "${TEST_STATE["QCRYPT_VM_1"]}" "/tmp/container" "dest-down-key" "$UTD_QUBES_TESTVM"
fi
echo d
assertOutput "$OUT_DEST_DOWN" "$chainDownState"

#device missing chain
echo e
if [ "$chainMissingState" -eq 1 ] ; then
	postOpenChecks 1 0 "/mnt-dev-missing" "${TEST_STATE["QCRYPT_VM_2"]}" "/srcmnt/test-folder/container" "dev-missing-key" "${TEST_STATE["QCRYPT_VM_1"]}"
else
	local mod=0
	[ $chainMissingState -eq 0 ] && mod=2
	postCloseChecks $mod "/mnt-dev-missing" "${TEST_STATE["QCRYPT_VM_2"]}" "/srcmnt/test-folder/container" "dev-missing-key" "${TEST_STATE["QCRYPT_VM_1"]}"
fi
echo f
assertOutput "$OUT_DEV_MISSING" "$chainMissingState"
echo g
}

@test "start & stop (valid)" {
	skipIfQcryptdRunning

	local target="test-start-01"
	local targetFolder="$QCRYPTD_CONF_DIR/$target"
	OUT_NONEXISTING="$(mktemp)"
	OUT_DEST_DOWN="$(mktemp)"
	OUT_DEV_MISSING="$(mktemp)"

	prepareQcryptdStartTest "$targetFolder"

	qvm-shutdown --wait "$UTD_QUBES_TESTVM"
	runSL b_dom0_isRunning "$UTD_QUBES_TESTVM"
	echo "$output"
	[ $status -ne 0 ]

	runSL "$QCRYPTD" -v start "$target"
	[ $status -eq 0 ]
	[ -n "$output" ]
	[[ "$output" != *"ERROR"* ]]

	#make sure no chain went up and none is going up in the next few seconds
	checkTestChains 0 0 0
	sleep 5
	checkTestChains 0 0 0

	#autostart = false should be working
	runSL b_dom0_isRunning "$UTD_QUBES_TESTVM"
	[ $status -ne 0 ]

	#add missing destination VM should cause the chain to start
	#also copy the remaining test container for the nonexisting-dest chain
	runSL b_dom0_ensureRunning "$UTD_QUBES_TESTVM"
	[ $status -eq 0 ]
	[ -z "$output" ]
	runSL b_dom0_copy "$(getFixturePath "1layer01/container")" "$UTD_QUBES_TESTVM" "/tmp/" 0
	[ $status -eq 0 ]
	[ -z "$output" ]
	sleep 5
	checkTestChains 1 0 1

	#make sure it's not closed again
	sleep 30
	checkTestChains 1 0 1

	#add the missing loop device should cause the chain to start
	runSL b_dom0_createLoopDeviceIfNecessary "${TEST_STATE["QCRYPT_VM_2"]}" "/tmp/loopfile"
	[ $status -eq 0 ]
	echo "created loop device: ${TEST_STATE["QCRYPT_VM_2"]}:$output"
	[[ "$output" == "/dev/loop0" ]]
	sleep 7
	checkTestChains 1 1 1

	#shutting down the destination VM should cause the chain to get closed
	qvm-shutdown --wait "$UTD_QUBES_TESTVM"
	runSL b_dom0_isRunning "$UTD_QUBES_TESTVM"
	[ $status -ne 0 ]
	sleep 5
	checkTestChains 2 1 1

	#stopping the service shouldn't affect anything
	runSL "$QCRYPTD" stop
	[ $status -eq 0 ]
	[ -n "$output" ]
	[[ "$output" != *"ERROR"* ]]
	sleep 2
	checkTestChains 2 1 1 1

	runSL "$QCRYPTD" -v start "$target"
	[ $status -eq 0 ]
	[ -n "$output" ]
	[[ "$output" != *"ERROR"* ]]
	sleep 20
	checkTestChains 2 1 1

	#stop with close all flag
	runSL "$QCRYPTD" -c stop
	[ $status -eq 0 ]
	[ -n "$output" ]
	[[ "$output" != *"ERROR"* ]]
	sleep 5
	checkTestChains 4 2 3 1

	#cleanup
	rm -f "$targetFolder"/*.ini
	rm -f "$OUT_NONEXISTING" "$OUT_DEST_DOWN" "$OUT_DEV_MISSING"
}

#status and restart only use already tested functionality

@test "cleanup" {
	runCleanup
}
