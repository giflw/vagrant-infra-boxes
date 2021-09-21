#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd $SCRIPT_DIR

function build_box {
    name=$(basename `pwd`)
    echo "Box"
    echo "Name:         $name"
    echo "Directory:    `pwd`"
    cat <<EOF > info.json
{
    "author": "${AUTHOR:=Guilherme I F L Weizenmann}",
    "homepage": "${HOMEPAGE:=https://github.com/giflw/vagrant-infra-boxes/blob/main/${name}}"
}
EOF
    #vagrant up
    #vagrant halt
    vagrant package --info info.json --output "${name}.box" --vagrantfile Vagrantfile

    # vars
    grep ENV Vagrantfile | tr ' ' $'\n' | xargs -L 1 | grep ENV | tr '[]' ' ' | awk '{print $2}' | sort -u
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
            build_box
            echo '--------------------------------------------------'
        done
    )
    echo '=================================================='
    echo '=================================================='
done
