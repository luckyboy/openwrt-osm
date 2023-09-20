#!/bin/bash

#Prepare version
source ../parse_yaml.sh
eval $(parse_yaml ../version.yaml)

#Download source code
rm -f .gitkeep
git config --global advice.detachedHead false
git clone -b $version_upstream_version_tag --depth 1 https://github.com/openwrt/openwrt.git .

# S1 repo url
download_package(){
	repo=$(echo $1 | grep -Eo '^http*.*..git')
	commit=$(echo $1 | grep -Eo '\^.*' | tr -d '^')
	branch=$(echo $1 | grep -Eo ';.*' | tr -d ';')
	if [ ! -z $commit ]; then
		echo Downloading package from $1
		git -C package clone $repo && cd package/$(basename $repo .git) && git checkout $commit && cd -
	elif [ ! -z $branch ]; then
		echo Downloading package from $1
		git -C package clone $repo --depth 1 --branch $branch
	else
		echo "Invalid package info $1"
		exit 1
	fi
}

#Download extra package
for f in $version_package_ ; do eval download_package \$${f} ; done

#Update feeds
./scripts/feeds update -a
./scripts/feeds install -a

#Generate configuration file
VERSION_REPO=$(grep -E '^VERSION_REPO.*https:/.' include/version.mk | grep -Eo 'https://.*[^)]')
wget -nv -O .config $VERSION_REPO/targets/x86/64/config.buildinfo

#Merge config
for f in $version_config_ ; do eval echo \$${f} >> .config ; done

#Set dnsmasq-full as default
sed -i 's/dnsmasq \\/dnsmasq-full \\/g' include/target.mk
#config luci-theme-argon as default theme
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' .config
#config version info
sed -i "s/CONFIG_VERSION_DIST=\"OpenWrt\"/CONFIG_VERSION_DIST=\"OpenWrt-OSM\"/g" .config
sed -i "s/CONFIG_VERSION_NUMBER=\"\"/CONFIG_VERSION_NUMBER=\"${version_version_number}\"/g" .config
sed -i "s/CONFIG_VERSION_CODE=\"\"/CONFIG_VERSION_CODE=\"$(git -C ../ rev-parse --short=10 HEAD)\"/g" .config

#Download Toolchain
TOOLCHAIN_PATH=$(find /tmp -maxdepth 1 -name 'toolchain-x86_64_gcc*_musl' -type d)
if [ -z $TOOLCHAIN_PATH ]; then
	wget -nv -O /tmp/release_page.html ${VERSION_REPO}/targets/x86/64/
	TOOLCHAIN=$(grep -m 1 -Eo '"openwrt-toolchain-(.*).tar.xz"' /tmp/release_page.html | tr -d '"')
	echo 'Downloading toolchain...'
	wget -nv -O /tmp/${TOOLCHAIN} ${VERSION_REPO}/targets/x86/64/${TOOLCHAIN}
	tar -C /tmp -xf /tmp/${TOOLCHAIN}
	TOOLCHAIN_DIR_NAME=$(basename $(find /tmp/$(basename $TOOLCHAIN .tar.xz) -name "toolchain-*" -type d))
	mv -f /tmp/$(basename $TOOLCHAIN .tar.xz)/${TOOLCHAIN_DIR_NAME} /tmp
	TOOLCHAIN_PATH=/tmp/$TOOLCHAIN_DIR_NAME
fi

#Setup external toolchain
./scripts/ext-toolchain.sh --toolchain $TOOLCHAIN_PATH --overwrite-config --config x86-64/generic

#Make download
make download -j8 || make download -j1 V=s

#Apply patches
find ../patches/ -type f | while read patch; do cp $patch ${patch#*../patches/}; done

#Compile firmware
make -j$(nproc) || make -j1 V=s
