# Port Desk

Install Xcode 27.2 and the [Swift 6.4.3 toolchain](docs/architecture.md#build-and-check). Open **Port Desk.xcodeproj**, select **Port Desk** and **My Mac**, then press **⌘R** to launch under the debugger. Select **Listener Checks** and press **⌘R** to run the disposable listener checks.

From a fresh checkout, `./build.sh` produces the signed **Port Desk.app** in the project directory. Run `./build.sh --check` for the same listener checks from Terminal.

Launch **Port Desk.app** in Finder and click the plug and server count in the menu bar. Select a port to open its preview, or expand the row for process details and live readings. Hover for Terminal and Stop. Open the row’s contextual menu for Restart and Command History. Settings controls launch at login, the global shortcut (⌥⌘P by default) and the live refresh interval.

See the [dashboard guide](docs/dashboard.md) for the controls, [build and verification](docs/architecture.md#build-and-check) for the local build, or the [documentation index](docs/INDEX.md) to make a change.
