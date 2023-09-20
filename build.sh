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
version_repo=$(grep -E '^VERSION_REPO.*https:/.' include/version.mk | grep -Eo 'https://.*[^)]')
wget -nv -O .config $version_repo/targets/x86/64/config.buildinfo

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
toolchain_path=$(find /tmp -maxdepth 1 -name 'toolchain-x86_64_gcc*_musl' -type d)
if [ -z $toolchain_path ]; then
	cd /tmp > /dev/null
	wget -nv -O release_page.html ${version_repo}/targets/x86/64/
	toolchain_file=$(grep -m 1 -Eo '"openwrt-toolchain-(.*).tar.xz"' /tmp/release_page.html | tr -d '"')
	echo 'Downloading toolchain...'
	wget -nv -O ${toolchain_file} ${version_repo}/targets/x86/64/${toolchain_file}
	tar -xf ${toolchain_file}
	toolchain_dir=$(basename $(find $(basename $toolchain_file .tar.xz) -name "toolchain-*" -type d))
	mv -f $(basename $toolchain_file .tar.xz)/${toolchain_dir} .
	toolchain_path=/tmp/$toolchain_dir
	rm -rf $(basename $toolchain_file .tar.xz)*
	cd - > /dev/null
fi

#Setup external toolchain
./scripts/ext-toolchain.sh --toolchain $toolchain_path --overwrite-config --config x86-64/generic

#Make download
make download -j8 || make download -j1 V=s

#Apply patches
find ../patches/ -type f | while read patch; do cp $patch ${patch#*../patches/}; done

#Compile firmware
make -j8 || make -j1 V=s

#Convert img to vmdk
for file in $(find bin -name "openwrt-osm-*-efi.img.gz" -type f);
do
	echo "Convert image $(basename $file) to vmdk"
	cd $(dirname $file) > /dev/null
	gunzip -c $(basename $file) > $(basename $file .gz)
	qemu-img convert -f raw $(basename $file .gz) -O vmdk $(basename $file .img.gz).vmdk
	gzip $(basename $file .img.gz).vmdk
	rm $(basename $file .gz)
	cd - > /dev/null
done
