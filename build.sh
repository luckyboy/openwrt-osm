#!/bin/bash
set -e
#Include yaml helper
source ../parse_yaml.sh

function merge_feeds(){
    eval $(parse_yaml ../version.yaml)
    for f in $version_feeds_ ; do eval echo \$${f} >> feeds.conf.default ; done
}

#Download source code (./openwrt is working dir)
function download_source_code(){
    rm -f .gitkeep
    eval $(parse_yaml ../version.yaml)
    git config --global advice.detachedHead false
    git clone -b $version_upstream_version_tag --depth 1 https://github.com/openwrt/openwrt.git .
}

#Update feeds
function update_feeds(){
    ./scripts/feeds update -a
    ./scripts/feeds install -a
}

#Generate config
function merge_config(){
    version_repo=$(grep -E '^VERSION_REPO.*https:/.' include/version.mk | grep -Eo 'https://.*[^)]')
    wget -nv -O .config $version_repo/targets/x86/64/config.buildinfo
    #Merge config
    eval $(parse_yaml ../version.yaml)
    for f in $version_config_ ; do eval echo \$${f} >> .config ; done
    #Set dnsmasq-full as default
    sed -i 's/dnsmasq \\/dnsmasq-full \\/g' include/target.mk
    #config luci-theme-argon as default theme
    sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' .config
    #config version info
    sed -i "s/CONFIG_VERSION_DIST=\"OpenWrt\"/CONFIG_VERSION_DIST=\"OpenWrt-OSM\"/g" .config
    sed -i "s/CONFIG_VERSION_NUMBER=\"\"/CONFIG_VERSION_NUMBER=\"${version_version_number}\"/g" .config
    sed -i "s/CONFIG_VERSION_CODE=\"\"/CONFIG_VERSION_CODE=\"r$(git -C ../ log --pretty=format:%h | wc -l)-$(git -C ../ rev-parse --short=10 HEAD)\"/g" .config
    #Exclude none official feeds from distfeeds.conf
    for feed in $(grep -v 'https://git\.openwrt\.org' feeds.conf.default | awk '{print $2}');
    do
        echo "CONFIG_FEED_${feed}=m" >> .config
    done
}

#Setup external toolchain
function setup_external_toolchain(){
    toolchain_path=$(find /tmp -maxdepth 1 -name 'toolchain-x86_64_gcc*_musl' -type d)
    if [ -z $toolchain_path ]; then
        version_repo=$(grep -E '^VERSION_REPO.*https:/.' include/version.mk | grep -Eo 'https://.*[^)]')
        cd /tmp/ > /dev/null
        wget -nv -O release_page.html ${version_repo}/targets/x86/64/
        toolchain_file=$(grep -m 1 -Eo '"openwrt-toolchain-(.*).(xz|zst)"' /tmp/release_page.html | tr -d '"')
        echo "Downloading toolchain...${toolchain_file}"
        wget -nv -O ${toolchain_file} ${version_repo}/targets/x86/64/${toolchain_file}
        tar -xf ${toolchain_file}
        toolchain_dir=$(basename $(find ${toolchain_file%.*.*} -name "toolchain-*" -type d))
        mv -f ${toolchain_file%.*.*}/${toolchain_dir} .
        toolchain_path=/tmp/$toolchain_dir
        rm -rf ${toolchain_file%.*.*}*
        cd - > /dev/null
    fi
    #Setup external toolchain
    ./scripts/ext-toolchain.sh --toolchain $toolchain_path --overwrite-config --config x86-64/generic
}

#Make download
function make_download(){
    make download -j8 || make download -j1 V=s
}

#Apply patches
function apply_patches(){
    cp -rf ../patches/* ./
}

#Compile firmware
function compile(){
    make -j8 || make -j1 V=s
}

#Convert img to vmdk
function generate_vmdk(){
    for file in $(find ./bin/targets/ -name "openwrt-osm-*-efi.img.gz" -type f);
    do
        echo "Convert image $(basename $file) to vmdk"
        cd $(dirname $file) > /dev/null
        gunzip -f -q -c $(basename $file) > $(basename $file .gz)
        qemu-img convert -f raw $(basename $file .gz) -O vmdk $(basename $file .img.gz).vmdk
        gzip -f -q $(basename $file .img.gz).vmdk
        rm $(basename $file .gz)
        cd - > /dev/null
    done
}

#Prepare artifacts for uploading
function prepare_artifacts(){
    mkdir -p ./artifact
    cp -rf $(find ./bin/targets/ -name "*.img.gz" -type f) ./artifact/
    cp -rf $(find ./bin/targets/ -name "*.vmdk.gz" -type f) ./artifact/
    kmod_bnx2x=$(find ./bin -type f -name "kmod-bnx2x*.ipk")
    if [ ! -z $kmod_bnx2x ]; then
        cp -rf $kmod_bnx2x ./artifact/$(basename $(echo $kmod_bnx2x | sed 's/kmod-bnx2x/kmod-bnx2x_2.5G/g'))
    fi
    cp -rf $(find ./bin/targets/ -type f -name "*.buildinfo" -o -name "*.manifest") ./artifact/
}

case $1 in
    "all")
        download_source_code
        merge_feeds
        update_feeds
        merge_config
        setup_external_toolchain
        make_download
        apply_patches
        compile
        generate_vmdk
        ;;
    "download_source_code" | "merge_feeds" | "update_feeds" | "merge_config" | "setup_external_toolchain" | "make_download" | "apply_patches" | "compile" | "generate_vmdk")
        $1
        ;;
esac
