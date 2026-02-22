# Project Configuration
APP_NAME=VocaGlyph
EXECUTABLE_NAME=VocaGlyph
BUILD_DIR=build
RELEASE_DIR=$(BUILD_DIR)/Release
APP_BUNDLE=$(RELEASE_DIR)/$(APP_NAME).app
MACOS_DIR=$(APP_BUNDLE)/Contents/MacOS
RESOURCES_DIR=$(APP_BUNDLE)/Contents/Resources

# App icon source
ICON_SRC=../swift-version/Sources/VocaGlyph/Resources/appicon.png
ICONSET_DIR=$(BUILD_DIR)/AppIcon.iconset
ICNS_FILE=$(BUILD_DIR)/AppIcon.icns

# MLX Metal shader sources from the SPM checkout
MLX_METAL_DIR=$(BUILD_DIR)/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal
MLX_INCLUDE_DIR=$(BUILD_DIR)/checkouts/mlx-swift/Source/Cmlx
MLX_AIR_DIR=$(BUILD_DIR)/mlx-air
MLX_METALLIB=$(BUILD_DIR)/mlx.metallib

.PHONY: build-app clean metallib icns

# Compile MLX Metal shaders into mlx.metallib
# MLX looks for mlx.metallib co-located with the binary (Contents/MacOS/)
metallib: $(MLX_METALLIB)

$(MLX_METALLIB): $(wildcard $(MLX_METAL_DIR)/*.metal)
	@echo "Compiling MLX Metal shaders..."
	@mkdir -p $(MLX_AIR_DIR)
	@for f in $(MLX_METAL_DIR)/*.metal; do \
		name=$$(basename $$f .metal); \
		xcrun metal -std=metal3.1 -O2 -I "$(MLX_INCLUDE_DIR)" -c "$$f" -o "$(MLX_AIR_DIR)/$$name.air"; \
	done
	@xcrun metallib $(MLX_AIR_DIR)/*.air -o $(MLX_METALLIB)
	@echo "MLX metallib compiled: $(MLX_METALLIB) ($$(wc -c < $(MLX_METALLIB) | tr -d ' ') bytes)"

# Generate AppIcon.icns from the source PNG
icns:
	@echo "Generating AppIcon.icns from $(ICON_SRC)..."
	@mkdir -p $(ICONSET_DIR)
	@sips -z 16   16   $(ICON_SRC) --out $(ICONSET_DIR)/icon_16x16.png    > /dev/null
	@sips -z 32   32   $(ICON_SRC) --out $(ICONSET_DIR)/icon_16x16@2x.png > /dev/null
	@sips -z 32   32   $(ICON_SRC) --out $(ICONSET_DIR)/icon_32x32.png    > /dev/null
	@sips -z 64   64   $(ICON_SRC) --out $(ICONSET_DIR)/icon_32x32@2x.png > /dev/null
	@sips -z 128  128  $(ICON_SRC) --out $(ICONSET_DIR)/icon_128x128.png  > /dev/null
	@sips -z 256  256  $(ICON_SRC) --out $(ICONSET_DIR)/icon_128x128@2x.png > /dev/null
	@sips -z 256  256  $(ICON_SRC) --out $(ICONSET_DIR)/icon_256x256.png  > /dev/null
	@sips -z 512  512  $(ICON_SRC) --out $(ICONSET_DIR)/icon_256x256@2x.png > /dev/null
	@sips -z 512  512  $(ICON_SRC) --out $(ICONSET_DIR)/icon_512x512.png  > /dev/null
	@sips -z 1024 1024 $(ICON_SRC) --out $(ICONSET_DIR)/icon_512x512@2x.png > /dev/null
	@iconutil -c icns $(ICONSET_DIR) -o $(ICNS_FILE)
	@echo "AppIcon.icns created: $(ICNS_FILE)"

build-app: $(MLX_METALLIB) icns
	@echo "Building application via SPM..."
	swift build -c release --build-path $(BUILD_DIR)
	@echo "Assembling macOS App Bundle..."
	rm -rf $(APP_BUNDLE)
	mkdir -p $(MACOS_DIR)
	mkdir -p $(RESOURCES_DIR)
	cp -r $(RELEASE_DIR)/$(EXECUTABLE_NAME) $(MACOS_DIR)/$(APP_NAME)
	# Embed MLX Metal library co-located with binary (required by mlx-swift at runtime)
	cp $(MLX_METALLIB) $(MACOS_DIR)/mlx.metallib
	# Copy Info.plist explicitly
	cp Info.plist $(APP_BUNDLE)/Contents/
	# Copy generated bundle resources if any
	-cp -r $(RELEASE_DIR)/*.bundle $(RESOURCES_DIR)/ 2>/dev/null || true
	# Copy App Icon
	cp $(ICNS_FILE) $(RESOURCES_DIR)/AppIcon.icns
	@echo "Build successful: $(APP_BUNDLE)"

package-dmg: build-app
	@echo "Packaging DMG installer..."
	rm -f "$(BUILD_DIR)/$(APP_NAME)-Installer.dmg"
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
