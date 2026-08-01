#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 06-playwright-deps — OS libraries required to launch Playwright browsers.
#
# The user tier (user/init.d/35-node) installs @playwright/test and downloads
# chromium/firefox/webkit into ~/.cache/ms-playwright, but the browsers only
# launch if their shared-library dependencies are present — and installing
# those needs root. This step is the root-tier counterpart: it installs the
# union of `npx playwright install-deps chromium firefox webkit`.
#
# Package names differ per distro release (Debian's t64 transition, differing
# libavcodec/libicu versions), so the lists are keyed by ID-VERSION_CODENAME
# from /etc/os-release. They mirror playwright-core's nativeDeps table — the
# same source `playwright install-deps` uses. To regenerate or add a distro,
# run this on a matching host with playwright installed:
#
#   npx playwright install-deps --dry-run chromium firefox webkit
#
# Unknown distros are skipped with a warning instead of failing the run.

echo "==> Installing Playwright browser system libraries..."

. /etc/os-release

case "${ID}-${VERSION_CODENAME:-}" in
  debian-trixie)
    # Debian 13 — playwright-core nativeDeps "debian13-x64"
    PACKAGES="libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 libasound2 libavcodec61 libcairo-gobject2 libdbus-glib-1-2 libfontconfig1 libfreetype6 libgdk-pixbuf-2.0-0 libgtk-3-0t64 libharfbuzz0b libpangocairo-1.0-0 libx11-xcb1 libxcb-shm0 libxcursor1 libxi6 libxrender1 libxtst6 libsoup-3.0-0 gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good libegl1 libenchant-2-2 libepoxy0 libevdev2 libgles2 libglx0 libgstreamer-gl1.0-0 libgstreamer-plugins-base1.0-0 libgstreamer1.0-0 libgtk-4-1 libgudev-1.0-0 libharfbuzz-icu0 libhyphen0 libicu76 libjpeg62-turbo liblcms2-2 libmanette-0.2-0 libnotify4 libopengl0 libopenjp2-7 libopus0 libpng16-16t64 libproxy1v5 libsecret-1-0 libwayland-client0 libwayland-egl1 libwayland-server0 libwebp7 libwebpdemux2 libwoff1 libxml2 libxslt1.1 libatomic1 libevent-2.1-7t64 libavif16"
    ;;
  debian-bookworm)
    # Debian 12 — playwright-core nativeDeps "debian12-x64"
    PACKAGES="libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 libavcodec59 libcairo-gobject2 libdbus-glib-1-2 libfontconfig1 libfreetype6 libgdk-pixbuf-2.0-0 libgtk-3-0 libharfbuzz0b libpangocairo-1.0-0 libx11-xcb1 libxcb-shm0 libxcursor1 libxi6 libxrender1 libxtst6 libsoup-3.0-0 gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good libegl1 libenchant-2-2 libepoxy0 libevdev2 libgles2 libglx0 libgstreamer-gl1.0-0 libgstreamer-plugins-base1.0-0 libgstreamer1.0-0 libgtk-4-1 libgudev-1.0-0 libharfbuzz-icu0 libhyphen0 libicu72 libjpeg62-turbo liblcms2-2 libmanette-0.2-0 libnotify4 libopengl0 libopenjp2-7 libopus0 libpng16-16 libproxy1v5 libsecret-1-0 libwayland-client0 libwayland-egl1 libwayland-server0 libwebp7 libwebpdemux2 libwoff1 libxml2 libxslt1.1 libatomic1 libevent-2.1-7 libavif15"
    ;;
  ubuntu-noble)
    # Ubuntu 24.04 — playwright-core nativeDeps "ubuntu24.04-x64"
    PACKAGES="libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 libavcodec60 libcairo-gobject2 libfontconfig1 libfreetype6 libgdk-pixbuf-2.0-0 libgtk-3-0t64 libpangocairo-1.0-0 libx11-xcb1 libxcb-shm0 libxcursor1 libxi6 libxrender1 gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good libicu74 libatomic1 libenchant-2-2 libepoxy0 libevent-2.1-7t64 libflite1 libgles2 libgstreamer-gl1.0-0 libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-base1.0-0 libgstreamer1.0-0 libgtk-4-1 libharfbuzz-icu0 libharfbuzz0b libhyphen0 libjpeg-turbo8 liblcms2-2 libmanette-0.2-0 libopus0 libpng16-16t64 libsecret-1-0 libvpx9 libwayland-client0 libwayland-egl1 libwayland-server0 libwebp7 libwebpdemux2 libwoff1 libxml2 libxslt1.1 libx264-164 libavif16"
    ;;
  ubuntu-jammy)
    # Ubuntu 22.04 — playwright-core nativeDeps "ubuntu22.04-x64"
    PACKAGES="libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 libnspr4 libnss3 libpango-1.0-0 libwayland-client0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 ffmpeg libcairo-gobject2 libdbus-glib-1-2 libfontconfig1 libfreetype6 libgdk-pixbuf-2.0-0 libgtk-3-0 libpangocairo-1.0-0 libx11-xcb1 libxcb-shm0 libxcursor1 libxi6 libxrender1 libxtst6 libsoup-3.0-0 libenchant-2-2 gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good libicu70 libegl1 libepoxy0 libevdev2 libffi7 libgles2 libglx0 libgstreamer-gl1.0-0 libgstreamer-plugins-base1.0-0 libgstreamer1.0-0 libgtk-4-1 libgudev-1.0-0 libharfbuzz-icu0 libharfbuzz0b libhyphen0 libjpeg-turbo8 liblcms2-2 libmanette-0.2-0 libnotify4 libopengl0 libopenjp2-7 libopus0 libpng16-16 libproxy1v5 libsecret-1-0 libwayland-egl1 libwayland-server0 libwebpdemux2 libwoff1 libxml2 libxslt1.1 libx264-163 libatomic1 libevent-2.1-7 libavif13"
    ;;
  *)
    echo "  skipped — no Playwright dep list for '${ID} ${VERSION_CODENAME:-unknown}'."
    echo "  Install them later as the deploy user with:"
    echo "    npx playwright install-deps chromium firefox webkit"
    exit 0
    ;;
esac

# Word-splitting of $PACKAGES is intentional (one package per word).
# shellcheck disable=SC2086
apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  $PACKAGES

echo "==> Done."
