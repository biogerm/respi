#!/bin/bash
echo $1
sed 's/'$1'/PASSWORD/g' config.json > config.json.nopwd
