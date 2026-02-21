# Project Configuration
APP_NAME=VocaGlyph
EXECUTABLE_NAME=voice-to-text
BUILD_DIR=build
RELEASE_DIR=$(BUILD_DIR)/Release
APP_BUNDLE=$(RELEASE_DIR)/$(APP_NAME).app
MACOS_DIR=$(APP_BUNDLE)/Contents/MacOS
RESOURCES_DIR=$(APP_BUNDLE)/Contents/Resources

.PHONY: build-app clean

build-app:
	@echo "Building application via SPM..."
	swift build -c release --build-path $(BUILD_DIR)
	@echo "Assembling macOS App Bundle..."
	rm -rf $(APP_BUNDLE)
	mkdir -p $(MACOS_DIR)
	mkdir -p $(RESOURCES_DIR)
	cp -r $(RELEASE_DIR)/$(EXECUTABLE_NAME) $(MACOS_DIR)/$(APP_NAME)
	# Copy Info.plist explicitly
	cp Info.plist $(APP_BUNDLE)/Contents/
	# Copy generated bundle resources if any
	-cp -r $(RELEASE_DIR)/*.bundle $(RESOURCES_DIR)/ 2>/dev/null || true
	# Copy App Icon
	-cp build/AppIcon.icns $(RESOURCES_DIR)/ 2>/dev/null || true
	@echo "Build successful: $(APP_BUNDLE)"

package-dmg: build-app
	@echo "Packaging DMG installer..."
	create-dmg \
		--volname "$(APP_NAME) Installer" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "$(APP_NAME).app" 150 190 \
		--hide-extension "$(APP_NAME).app" \
		--app-drop-link 450 190 \
		"$(BUILD_DIR)/$(APP_NAME)-Installer.dmg" \
		"$(APP_BUNDLE)"
	@echo "DMG created at $(BUILD_DIR)/$(APP_NAME)-Installer.dmg"

clean:
	rm -rf $(BUILD_DIR) .build
