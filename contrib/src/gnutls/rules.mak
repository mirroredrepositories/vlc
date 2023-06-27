# GnuTLS

GNUTLS_VERSION := 3.6.16
GNUTLS_URL := $(GNUGPG)/gnutls/v3.6/gnutls-$(GNUTLS_VERSION).tar.xz

# nettle/gmp can't be used with the LGPLv2 license
ifdef GPL
GNUTLS_PKG=1
else
ifdef GNUV3
GNUTLS_PKG=1
endif
endif

ifdef BUILD_NETWORK
ifndef HAVE_DARWIN_OS
ifdef GNUTLS_PKG
PKGS += gnutls
endif
endif
endif
ifeq ($(call need_pkg,"gnutls >= 3.5.0"),)
PKGS_FOUND += gnutls
endif

$(TARBALLS)/gnutls-$(GNUTLS_VERSION).tar.xz:
	$(call download_pkg,$(GNUTLS_URL),gnutls)

.sum-gnutls: gnutls-$(GNUTLS_VERSION).tar.xz

gnutls: gnutls-$(GNUTLS_VERSION).tar.xz .sum-gnutls
	$(UNPACK)
	$(APPLY) $(SRC)/gnutls/gnutls-fix-mangling.patch

	# backport gnulib patch
	$(APPLY) $(SRC)/gnutls/0001-Don-t-assume-that-UNICODE-is-not-defined.patch

	# forbidden RtlSecureZeroMemory call in winstore builds
	$(APPLY) $(SRC)/gnutls/0001-explicit_bzero-Do-not-call-SecureZeroMemory-on-UWP-b.patch

	# disable the dllimport in static linking (pkg-config --static doesn't handle Cflags.private)
	sed -i.orig -e s/"_SYM_EXPORT __declspec(dllimport)"/"_SYM_EXPORT"/g $(UNPACK_DIR)/lib/includes/gnutls/gnutls.h.in

	# fix i686 UWP builds as they were using CertEnumCRLsInStore via invalid LoadLibrary
	$(APPLY) $(SRC)/gnutls/0001-fix-mingw64-detection.patch

	# fix AArch64 builds for Apple OS by removing unsupported compiler flag (gnutls#1347, gnutls#1317)
ifdef HAVE_DARWIN_OS
	$(APPLY) $(SRC)/gnutls/gnutls-fix-aarch64-compilation-appleos.patch
endif
ifdef HAVE_ANDROID
	$(APPLY) $(SRC)/gnutls/gnutls-fix-aarch64-compilation-appleos.patch
endif

	$(APPLY) $(SRC)/gnutls/0001-windows-Avoid-Wint-conversion-errors.patch

	# use CreateFile2 in Win8 as CreateFileW is forbidden in UWP
	$(APPLY) $(SRC)/gnutls/0001-Use-CreateFile2-in-UWP-builds.patch

	$(UPDATE_AUTOCONFIG)
	$(MOVE)

GNUTLS_CONF := \
	--disable-gtk-doc \
	--without-p11-kit \
	--disable-cxx \
	--disable-srp-authentication \
	--disable-anon-authentication \
	--disable-openssl-compatibility \
	--disable-guile \
	--disable-nls \
	--without-libintl-prefix \
	--disable-doc \
	--disable-tools \
	--disable-tests \
	--with-included-libtasn1 \
	--with-included-unistring

DEPS_gnutls = nettle $(DEPS_nettle)
ifdef HAVE_WINSTORE
# gnulib uses GetFileInformationByHandle
DEPS_gnutls += alloweduwp $(DEPS_alloweduwp)
endif

ifdef HAVE_ANDROID
GNUTLS_ENV := gl_cv_header_working_stdint_h=yes
endif
ifdef HAVE_WIN32
	GNUTLS_CONF += --without-idn
ifeq ($(ARCH),aarch64)
	# Gnutls' aarch64 assembly unconditionally uses ELF specific directives
	GNUTLS_CONF += --disable-hardware-acceleration
endif
endif

.gnutls: gnutls
	$(MAKEBUILDDIR)
	$(GNUTLS_ENV) $(MAKECONFIGURE) $(GNUTLS_CONF)
ifdef HAVE_DARWIN_OS
	# Add missing frameworks to Libs.private for Darwin
	cd $< && sed -i.orig -e s/"Libs.private:"/"Libs.private: -framework Security -framework CoreFoundation"/g $(BUILD_DIRUNPACK)/lib/gnutls.pc
endif
	$(call pkg_static,"$(BUILD_DIRUNPACK)/lib/gnutls.pc")
	+$(MAKEBUILD) -C gl
	+$(MAKEBUILD) -C lib
	+$(MAKEBUILD) -C gl install
	+$(MAKEBUILD) -C lib install
	touch $@
