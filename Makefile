.PHONY: all build test install uninstall clean

all: build

build:
	@./scripts/build.sh

test: build
	@swiftc -O \
	  -F build/StepView.app/Contents/Frameworks \
	  -I build/StepView.app/Contents/Frameworks/StepCADCore.framework/Headers \
	  -Xlinker -rpath -Xlinker @executable_path/StepView.app/Contents/Frameworks \
	  -framework Foundation -framework AppKit -framework SceneKit -framework QuickLookUI -framework StepCADCore \
	  StepView/src/CADGeometryBuilder.swift \
	  StepView/src/CADSceneView.swift \
	  StepViewQL/src/PreviewViewController.swift \
	  scripts/test_runner.swift \
	  -o build/test_runner
	@./build/test_runner

install: build
	@./scripts/install.sh

uninstall:
	@./scripts/uninstall.sh

clean:
	@rm -rf build
	@echo "Répertoire build nettoyé."
