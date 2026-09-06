#!/usr/bin/env bats

load test_helper

@test "get_system_users: returns users with valid homes and login shells" {
    begin_test
    write_passwd_fixture

    users=$(get_system_users)
    [[ "$users" == *"alice"* ]]
    [[ "$users" == *"bob"* ]]
    [[ "$users" != *"root"* ]]
    [[ "$users" != *"daemon"* ]]
    [[ "$users" != *"svc"* ]]
}

@test "get_system_users: excludes nologin service accounts" {
    begin_test
    write_passwd_fixture

    users=$(get_system_users)
    [[ "$users" != *"daemon"* ]]
    [[ "$users" != *"svc"* ]]
}

@test "get_user_home: resolves home directory from passwd" {
    begin_test
    write_passwd_fixture

    home=$(get_user_home "alice")
    [ "$home" = "${TEST_HOME}/alice" ]
}
