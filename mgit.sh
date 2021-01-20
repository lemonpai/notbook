#!/bin/bash

user_name="lemonpai"
email="lyu.teng@outlook.com"
project_name="nb"
progect_url="https://github.com/lemonpai/notbook.git"


function init() { 
    git init
    config
}

function config() {
    git config --global user.name ${user_name}
    git config --global user.email ${email}
    git remote add ${project_name} ${progect_url}
}

function pull() {
    git pull ${project_name} master
}

function push() {
    git add -A .
    git commit -m "$*"
    git push ${project_name} master
}

function diff() {
    echo "select two version, below"
    git log --oneline
    echo -n "-- src version  : "
    read src
    echo -n "-- dest version : "
    read dest
	git diff ${dest} ${src} --name-only
	echo -n "-- is compress?[y or n] : "
	read is_compress
	if [ ${is_compress} == 'y' ]; then
        git diff ${dest} ${src} --name-only | xargs zip diff_${diff}_${src}.zip
	fi
}

function help() {
    echo "./mgit <cmd> <param>"
    echo "cmd:"
    echo "  init : init the workspace"
    echo "  pull : get the latest code"
    echo "  push : upload the code, with comment"
    echo "  diff : get changed files & compass into zip"
    echo "param"
    echo "  comment : only for push command"
}

case $1 in
    "init")
        init
        ;;
    "pull")
        pull
        ;;
    "config")
        config
        ;;
    "push")
        shift
        push $@
        ;;
    "diff")
        diff
        ;;
    "--help")
        help
        ;;
esac
	

