#
# File:    ./common.mk
# Author:  Jiří Kučera <sanczes AT gmail.com>
# Date:    2020-03-29 12:35:27 +0200
# Project: Virtual Machine Tools (vmtools)
# Brief:   Variables and settings shared across Makefiles
#
# SPDX-License-Identifier: MIT
#

NAME := vmtools

INSTALL := install
MKDIR := mkdir
SHELLCHECK := shellcheck

PREFIX ?= /usr/local

BINDIR := $(PREFIX)/bin
DESTDIR := $(PREFIX)/share/$(NAME)
DOCDIR := $(PREFIX)/share/doc/$(NAME)
