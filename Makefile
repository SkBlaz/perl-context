# Makefile for pcontext - Repository Context Dumper
#
# Usage:
#   make test      - Run all tests
#   make install   - Install to PREFIX (default: /usr/local)
#   make uninstall - Remove installed files
#   make clean     - Remove generated files

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/share/perl5

SCRIPTS = pcontext.pl pcontext-mcp pcontext-mcp-standalone
LIBS = lib/PContext.pm

.PHONY: all test install uninstall clean help

all: test

help:
	@echo "pcontext - Repository Context Dumper for LLMs"
	@echo ""
	@echo "Targets:"
	@echo "  make test      - Run all tests"
	@echo "  make install   - Install to PREFIX (default: /usr/local)"
	@echo "  make uninstall - Remove installed files"
	@echo "  make clean     - Remove generated files"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX=/path   - Installation prefix (default: /usr/local)"
	@echo ""
	@echo "Examples:"
	@echo "  make install PREFIX=~/.local"
	@echo "  sudo make install"

test:
	@echo "=== Checking syntax ==="
	perl -c pcontext.pl
	perl -c pcontext-mcp
	perl -c pcontext-mcp-standalone
	perl -c lib/PContext.pm
	@echo ""
	@echo "=== Running pcontext.t ==="
	perl pcontext.t
	@echo ""
	@echo "=== Running pcontext-mcp.t ==="
	perl pcontext-mcp.t
	@echo ""
	@echo "=== All tests passed ==="

install: test
	@echo "Installing to $(PREFIX)..."
	install -d $(BINDIR)
	install -d $(LIBDIR)/PContext
	install -m 755 pcontext.pl $(BINDIR)/pcontext
	install -m 755 pcontext-mcp $(BINDIR)/pcontext-mcp
	install -m 755 pcontext-mcp-standalone $(BINDIR)/pcontext-mcp-standalone
	install -m 644 lib/PContext.pm $(LIBDIR)/PContext.pm
	@echo ""
	@echo "Installed:"
	@echo "  $(BINDIR)/pcontext"
	@echo "  $(BINDIR)/pcontext-mcp"
	@echo "  $(BINDIR)/pcontext-mcp-standalone (self-contained, no deps)"
	@echo "  $(LIBDIR)/PContext.pm"
	@echo ""
	@echo "Note: Add $(LIBDIR) to PERL5LIB if not in default path:"
	@echo "  export PERL5LIB=$(LIBDIR):\$$PERL5LIB"

uninstall:
	@echo "Uninstalling from $(PREFIX)..."
	rm -f $(BINDIR)/pcontext
	rm -f $(BINDIR)/pcontext-mcp
	rm -f $(BINDIR)/pcontext-mcp-standalone
	rm -f $(LIBDIR)/PContext.pm
	-rmdir $(LIBDIR)/PContext 2>/dev/null || true
	@echo "Done"

clean:
	rm -f *.bak lib/*.bak
	rm -f *.tmp
	rm -rf /tmp/pcontext-*
