include environment.mk
LLVM_VERSION ?= 18.1.7
MOLD_VERSION ?= 2.32.1
SCCACHE_VERSION ?= 0.8.1
RUST_VERSION ?= 1.76.0

.PHONY: all clean llvm mold sccache rust
all: llvm mold sccache rust

$(TOOLCHAIN_DIR):
	mkdir -p $@

LLVM_TARBALL := llvm.txz
$(LLVM_TARBALL):
	curl -LC- -o $@ \
		https://github.com/llvm/llvm-project/releases/download/llvmorg-$(LLVM_VERSION)/clang+llvm-$(LLVM_VERSION)-x86_64-linux-gnu-ubuntu-18.04.tar.xz
llvm: $(LLVM_TARBALL) $(TOOLCHAIN_DIR)
	tar -axf $< --strip-components=1 -C $(TOOLCHAIN_DIR)
	# Ubuntu 26.04+ ships libxml2.so.16; the prebuilt ld.lld/clang need libxml2.so.2.
	# Shim the old soname into toolchain/lib (on LD_LIBRARY_PATH); no-op where .so.2 exists.
	@if [ ! -e $(TOOLCHAIN_DIR)/lib/libxml2.so.2 ] && [ -e /usr/lib/x86_64-linux-gnu/libxml2.so.16 ]; then \
		ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.16 $(TOOLCHAIN_DIR)/lib/libxml2.so.2 ; \
		echo "toolchain.mk: created libxml2.so.2 -> libxml2.so.16 shim (Ubuntu 26.04+)" ; \
	fi

MOLD_TARBALL := mold.tgz
$(MOLD_TARBALL):
	curl -LC- -o $@ \
		https://github.com/rui314/mold/releases/download/v$(MOLD_VERSION)/mold-$(MOLD_VERSION)-x86_64-linux.tar.gz
mold: $(MOLD_TARBALL) $(TOOLCHAIN_DIR)
	tar -axf $< --strip-components=1 -C $(TOOLCHAIN_DIR)

SCCACHE_TARBALL := sccache.tgz
$(SCCACHE_TARBALL):
	curl -LC- -o $@ \
		https://github.com/mozilla/sccache/releases/download/v$(SCCACHE_VERSION)/sccache-v$(SCCACHE_VERSION)-x86_64-unknown-linux-musl.tar.gz
sccache: $(SCCACHE_TARBALL) $(TOOLCHAIN_DIR) $(TOOLCHAIN_DIR)
	tar -axf $< --strip-components=1 -C $(TOOLCHAIN_DIR)/bin --wildcards */sccache

rustup:
	curl -fsSL https://sh.rustup.rs -o $@
rust: rustup $(TOOLCHAIN_DIR)
	sh $< -y --target=x86_64-unknown-linux-musl --no-modify-path --no-update-default-toolchain --default-toolchain=$(RUST_VERSION) --verbose

clean:
	rm -rf $(TOOLCHAIN_DIR) $(LLVM_TARBALL) $(MOLD_TARBALL) $(SCCACHE_TARBALL) rustup
