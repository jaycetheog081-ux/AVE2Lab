# AVE2Lab (separate research harness)

This is a standalone Objective-C iOS app built through GitHub Actions. It is intentionally separate from hurr1c4ne and Radix.

## What it does
- Runs a modest VideoToolbox H.264 encoding test using synthetic 640x480 frames.
- Displays iOS version, submission errors, completion status, and successful output callback count.
- Does not inspect or disclose exploit details in hurr1c4ne.
- Does not intentionally corrupt kernel memory or trigger a kernel panic.
- A successful encode does **not** prove AppleAVE2 was used or establish that the suspected kernel code is reachable.

## Build on GitHub using an iPhone
1. Create a new GitHub repository named `AVE2Lab` (public or private).
2. Upload all files and folders in this archive to the repository root, preserving paths.
3. Open the repository's **Actions** tab and run **Build AVE2Lab IPA** (or push to `main`).
4. Open the completed run and download artifact `AVE2Lab-unsigned-ipa`.

## Installation limitation
The workflow creates an **unsigned** IPA. iOS generally will not install an unsigned app directly. You need a signing/install method compatible with your device and iOS version, or modify the workflow to sign with your own Apple development certificate and provisioning profile. Do not upload certificates or private keys to a public repository.

## Build notes
The workflow uses XcodeGen and Xcode 16.4 on a macOS GitHub Actions runner. If that Xcode version is not available on the selected runner, change the Xcode selection step to the installed version reported by the runner.
