#!/bin/bash
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# inspired by https://github.com/Originate/guide/blob/master/android/guide/Continuous%20Integration.md

# shellcheck disable=SC1091
source "scripts/.tests.env"

function getAndroidPackages {
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools:$ANDROID_HOME/tools.bin:$PATH"

  DEPS="$ANDROID_HOME/installed-dependencies"

  # Package names can be obtained using `sdkmanager --list`
  if [ ! -e "$DEPS" ] || [ ! "$CI" ]; then
    echo "Installing Android API level $ANDROID_SDK_TARGET_API_LEVEL, Google APIs, $AVD_ABI system image..."
    echo y | sdkmanager "system-images;android-$ANDROID_SDK_TARGET_API_LEVEL;google_apis;$AVD_ABI"
    echo "Installing build SDK for Android API level $ANDROID_SDK_BUILD_API_LEVEL..."
    echo y | sdkmanager "platforms;android-$ANDROID_SDK_BUILD_API_LEVEL"
    echo "Installing target SDK for Android API level $ANDROID_SDK_TARGET_API_LEVEL..."
    echo y | sdkmanager "platforms;android-$ANDROID_SDK_TARGET_API_LEVEL"
    echo "Installing SDK build tools, revision $ANDROID_SDK_BUILD_TOOLS_REVISION..."
    echo y | sdkmanager "build-tools;$ANDROID_SDK_BUILD_TOOLS_REVISION"
    # These moved to "system-images;android-$ANDROID_SDK_BUILD_API_LEVEL;google_apis;x86" starting with API level 25, but there is no ARM version.
    echo "Installing Google APIs $ANDROID_GOOGLE_API_LEVEL..."
    echo y | sdkmanager "add-ons;addon-google_apis-google-$ANDROID_GOOGLE_API_LEVEL"
    echo "Installing Android Support Repository"
    echo y | sdkmanager "extras;android;m2repository"
    $CI && touch "$DEPS"
  fi
}

function getAndroidNDK {
  NDK_HOME="/opt/ndk"
  DEPS="$NDK_HOME/installed-dependencies"

  if [ ! -e $DEPS ]; then
    cd $NDK_HOME || exit
    echo "Downloading NDK..."
    curl -o ndk.zip https://dl.google.com/android/repository/android-ndk-r17c-linux-x86_64.zip
    unzip -o -q ndk.zip
    echo "Installed Android NDK at $NDK_HOME"
    touch $DEPS
    rm ndk.zip
  fi
}

function createAVD {
  AVD_PACKAGES="system-images;android-$ANDROID_SDK_TARGET_API_LEVEL;google_apis;$AVD_ABI"
  echo "Creating AVD with packages $AVD_PACKAGES"
  echo no | avdmanager create avd --name "$AVD_NAME" --force --package "$AVD_PACKAGES" --tag google_apis --abi "$AVD_ABI"
}

function launchAVD {
  # The AVD name here should match the one created in createAVD
  if [ "$CI" ]
  then
    "$ANDROID_HOME/emulator/emulator" -avd "$AVD_NAME" -no-audio -no-window
  else
    "$ANDROID_HOME/emulator/emulator" -avd "$AVD_NAME"
  fi
}

function waitForAVD {
  echo "Waiting for Android Virtual Device to finish booting..."
  local bootanim=""
  export PATH=$(dirname $(dirname $(command -v android)))/platform-tools:$PATH
  until [[ "$bootanim" =~ "stopped" ]]; do
    sleep 5
    bootanim=$(adb -e shell getprop init.svc.bootanim 2>&1)
    echo "boot animation status=$bootanim"
  done
  echo "Android Virtual Device is ready."
}

function retry3 {
  local n=1
  local max=3
  local delay=1
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo "Command failed. Attempt $n/$max:"
        sleep $delay;
      else
        echo "The command has failed after $n attempts." >&2
        return 1
      fi
    }
  done
}
