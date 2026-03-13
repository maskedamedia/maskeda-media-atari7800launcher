APP ?= Atari7800Launcher

.PHONY: build build-release run package clean

build:
	swift build

build-release:
	swift build -c release

run:
	swift run $(APP) $(ARGS)

package:
	bash scripts/package-app.sh

clean:
	rm -rf .build dist
