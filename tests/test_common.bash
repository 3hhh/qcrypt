#!/bin/bash
# 
#+Test code shared across qcrypt & qcryptd tests.
#+
#+Copyright (C) 2019  David Hobach  GPLv3
#+0.3

QCRYPT="$(readlink -f "$BATS_TEST_DIRNAME/../qcrypt")"
QCRYPTD="$(readlink -f "$BATS_TEST_DIRNAME/../qcryptd")"
QCRYPTD_CONF_DIR="$(readlink -f "$BATS_TEST_DIRNAME/../conf")"

#meant to be run inside setup()
function setupQcryptTesting {
	#blib setup
	#NOTE: bats forces us to load blib again every time (if we don't do it here, bats will re-source the entire file for every test anyway)
	set +e
	source blib
	source "$B_LIB_DIR/tests/test_common.bash"
	set -e
	B_TEST_MODE=0

	skipIfNotQubesDom0

	[ -z "$UTD_QUBES_TESTVM" ] && skip "Please specify a static disposable test VM as UTD_QUBES_TESTVM in your user data file $USER_DATA_FILE."

	b_import "/os/qubes4/dom0"

	#re-use the same VMs for all tests, use fresh ones if some test kills them
	loadBlibTestState
	recreateTestVMsIfNeeded
	echo "QCRYPT_VM_1 = ${TEST_STATE["QCRYPT_VM_1"]}"
	echo "QCRYPT_VM_2 = ${TEST_STATE["QCRYPT_VM_2"]}"
	echo "UTD_QUBES_TESTVM = $UTD_QUBES_TESTVM"
}

#recreateTestVMsIfNeeded
function recreateTestVMsIfNeeded {
	if [ -z "${TEST_STATE["QCRYPT_VM_1"]}" ] || ! qvm-check --running "${TEST_STATE["QCRYPT_VM_1"]}" &> /dev/null ; then
		TEST_STATE["QCRYPT_VM_1"]="$(b_dom0_startDispVM "$UTD_QUBES_DISPVM_TEMPLATE")"
		saveBlibTestState
	fi
	if [ -z "${TEST_STATE["QCRYPT_VM_2"]}" ] || ! qvm-check --running "${TEST_STATE["QCRYPT_VM_2"]}" &> /dev/null ; then
		TEST_STATE["QCRYPT_VM_2"]="$(b_dom0_startDispVM "$UTD_QUBES_DISPVM_TEMPLATE")"
		saveBlibTestState
	fi
}

function skipIfNotRoot {
	[[ "$(whoami)" != "root" ]] && skip "This test must be run as root."
	return 0
}

function skipIfQcryptdRunning {
	"$QCRYPTD" status &> /dev/null && skip "qcryptd appears to be running."
	return 0
}

#getFixturePath [fixture name]
function getFixturePath {
	local fixture="$1"
	[ -n "$fixture" ] && fixture="/$fixture"
	echo "$BATS_TEST_DIRNAME/fixtures$fixture"
}

#getQcryptKeyFolder [vm]
function getQcryptKeyFolder {
	local vm="$1"
	local user="$(qvm-prefs "$vm" default_user)"
	echo "/home/$user/.qcrypt/keys"
}

#copyFixture [fixture name] [vm]
#Copy the container fixture to the given VM at /tmp/[fixture name].
function copyFixture {
	local fixture="$1"
	local fixturePath="$(getFixturePath "$fixture")"
	local vm="$2"

	local fixtureContainer="$fixturePath/container"
	runSL b_dom0_copy "$fixtureContainer" "$vm" "/tmp/$fixture" 0 1
	[ $status -eq 0 ]
	[ -z "$output" ]
}

#readOnlyTest [folder]
#This function is meant to be run inside a VM.
function readOnlyTest {
	local folder="$1"
	local tfile="$folder/FAILURE.txt"
	echo "FAILURE" > "$tfile"
	[ $? -eq 0 ] && exit 2
	
	cat "$tfile"
	[ $? -eq 0 ] && exit 3

	exit 0
}

#meant to be run as the last test of a unit
function runCleanup {
	qvm-shutdown "$UTD_QUBES_TESTVM" "${TEST_STATE["QCRYPT_VM_1"]}" "${TEST_STATE["QCRYPT_VM_2"]}" || :

	clearBlibTestState

	#test whether qvm-block ls is still working
	#cf. https://github.com/QubesOS/qubes-issues/issues/4940
	#sometimes it's also the 2 layer close above
	runSL qvm-block ls
	[ $status -eq 0 ]
	[[ "$output" != *"qubesd"* ]]
}

#assertQcryptStatus [expected status] [mount point] [source vm] [source file] [key id] [destination vm 1] .. [destination vm n]
#[expected status]: exact status match, each error indicates one missing step towards decryption; -1: the status check should produce an error with a non-zero exit code
function assertQcryptStatus {
	local expected="$1"
	local mp="$2"
	local target="${@: -1}"
	shift 2

	local statusParams=""
	[ -n "$mp" ] && printf -v statusParams -- '--mp %q' "$mp"
	runSL "$QCRYPT" status $statusParams -- "$@"
	echo "$output"
	[ -n "$output" ]
	if [ $expected -eq -1 ] ; then
		[[ "$output" == *"ERROR"* ]]
		[ $status -ne 0 ]
	else
		[[ "$output" != *"ERROR"* ]]
		[[ "$output" == *"$target"* ]]

		echo "expected status: $expected"
		echo "actual   status: $status"
		[ $status -eq $expected ]
	fi
}

#postOpenChecks [read-only flag] [success file flag] [mount point] [source vm] [source file] [key id] [destination vm 1] .. [destination vm n]
#[mount point]: Can be left empty, if the chain is not mounted.
#[success file flag]: Whether a file named SUCCESS.txt with the content 'SUCCESS' exists at [mount point]/SUCCESS.txt. If it doesn't, it will be created as part of this check (unless the mount pint is read-only or it's not mounted).
function postOpenChecks {
	local ro="${1:-1}"
	local hasSuccFile="${2:-0}"
	local mp="$3"
	shift 3
	local source="$1"
	local key="$2"
	local target="${@: -1}"

	#check status
	#NOTE: we rely on status here, but that's tested inside its dedicated status test
	assertQcryptStatus 0 "$mp" "$@"

	#create the success file if needed (write test)
	local succFile="$mp/SUCCESS.txt"
	local succFileEsc=""
	printf -v succFileEsc '%q' "$succFile"
	if [ -n "$mp" ] && [ $ro -ne 0 ] && [ $hasSuccFile -ne 0 ] ; then
		runSL b_dom0_qvmRun "$target" "echo SUCCESS > $succFileEsc"
		[ $status -eq 0 ]
		[ -z "$output" ]
		hasSuccFile=0
	fi

	#check for the success file
	if [ -n "$mp" ] && [ $hasSuccFile -eq 0 ] ; then
		runSL b_dom0_qvmRun "$target" "cat $succFileEsc"
		[ $status -eq 0 ]
		[[ "$output" == "SUCCESS" ]]
	fi

	#make sure that we cannot write, if r/o
	if [ -n "$mp" ] && [ $ro -eq 0 ] ; then
		runSL b_dom0_execFuncIn "$target" "" "readOnlyTest" "$mp"
		[ $status -eq 0 ]
		[ -n "$output" ]
	fi

	return 0
}

#postCloseChecks [expected status mod] [mount point] [source vm] [source file] [key id] [destination vm 1] .. [destination vm n]
#[expected status mod]: Integer modifier for the expected status (default: 0). Only required under very special circumstances (e.g. source file missing).
function postCloseChecks {
	local mod="${1:-0}"
	local mp="$2"
	local sourceVM="$3"
	shift 2

	local numDst=$(( $# -3 ))
	#expected status: device not attached & not decrypted for each VM (VMs running & keys available though), not mounted in target VM, no loop device in source VM anymore
	local eStatus=$(( $numDst * 2 + 2 ))

	#add run status info
	declare -a vms=("$sourceVM" "${@:4}")
	local vm=
	for vm in "${vms[@]}" ; do
		#not running: VM down & missing key/source file --> +2
		qvm-check --running "$vm" &> /dev/null || eStatus=$(( $eStatus +2))
	done

	#add modifier
	eStatus=$(( $eStatus + $mod ))

	assertQcryptStatus "$eStatus" "$mp" "$@"
}
