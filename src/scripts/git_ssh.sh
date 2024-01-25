#!/bin/bash

sudo apt-get install git &&
ssh-keygen -t rsa -b 4096 -q -f ~/.ssh/id_rsa -N "" &&
printf "\n\n-----------------------------------\n" &&
cat ~/.ssh/id_rsa.pub &&
printf "\n\n-----------------------------------\n" &&
printf "copy the content above in your github-Account SSH-Keys\n"