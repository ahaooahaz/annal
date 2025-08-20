mk = linux.mk
ifeq ($(OS),Windows_NT)
	mk := windows.mk
else
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    mk := linux.mk
else ifeq ($(UNAME_S),Darwin)
    mk := mac.mk
endif
endif

include $(mk)
