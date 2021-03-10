# SPDX-License-Identifier: MIT
#
# File:    Makefile
# Author:  Jiří Kučera, <sanczes@gmail.com>
# Date:    2020-03-29 11:46:31 +0200
# Project: Virtual Machine Tools (vmtools)
# Brief:   Makefile for project maintenance.
#

include ./common.mk

SCRIPTS := vmconfig vminit vmkill vmping vmplay vmscp vmsetup vmssh vmstart \
           vmstatus vmstop vmupdate vmtools-config vmtools-getimage \
           vmtools-setup
LIBRARY := vmtools.sh

.PHONY: all install check

all: check

install:
	$(MKDIR) -p $(BINDIR)
	$(MKDIR) -p $(DESTDIR)
	$(MKDIR) -p $(DOCDIR)
	$(INSTALL) -p -m 755 $(SCRIPTS) $(BINDIR)
	$(INSTALL) -p -m 644 $(LIBRARY) $(DESTDIR)
	$(INSTALL) -p -m 644 README.md $(DOCDIR)
	$(INSTALL) -p -m 644 LICENSE $(DOCDIR)
	$(INSTALL) -p -m 644 VERSION $(DOCDIR)

check:
	$(SHELLCHECK) -s bash -S style -x $(LIBRARY) $(SCRIPTS)
