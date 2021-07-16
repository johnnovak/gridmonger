CONTENTS_DIR=Gridmonger.app/Contents/
MACOS_DIR=Gridmonger.app/Contents/MacOS/
RESOURCES_DIR=Gridmonger.app/Contents/Resources/
TARGET=Gridmonger
DIST_NAME=gridmonger-macosx

mkdir -p dist/$CONTENTS_DIR
cp Info.plist dist/$CONTENTS_DIR

# $(SED) 's/{VERSION}/$(VERSION)/g' dist/Gridmonger.app/Contents/Info.plist
mkdir -p dist/$MACOS_DIR
cp $TARGET dist/$MACOS_DIR
cp -R Data dist/$MACOS_DIR
cp -R Themes dist/$MACOS_DIR
cp -R Manual dist/$MACOS_DIR
cp -R "Example Maps" dist/$MACOS_DIR

strip -S dist/$MACOS_DIR/$TARGET
mkdir -p dist/$RESOURCES_DIR
cp -R icon.icns dist/$RESOURCES_DIR

# Manually check that no nonstandard shared libraries are linked
#otool -L dist/$MACOS_DIR/$TARGET

# Clean up and sign bundle
xattr -cr dist/Gridmonger.app

# This will only work if you have the private key to my certificate
#codesign --verbose --sign "Developer ID Application: Andrew Belt (VRF26934X5)"
#--options runtime --entitlements Entitlements.plist --deep dist/Gridmonger.app
#codesign --verify --deep --strict --verbose=2 dist/Gridmonger.app

# Make ZIP
#cd dist && zip -q -9 -r $DIST_NAME.zip Gridmonger.app
