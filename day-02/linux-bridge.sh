#!/bin/bash

# import helper function from helper.sh
source helper.sh

echo "create namespace ns1 and assign IP 192.168.1.1"
create-ns ns1 192.168.1.1

echo "create namespace ns2 and assign IP 192.168.1.2"
create-ns ns2 192.168.1.2

echo "create bridge br0 and assign interfaces"
create-br-and-assign-iface br0


