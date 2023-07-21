#!/bin/bash

source helper.sh

teardown-ovn-ls ls0 eth0
teardown-ovn-ls ls-out
teardown-ovn-lr r0
teardown-ns ns1
