# Both the root dispatcher and individual modules use the same platform names.
ifndef PLATFORM
ifeq ($(OS),Windows_NT)
PLATFORM := windows
else
PLATFORM := $(shell uname -s | tr '[:upper:]' '[:lower:]')
endif
endif
