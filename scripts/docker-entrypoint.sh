#!/bin/bash

#service postgresql start

tail -f /var/log/apache2/access.log &

# Run Apache in the foreground
#/usr/sbin/apache2ctl -D FOREGROUND
