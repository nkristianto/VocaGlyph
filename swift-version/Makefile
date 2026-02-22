# Project Configuration
APP_NAME=VocaGlyph
EXECUTABLE_NAME=voice-to-text
BUILD_DIR=build
RELEASE_DIR=$(BUILD_DIR)/Release
APP_BUNDLE=$(RELEASE_DIR)/$(APP_NAME).app
MACOS_DIR=$(APP_BUNDLE)/Contents/MacOS
RESOURCES_DIR=$(APP_BUNDLE)/Contents/Resources

# MLX Metal shader sources from the SPM checkout
MLX_METAL_DIR=$(BUILD_DIR)/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal
MLX_INCLUDE_DIR=$(BUILD_DIR)/checkouts/mlx-swift/Source/Cmlx
MLX_AIR_DIR=$(BUILD_DIR)/mlx-air
MLX_METALLIB=$(BUILD_DIR)/mlx.metallib

.PHONY: build-app clean metallib

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

build-app: $(MLX_METALLIB)
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
