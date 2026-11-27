# Port Desk

Install Xcode 27.2 and the [Swift 6.4.3 toolchain](docs/architecture.md#build-and-check). Open **Port Desk.xcodeproj**, select **Port Desk** and **My Mac**, then press **⌘R** to launch under the debugger. Select **Listener Checks** and press **⌘R** to run the disposable listener checks.

From a fresh checkout, `./build.sh` produces the signed **Port Desk.app** in the project directory. Run `./build.sh --check` for the same listener checks from Terminal.

Launch **Port Desk.app** in Finder, then click the terminal icon in the macOS menu bar. The panel lists the TCP listeners visible to your account. Open a development port in your browser to identify the preview, then choose **Stop** or **Restart** to review its command. Hover over a row action for its name. Expand **Command history** to see the commands and results, or **Other listeners** to inspect read-only ports.

See the [dashboard guide](docs/dashboard.md) for the controls, [build and verification](docs/architecture.md#build-and-check) for the local build, or the [documentation index](docs/INDEX.md) to make a change.
