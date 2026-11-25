# Sets SWIFTC to a working compiler command. Sourced by the other scripts.
mkdir -p build
SWIFTC=(swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0")

# Some Command Line Tools upgrades leave behind a module.modulemap that declares
# SwiftBridging a second time, which breaks every build. Hide it from this
# compiler run only; nothing on the system is changed.
() {
  local dir="$(xcode-select -p)/usr/include/swift"
  if [[ -f $dir/module.modulemap && -f $dir/bridging.modulemap ]] \
     && grep -q 'module SwiftBridging' $dir/module.modulemap; then
    : > build/empty.modulemap
    cat > build/overlay.yaml <<Y
{"version": 0, "case-sensitive": "false", "roots": [
  {"type": "directory", "name": "$dir", "contents": [
    {"type": "file", "name": "module.modulemap", "external-contents": "$PWD/build/empty.modulemap"}]}]}
Y
    SWIFTC+=(-vfsoverlay "$PWD/build/overlay.yaml")
  fi
}
