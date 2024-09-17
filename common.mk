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

CD := cd
INSTALL := install
RM := rm
SHELLCHECK := shellcheck

PREFIX ?= $(HOME)/.local

BINDIR := $(PREFIX)/bin
DESTDIR := $(PREFIX)/share/$(NAME)
DOCDIR := $(PREFIX)/share/doc/$(NAME)
