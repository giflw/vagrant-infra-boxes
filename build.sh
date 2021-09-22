#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd $SCRIPT_DIR

function build_box {
    envvars="`jq -r .env info.json`"
    if [ -n "$envvars" ]; then
        set -a # -o allexport
        eval "$envvars"
        echo "envfile --------------------------"
        echo "$envvars"
        echo "----------------------------------"
        set +a # +o allexport
    fi

    name=$(basename `pwd`)
    name=`jq .os -r info.json | cut -f 1 -d -`-${name}
    echo "Box"
    echo "Name:         $name"
    echo "Directory:    `pwd`"

    vagrant up

    vagrant halt

    if [ -f "${name}.box" ]; then
        rm "${name}.box"
    fi

    vagrant package \
        --info info.json \
        --output "${name}.box" \
        --vagrantfile Vagrantfile

    vagrant cloud publish \
        giflw/${name} \
        "`jq .os -r info.json | cut -f 2 -d -`-`date +%Y%m%d%H%M`" \
        virtualbox \
        ./${name}.box \
        --version-description "`jq .description -r info.json`" \
        --release \
        --no-private \
        --force

    vagrant destroy -f

    rm "${name}.box"
}


for distro in `ls -d */`; do
    echo '=================================================='
    echo '=================================================='
    echo $distro
    (
        cd $distro
        for box in `ls -d */`; do
            echo '--------------------------------------------------'
            echo $box
            cd $box
            pwd
            build_box
            echo '--------------------------------------------------'
        done
    )
    echo '=================================================='
    echo '=================================================='
done
