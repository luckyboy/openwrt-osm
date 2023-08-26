# OpenWrt-OSM Official Slightly Modification(OSM)

## Automated OpenWrt image customization based on OpenWrt official release

###   This repo's CI is based on [P3TERX](https://github.com/P3TERX/Actions-OpenWrt), thanks for the authors.

## Usage:
  * Fork this repo
  * Enable GitHub Actions for your own repo
  * Choose the OpenWrt official release (https://downloads.openwrt.org/releases/) you want
  * Edit openwrt_releases with the target official relase information
     |  Content   | Description  |
     |  ----  | ----  |
     | openwrt-23.05  | The OpenWrt official release branch from github |
     | 5deed175a5  | The OpenWrt Official release commit id from version.buildinfo (e.g https://downloads.openwrt.org/releases/23.05.0-rc3/targets/x86/64/version.buildinfo) |
     | https://downloads.openwrt.org/releases/23.05.0-rc3/targets/x86/64/config.buildinfo | The OpenWrt official release config url |
     | https://downloads.openwrt.org/releases/23.05.0-rc3/targets/x86/64/feeds.buildinfo | The OpenWrt official release feeds url |
  * Modify .github/workflows/openwrt-osm-ci.yml in those build steps at your needs. Basically, We can add or remove applications int the step "Generate configuration file"
  * Run the workflow to build your own release.
## License
  MIT
