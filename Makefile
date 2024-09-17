#
# File:    ./Makefile
# Author:  Jiří Kučera <sanczes AT gmail.com>
# Date:    2020-03-29 11:46:31 +0200
# Project: Virtual Machine Tools (vmtools)
# Brief:   Makefile for project maintenance
#
# SPDX-License-Identifier: MIT
#

include ./common.mk

SCRIPTS := vmconfig vminit vmkill vmping vmpkg vmplay vmrepo vmscp vmsetup \
           vmssh vmstart vmstatus vmstop vmtmt vmupdate \
           vmtools-cleanup vmtools-config vmtools-getimage vmtools-images \
           vmtools-rmi vmtools-setup vmtools-vms
LIBRARY := vmtools.sh getimage.sh pkgman.sh

.PHONY: all install check

all: check

install:
	$(INSTALL) -vd $(BINDIR)
	$(INSTALL) -vd $(DESTDIR)
	$(INSTALL) -vd $(DOCDIR)
	$(INSTALL) -vp -m 755 $(SCRIPTS) $(BINDIR)
	$(INSTALL) -vp -m 644 $(LIBRARY) $(DESTDIR)
	$(INSTALL) -vp -m 644 README.md $(DOCDIR)
	$(INSTALL) -vp -m 644 LICENSE $(DOCDIR)
	$(INSTALL) -vp -m 644 VERSION $(DOCDIR)

uninstall:
	$(RM) -rv $(DOCDIR)
	$(RM) -rv $(DESTDIR)
	$(CD) $(BINDIR) && $(RM) -fv $(SCRIPTS)

check:
	$(SHELLCHECK) -s bash -S style -x $(LIBRARY) $(SCRIPTS)
