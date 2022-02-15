#!/usr/bin/env bats
# 
#+Bats tests to run shellcheck on qcrypt et al.
#+
#+Copyright (C) 2022  David Hobach  GPLv3
#+0.7

load "test_common"

function setup {
	setupBlib
}

function runShellcheck {
	skipIfCommandMissing "shellcheck"

	local file="$1"
	runSC shellcheck -s "bash" -S "warning" "$file"
	echo "$output"
	[ $status -eq 0 ]
	[ -z "$output" ]
}

@test "shellcheck: qcrypt" {
	echo "$B_SCRIPT_DIR"
	runShellcheck "$QCRYPT"
}

@test "shellcheck: qcryptd" {
	runShellcheck "$QCRYPTD"
}
