#! /bin/bash
#

# Get health check passing as quick as possible
yum -y install nginx
systemctl start nginx

# Install convenience packages for load testing
yum -y install git tmux tcpdump iperf3
