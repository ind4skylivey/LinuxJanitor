#!/usr/bin/env bats

load test_helper

@test "cli: --version prints version" {
    run "$SCRIPT_PATH" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"System Cleanup Enhanced v3.0"* ]]
}

@test "cli: --help prints usage" {
    run "$SCRIPT_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "cli: --user without argument exits with error" {
    run "$SCRIPT_PATH" --user
    [ "$status" -eq 1 ]
    [[ "$output" == *"--user requires an argument"* ]]
}

@test "cli: unknown option prints warning" {
    run "$SCRIPT_PATH" --not-a-real-flag --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unknown option: --not-a-real-flag"* ]]
    [[ "$output" == *"v3.0"* ]]
}
