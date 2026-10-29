#!/usr/bin/env bash
# Type-checks the iPhone app's Swift on Linux, without a Mac or Actions minutes.
#
# Apple's frameworks do not exist on Linux, so stubs/ declares the parts of
# UIKit, Flutter, AppIntents, DeviceCheck and the rest that ios/Runner uses,
# with Apple's signatures. It catches type errors in our Swift; linking,
# signing and CocoaPods still need Xcode. When Runner uses a new Apple API,
# add it to the matching stub.
#
# Needs Docker. Run from anywhere: tool/swift_typecheck/typecheck.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
image="${SWIFT_IMAGE:-swift:6.0-noble}"

docker run --rm -v "$here:/check:ro" -v "$repo/ios/Runner:/runner:ro" "$image" bash -c '
  set -euo pipefail
  work="$(mktemp -d)"
  mkdir "$work/out" "$work/src"
  cp /runner/*.swift "$work/src/"
  # Linux Swift has no Objective-C runtime.
  sed -i "s/@objc class /class /" "$work/src/"*.swift
  for module in UIKit UniformTypeIdentifiers UserNotifications Flutter DeviceCheck AppIntents; do
    swiftc -swift-version 5 -parse-as-library -emit-module -module-name "$module" \
      -I "$work/out" -o "$work/out/$module.swiftmodule" "/check/stubs/$module.swift"
  done
  swiftc -swift-version 5 -typecheck -I "$work/out" "$work/src/"*.swift
  echo "Swift type-checks."
'
