#!/bin/sh
# Xcode Cloud: Jendapp.xcodeproj is gitignored, so generate it from project.yml after cloning.
# Builds start on pushes to the `release` branch; Xcode Cloud sets the build number.
set -eu
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen
