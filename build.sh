#!/bin/sh
# Multi-arch build procedure based on https://github.com/rmoriz/multiarch-test
set -e

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
	exec sudo -- "$0" "$@"
	exit
fi

function executeHook() {
    cd ${BASE_PATH}

    echo "Executing $(basename $1) hook..."
    source hooks/$1
}

# Create 'build.conf' file (or passa  path to it as argument) to override these
# If you just want to build locally the script will ask you questions
#
# DOCKER_REPO should use format "index.docker.io/your_username/your_repository"
# SOURCE_BRANCH, SOURCE_COMMIT and COMMIT_MSG will be filled automatically when possible
# IMAGE_NAME is automatically generated by combining DOCKER_REPO and DOCKER_TAG
BASE_PATH=$(realpath $(dirname "$0"))
CONFIG_FILE="$(dirname $0)/build.conf"
ARCHITECTURES_TO_BUILD=()
DOCKERFILE_PATH=Dockerfile
DOCKERCFG=
SOURCE_BRANCH=
SOURCE_COMMIT=
COMMIT_MSG=
DOCKER_REPO=
DOCKER_TAG=
IMAGE_NAME=

if [ "$1" != "" ] && [ -f "$1" ]; then
    CONFIG_FILE="$1"
fi

if [ -f "${CONFIG_FILE}" ]; then
    source ${CONFIG_FILE}
fi

# Generate IMAGE_NAME
if [ -z "${IMAGE_NAME}" ]; then
    if ! [ -z "${DOCKER_REPO}" ] && ! [ -z "${DOCKER_TAG}" ]; then
        IMAGE_NAME="${DOCKER_REPO}:${DOCKER_TAG}"
    else
        IMAGE_NAME="$(basename "$PWD"):local"
    fi
fi

# Fill out SOURCE_BRANCH, SOURCE_COMMIT and COMMIT_MSG automatically
if command -v git &> /dev/null; then
    if [ -z "${SOURCE_BRANCH}" ] && [ -d "$(dirname $0)/.git" ]; then
        SOURCE_BRANCH=`git rev-parse --abbrev-ref HEAD`
    fi

    if [ -z "${SOURCE_COMMIT}" ] && [ -d "$(dirname $0)/.git" ]; then
        SOURCE_COMMIT=`git rev-parse HEAD`
    fi

    if [ -z "${COMMIT_MSG}" ] && [ -d "$(dirname $0)/.git" ]; then
        COMMIT_MSG=`git log -1 --pretty=%B`
    fi
fi

read -p "Build image(s)? [Y/n] " -n 1 -r && ! [[ -z $REPLY ]] && echo 
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    if [ -z "${ARCHITECTURES_TO_BUILD}" ]; then
        POSSIBLE_ARCHITECTURES=(amd64 arm64 armhf)

        for arch in ${POSSIBLE_ARCHITECTURES[@]}; do
            read -p "Build image for ${arch}? [Y/n] " -n 1 -r && ! [[ -z $REPLY ]] && echo  
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                ARCHITECTURES_TO_BUILD+=($arch)
            fi
        done
        
        if [ -z "${ARCHITECTURES_TO_BUILD}" ]; then
            echo "Nothing selected, aborting"
            exit 1
        fi
    else
        echo "Architectures to build read from config: ${ARCHITECTURES_TO_BUILD[*]}"
    fi

    executeHook "post_checkout"
    executeHook "pre_build"
    executeHook "build"
fi

echo
if \
    [ ! -z "${IMAGE_NAME}" ] && echo "${IMAGE_NAME}" | grep -q "index.docker.io/" \
; then
    read -p "Push image(s)? [Y/n] " -n 1 -r && ! [[ -z $REPLY ]] && echo  
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        executeHook "push"
    fi
else
    echo "Unable to push, IMAGE_NAME is not correctly set"
fi

echo "Done"
