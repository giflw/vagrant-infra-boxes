#!/usr/bin/env bash

set -euo pipefail

_PAD=0
_BUILD_ADD="Enable/disable vagrant box add to local box repository (default: TRUE)"
_BUILD_BUILD="Enable/disable box build (default: TRUE)"
_BUILD_CLEAN="Enable/disable box removal before and after build (default: TRUE)"
_BUILD_PUBLISH="Enable/disable vagrant publish to vagrant cloud (default: FALSE)"
_BUILD_RELEASE="Enable/disable vagrant release to vagrant cloud appy only if publising) (default: TRUE)"

for name in `( set -o posix ; set ) | egrep '^_BUILD_.*' | cut -f 1 -d =`; do
    name=${name##*_}
    new_pad=`expr length "$name"`
    if [ $new_pad -gt $_PAD ]; then
        _PAD=$new_pad
    fi
done

echo
echo "Flags available (name:description):"
echo
for name in `( set -o posix ; set ) | egrep '^_BUILD_.*' | cut -f 1 -d =`; do
    flag=${name##*_}
    flag=${flag,,}
    flag="--${flag}/--no-${flag}                                             "

    default_value=${!name}
    default_value=${default_value##*default: }
    default_value=${default_value%%)*}

    echo "${flag:0:$(( $_PAD * 2 + 8 ))} : ${!name}"
    declare "${name}=${default_value}"
done
echo
echo


while [ $# -gt 0 ]; do
    flag=$1
    var_name=$flag
    value=TRUE
    if [[ $var_name == --no-* ]]; then
        value=FALSE
    fi
    var_name=${var_name##*-}
    var_name=${var_name^^}
    var_name=_BUILD_${var_name}

    if ( set -o posix ; set ) | grep "${var_name}="; then
        declare -r "${var_name}=${value}"
    else
        echo "Unknown flag $var_name ($flag)"
        exit 1
    fi
    shift
done

echo "Flags value for this build:"
for name in `( set -o posix ; set ) | egrep '^_BUILD_.*' | cut -f 1 -d =`; do
    name_padded="${name##*_}                                                        "
    echo "${name_padded:0:$_PAD} : ${!name}"
done
echo

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo "Script directory: $SCRIPT_DIR"
cd $SCRIPT_DIR

DISTROS_BUILD="$SCRIPT_DIR/distros.build"
echo "Building boxes ids:"
cat $DISTROS_BUILD
echo
echo '------------------'

for i in `seq 1 5`; do
    echo -n '.'
    sleep 1
done
echo

vagrant_cmd=vagrant

export RANDOM_PORTS=true

function build_box {
    export BUILDING=true
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

    if [ $_BUILD_CLEAN = 'TRUE' -o $_BUILD_BUILD = 'TRUE' ]; then
        $vagrant_cmd destroy -f
        if [ -f "${name}.box" ]; then
            rm "${name}.box"
        fi
    fi

    if [ $_BUILD_BUILD = 'TRUE' ]; then
        $vagrant_cmd up

        $vagrant_cmd halt

        $vagrant_cmd package \
            --info info.json \
            --output "${name}.box" \
            --vagrantfile Vagrantfile
    fi

    checksum=`sha512sum ${name}.box | awk '{print $1}'`

    if [ $_BUILD_ADD = 'TRUE' ]; then
        $vagrant_cmd box add \
            --name giflw/${name} \
            ${name}.box \
            --checksum "${checksum}" \
            --checksum-type sha512 \
            --force
    fi

    if [ $_BUILD_PUBLISH = 'TRUE' ]; then
        $vagrant_cmd cloud publish \
            giflw/${name} \
            "`jq .os -r info.json | cut -f 2 -d -`-`date --utc +%Y%m%d%H%M`" \
            virtualbox \
            ${name}.box \
            --version-description "`jq .description -r info.json`" \
            --checksum "${checksum}" \
            --checksum-type sha512 \
            `test $_BUILD_RELEASE = 'TRUE' && echo --release || echo ''` \
            --no-private \
            --force
    fi

    if [ $_BUILD_BUILD = 'TRUE' ]; then
        $vagrant_cmd destroy -f
    fi

    if [ $_BUILD_CLEAN = 'TRUE' -a -f "${name}.box" ]; then
        rm "${name}.box"
    fi
}


for distro in `ls -d */`; do
    echo '=================================================='
    echo '=================================================='
    echo "MAIN: $distro"
    (
        cd $distro
        for box in `ls -d */`; do
	(
            echo '--------------------------------------------------'
            echo "    SUB:  $box"
            boxid="${distro%*/}/${box%*/}"
            echo "        BOX ID: $boxid"
            cd $box
            echo "        PATH: `pwd`"
            if grep $boxid $DISTROS_BUILD &> /dev/null; then
                echo "        Starting build..."
                build_box
                echo "        ...build finished."
            else
                echo "        Skipping box missing on distros.build file"
            fi
            echo '--------------------------------------------------'
    	)
    	done
    )
    echo '=================================================='
    echo '=================================================='
done
