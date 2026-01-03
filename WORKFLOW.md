# GitHub Actions Workflow Documentation

## Overview
This repository includes an automated GitHub Actions workflow that builds and releases the Fitgirl Downloader application for multiple platforms.

## Workflow: Build and Release

**File**: `.github/workflows/build-and-release.yml`

### Triggers
The workflow is triggered when:
- A push is made to the `main` or `dev` branch
- Changes are detected in the `lib/**` folder (any file in the lib directory)

### Versioning
- Version and build number are automatically extracted from `pubspec.yaml`
- Release tags follow the format: `v{version}+{build_number}` (e.g., `v1.0.0+1`)
- To create a new release, update the version in `pubspec.yaml` and push changes to the `lib/` folder

### Release Types
- **Main branch**: Creates stable releases (not marked as pre-release)
- **Dev branch**: Creates pre-releases (marked as pre-release on GitHub)

### Supported Platforms

#### Android
- **Universal APK**: Includes all architectures (armeabi-v7a, arm64-v8a, x86_64)
- File: `fitgirl-downloader-v{version}-android-universal.apk`

#### Windows
- **x64**: 64-bit Windows desktop application installer
- File: `fitgirl-downloader-v{version}-windows-x64-setup.exe`
- **Note**: Flutter currently only supports x64 for Windows desktop. 32-bit and ARM64 builds are not available.
- This is a self-contained installer that includes all necessary files

#### Linux
- **x64**: 64-bit Linux desktop application
- File: `fitgirl-downloader-v{version}-linux-x64.tar.gz`
- **Note**: Flutter currently only supports x64 for Linux desktop. ARM64 builds are not available.

#### macOS
- **Universal**: Contains both Intel (x64) and Apple Silicon (ARM64) binaries
- File: `fitgirl-downloader-v{version}-macos-universal.zip`
- Works on both Intel Macs and Apple Silicon Macs

#### iOS
- **Unsigned IPA**: iOS application bundle without code signing
- File: `fitgirl-downloader-v{version}-ios-unsigned.zip`
- **Note**: Requires signing with your own certificate before installation on devices

### How to Create a New Release

1. **Update Version**: Edit `pubspec.yaml` and change the version number:
   ```yaml
   version: 1.1.0+2  # Update this line
   ```

2. **Make Changes**: Make your code changes in the `lib/` folder

3. **Commit and Push**: Commit your changes and push to either `main` or `dev` branch:
   ```bash
   git add .
   git commit -m "Your commit message"
   git push origin main  # or dev for pre-release
   ```

4. **Wait for Build**: The workflow will automatically:
   - Build all platform binaries
   - Create a new GitHub release
   - Upload all build artifacts to the release

5. **Check Release**: Visit the "Releases" page on GitHub to see your new release with all platform builds

### Build Process
Each platform is built in parallel to speed up the release process:
1. **Prepare**: Extracts version info and determines release type
2. **Build Jobs**: Runs simultaneously for each platform
3. **Release**: Collects all artifacts and creates a GitHub release

### Troubleshooting

#### Workflow Not Triggering
- Ensure changes are in the `lib/**` folder
- Check that you're pushing to `main` or `dev` branch
- Review the "Actions" tab on GitHub for workflow status

#### Build Failures
- Check the workflow logs in the "Actions" tab
- Ensure `pubspec.yaml` is valid and contains a version line
- Verify all dependencies are compatible with the Flutter version (3.27.1)

#### Missing Platforms
- Flutter has platform limitations:
  - Windows: Only x64 supported
  - Linux: Only x64 supported
  - These are Flutter framework limitations, not workflow issues

### Customization

#### Change Flutter Version
Edit the `flutter-version` in each build job:
```yaml
- name: Set up Flutter
  uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.27.1'  # Change this
    channel: 'stable'
```

#### Add More Triggers
Edit the `on:` section to add more triggers:
```yaml
on:
  push:
    branches:
      - main
      - dev
    paths:
      - 'lib/**'
  workflow_dispatch:  # Add manual trigger
```

#### Modify Release Notes
Edit the `body:` section in the release job to customize release notes.

## GitHub Permissions
The workflow requires:
- Read access to repository contents
- Write access to create releases and upload assets
- These are provided by `GITHUB_TOKEN` (automatically available)

## Best Practices
1. Always test changes locally before pushing
2. Use semantic versioning (MAJOR.MINOR.PATCH+BUILD)
3. Use dev branch for testing releases
4. Only push to main for production releases
5. Review workflow logs if builds fail
