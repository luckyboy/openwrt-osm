#!/bin/bash

#Prepare version
source ../parse_yaml.sh
eval $(parse_yaml ../version.osm)

#Download source code
rm -f .gitkeep
git config --global advice.detachedHead false
git clone -b $version_upstream_version_tag --depth 1 https://github.com/openwrt/openwrt.git .

#Merge feeds
for f in $version_feeds_ ; do eval echo \$${f} >> feeds.conf.default ; done

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
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' .config
sed -i "s/CONFIG_VERSION_DIST=\"OpenWrt\"/CONFIG_VERSION_DIST=\"OpenWrt-OSM\"/g" .config
sed -i "s/CONFIG_VERSION_NUMBER=\"\"/CONFIG_VERSION_NUMBER=\"${version_version_number}\"/g" .config
sed -i "s/CONFIG_VERSION_CODE=\"\"/CONFIG_VERSION_CODE=\"r$(git -C ../ rev-parse --short=10 HEAD)\"/g" .config

#Download Toolchain
wget -nv -O /tmp/release_page.html ${VERSION_REPO}/targets/x86/64/
TOOLCHAIN=$(grep -m 1 -Eo '"openwrt-toolchain-(.*).tar.xz"' /tmp/release_page.html | tr -d '"')
wget -nv -O /tmp/${TOOLCHAIN} ${VERSION_REPO}/targets/x86/64/${TOOLCHAIN}
tar -C /tmp -xf /tmp/${TOOLCHAIN}
TOOLCHAIN_DIR_NAME=$(basename $(find /tmp/$(basename $TOOLCHAIN .tar.xz) -name "toolchain-*" -type d))
mv -f /tmp/$(basename $TOOLCHAIN .tar.xz)/${TOOLCHAIN_DIR_NAME} /tmp/

#Setup external toolchain
./scripts/ext-toolchain.sh --toolchain /tmp/${TOOLCHAIN_DIR_NAME} --overwrite-config --config x86-64/generic

#Make download
make download -j8 || make download -j1 V=s

#Apply patches
find ../patches/ -type f | while read patch; do cp $patch ${patch#*../patches/}; done

#Compile firmware
make -j$(nproc) || make -j1 V=s
