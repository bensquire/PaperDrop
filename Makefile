APP := apps/PaperDrop

.PHONY: test lint format build bundle release clean

test:
	cd $(APP) && swift test

# Apple's toolchain-bundled `swift format` — no external dependencies.
lint:
	cd $(APP) && swift format lint --strict --recursive Sources Tests Package.swift

format:
	cd $(APP) && swift format --in-place --recursive Sources Tests Package.swift

build:
	cd $(APP) && swift build -c release -Xswiftc -Osize

bundle:
	$(APP)/bundle.sh

release:
	$(APP)/release.sh

clean:
	cd $(APP) && swift package clean && rm -rf PaperDrop.app PaperDrop.dmg
