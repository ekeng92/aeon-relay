.PHONY: build app install uninstall run clean test

APP_NAME     = AEON Relay
BINARY_NAME  = AEONRelay
BUILD_DIR    = .build/release
APP_BUNDLE   = build/$(APP_NAME).app
INSTALL_DIR  = $(HOME)/Applications
GIT_SHA      = $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo "dev")

build:
	@echo "Compiling $(BINARY_NAME)..."
	@swift build -c release 2>&1 | grep -v "^$$" | tail -5
	@echo "Done — binary at $(BUILD_DIR)/$(BINARY_NAME)"

app:
	@echo "Creating app bundle..."
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@# Stamp build commit SHA into BuildInfo.swift then compile
	@BUILD_SHA=$$(git rev-parse --short HEAD 2>/dev/null || echo "dev"); \
	 sed -i '' "s/static let commitSHA = \".*\"/static let commitSHA = \"$$BUILD_SHA\"/" Sources/AEONRelay/BuildInfo.swift; \
	 echo "Compiling $(BINARY_NAME) ($$BUILD_SHA)..."; \
	 swift build -c release 2>&1 | grep -v "^$$" | tail -5
	@cp "$(BUILD_DIR)/$(BINARY_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	@# Restore BuildInfo.swift to placeholder so the repo stays clean
	@sed -i '' 's/static let commitSHA = ".*"/static let commitSHA = "dev"/' Sources/AEONRelay/BuildInfo.swift
	@cp resources/Info.plist "$(APP_BUNDLE)/Contents/"
	@# Stamp build version with git SHA
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(GIT_SHA)" "$(APP_BUNDLE)/Contents/Info.plist" 2>/dev/null || true
	@test -f resources/AppIcon.icns && cp resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/" || true
	@codesign --force --deep --sign - "$(APP_BUNDLE)" 2>/dev/null || true
	@touch "$(APP_BUNDLE)"
	@echo "Built: $(APP_BUNDLE) ($(GIT_SHA))"

run: app
	@open "$(APP_BUNDLE)"

install: app
	@echo "Installing to $(INSTALL_DIR)..."
	@mkdir -p "$(INSTALL_DIR)"
	@if pgrep -x $(BINARY_NAME) >/dev/null 2>&1; then \
		echo "Stopping running instance..."; \
		osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null || pkill -x $(BINARY_NAME) 2>/dev/null || true; \
		sleep 1; \
	fi
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@codesign --force --deep --sign - "$(INSTALL_DIR)/$(APP_NAME).app" 2>/dev/null || true
	@touch "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed: $(INSTALL_DIR)/$(APP_NAME).app"
	@# Install LaunchAgent for auto-start on login
	@mkdir -p "$(HOME)/Library/LaunchAgents"
	@sed "s|__BINARY_PATH__|$(INSTALL_DIR)/$(APP_NAME).app/Contents/MacOS/$(BINARY_NAME)|g" \
		resources/com.aeon.relay.plist > "$(HOME)/Library/LaunchAgents/com.aeon.relay.plist"
	@launchctl bootout gui/$$(id -u) "$(HOME)/Library/LaunchAgents/com.aeon.relay.plist" 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) "$(HOME)/Library/LaunchAgents/com.aeon.relay.plist" 2>/dev/null || true
	@echo "LaunchAgent installed (auto-start on login)"
	@echo "Opening..."
	@open "$(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	@echo "Uninstalling $(APP_NAME)..."
	@if pgrep -x $(BINARY_NAME) >/dev/null 2>&1; then \
		pkill -x $(BINARY_NAME) 2>/dev/null || true; \
	fi
	@launchctl bootout gui/$$(id -u) "$(HOME)/Library/LaunchAgents/com.aeon.relay.plist" 2>/dev/null || true
	@rm -f "$(HOME)/Library/LaunchAgents/com.aeon.relay.plist"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@rm -rf "$(HOME)/.aeon-relay"
	@echo "Removed from $(INSTALL_DIR), LaunchAgent, and ~/.aeon-relay"

test:
	@swift test 2>&1

clean:
	@rm -rf .build build
	@echo "Clean"
