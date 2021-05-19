EAPI=7

REQUIRED_BUILDSPACE='16G'

inherit webbrowser-1 git-r3 flag-o-matic pax-utils desktop

KEYWORDS="~x86 ~amd64"
DESCRIPTION="Webbrowser - fork of Pale Moon"
HOMEPAGE="https://git.nuegia.net/webbrowser.git"

SLOT="0"
LICENSE="MPL-2.0 GPL-2 LGPL-2.1"
IUSE="
	+devtools
	+gtk2
	-gtk3
	jack
	+jemalloc
	+optimize
	-pulseaudio
	+system-bz2
	+system-jpeg
	+system-libevent
	+system-libvpx
	+system-zlib
	+threads
	-valgrind
	-webrtc
"

EGIT_REPO_URI="https://git.nuegia.net/webbrowser.git"
EGIT_COMMIT="v${PV}"

DEPEND="
	>=sys-devel/autoconf-2.13:2.1
	dev-lang/python:2.7
	>=dev-lang/perl-5.6
	dev-lang/yasm
"

RDEPEND="
	x11-libs/libXt
	app-arch/zip
	media-libs/freetype
	media-libs/fontconfig

	optimize? ( sys-libs/glibc )

	valgrind? ( dev-util/valgrind )

	gtk2? ( >=x11-libs/gtk+-2.18.0:2 )
	gtk3? ( >=x11-libs/gtk+-3.4.0:3 )

	media-libs/alsa-lib
	pulseaudio? ( media-sound/pulseaudio )

	media-video/ffmpeg[x264]

	system-libvpx? ( media-libs/libvpx )
	system-libevent? ( dev-libs/libevent )
	system-jpeg? ( virtual/jpeg )
	system-zlib? ( sys-libs/zlib )
	system-bz2? ( app-arch/bzip2 )

	jack? ( virtual/jack )
"

REQUIRED_USE="
	jemalloc? ( !valgrind )
	^^ ( gtk2 gtk3 )
"

src_prepare() {
	# Ensure that our plugins dir is enabled by default:
	sed -i -e "s:/usr/lib/mozilla/plugins:/usr/lib/nsbrowser/plugins:" \
		"${S}/platform/xpcom/io/nsAppFileLocationProvider.cpp" \
		|| die "sed failed to replace plugin path for 32bit!"
	sed -i -e "s:/usr/lib64/mozilla/plugins:/usr/lib64/nsbrowser/plugins:" \
		"${S}/platform/xpcom/io/nsAppFileLocationProvider.cpp" \
		|| die "sed failed to replace plugin path for 64bit!"

	default
}

src_configure() {
	# Basic configuration:
	mozconfig_init

	mozconfig_disable tests eme parental-controls accessibility gamepad
	mozconfig_disable necko-wifi updater sync mozril-geoloc gconf
	mozconfig_enable alsa

	if use optimize; then
		O='-O2 -pipe -ftree-parallelize-loops=4 -lgomp -fopenmp -msse2 -mfpmath=sse'
		mozconfig_enable "optimize=\"${O}\""
		filter-flags '-O*' '-msse2' '-mfpmath=sse'
	else
		mozconfig_disable optimize
	fi

	if use threads; then
		mozconfig_with pthreads
	fi

	if use jack; then
		mozconfig_enable jack
	else
		mozconfig_disable jack
	fi

	if use jemalloc; then
		mozconfig_enable jemalloc
	fi

	if use valgrind; then
		mozconfig_enable valgrind
	fi

	if use gtk2; then
		mozconfig_enable default-toolkit=\"cairo-gtk2\"
		mozconfig_var __GTK_VERSION 2
		export MOZ_PKG_SPECIAL=2
	fi

	if use gtk3; then
		mozconfig_enable default-toolkit=\"cairo-gtk3\"
		mozconfig_var __GTK_VERSION 3
		export MOZ_PKG_SPECIAL=3
	fi

	if use system-libvpx; then
		mozconfig_enable system-libvpx
	else
		mozconfig_disable system-libvpx
	fi

	if use system-libevent; then
		mozconfig_enable system-libevent
	else
		mozconfig_disable system-libevent
	fi

	if use system-jpeg; then
		mozconfig_enable system-jpeg
	else
		mozconfig_disable system-jpeg
	fi

	if use system-zlib; then
		mozconfig_enable system-zlib
	else
		mozconfig_disable system-zlib
	fi

	if use system-bz2; then
		mozconfig_enable system-bz2
	else
		mozconfig_disable system-bz2
	fi

	if use pulseaudio; then
		mozconfig_enable pulseaudio
	else
		mozconfig_disable pulseaudio
	fi

	if use devtools; then
		mozconfig_enable devtools
	fi

	if use webrtc; then
		mozconfig_enable webrtc
	else
		mozconfig_disable webrtc
	fi

	# Enabling this causes xpcshell to hang during the packaging process,
	# so disabling it until the cause can be tracked down. It most likely
	# has something to do with the sandbox since the issue goes away when
	# building with FEATURES="-sandbox -usersandbox".
	mozconfig_disable precompiled-startupcache

	# Mainly to prevent system's NSS/NSPR from taking precedence over
	# the built-in ones:
	append-ldflags -Wl,-rpath="${EPREFIX}/usr/$(get_libdir)/webbrowser"

	export MOZBUILD_STATE_PATH="${WORKDIR}/mach_state"
	mozconfig_opt PYTHON $(which python2)
	mozconfig_opt AUTOCONF $(which autoconf-2.13)
	mozconfig_opt MOZ_MAKE_FLAGS "\"${MAKEOPTS}\""
	# TODO: hardcoded ones
	mozconfig_ac --x-libraries /usr/lib64
	mozconfig_var _BUILD_64 1
	mozconfig_opt AUTOCLOBBER 1

	# Shorten obj dir to limit some errors linked to the path size hitting
	# a kernel limit (127 chars):
	mozconfig_opt MOZ_OBJDIR "@TOPSRCDIR@/o"

	# Disable mach notifications, which also cause sandbox access violations:
	export MOZ_NOSPAM=1
}

src_compile() {
	# Prevents portage from setting its own XARGS which messes with the
	# build system checks:
	# See: https://gitweb.gentoo.org/proj/portage.git/tree/bin/isolated-functions.sh
	export XARGS="$(which xargs)"

	python2 "${S}/platform/mach" build || die
}

src_install() {
	# obj_dir changes depending on arch, compiler, etc:
	local obj_dir="$(echo */config.log)"
	obj_dir="${obj_dir%/*}"

	# Disable MPROTECT for startup cache creation:
	pax-mark m "${obj_dir}"/dist/bin/xpcshell

	# Set the backspace behaviour to be consistent with the other platforms:
	set_pref "browser.backspace_action" 0

	# Gotta create the package, unpack it and manually install the files
	# from there not to miss anything (e.g. the statusbar extension):
	einfo "Creating the package..."
	python2 "${S}/platform/mach" mozpackage || die
	local extracted_dir="${T}/package"
	mkdir -p "${extracted_dir}"
	cd "${extracted_dir}"
	einfo "Extracting the package..."
	tar xjpf "${S}/${obj_dir}/dist/${P}.linux-${CTARGET_default%%-*}-2.tar.bz2"
	einfo "Installing the package..."
	local dest_libdir="/usr/$(get_libdir)"
	mkdir -p "${D}/${dest_libdir}"
	cp -rL "${PN}" "${D}/${dest_libdir}"
	dosym "${dest_libdir}/${PN}/${PN}" "/usr/bin/${PN}"
	einfo "Done installing the package."

	# Until JIT-less builds are supported,
	# also disable MPROTECT on the main executable:
	pax-mark m "${D}/${dest_libdir}/${PN}/"{webbrowser,webbrowser-bin,plugin-container}

	# Install icons and .desktop for menu entry:
	install_branding_files
}
