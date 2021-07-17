CONTENTS_DIR=dist/Gridmonger.app/Contents/
MACOS_DIR=$CONTENTS_DIR/MacOS/
RESOURCES_DIR=$CONTENTS_DIR/Resources/
EXE=Gridmonger
DIST_NAME=gridmonger-macosx
VERSION=1.0

mkdir -p $CONTENTS_DIR

# Copy plist file & set version
sed "s/{VERSION}/$VERSION/g" Info.plist >$CONTENTS_DIR/Info.plist

# Copy main executable
mkdir -p $MACOS_DIR
cp $EXE $MACOS_DIR

# Copy resources
mkdir -p $RESOURCES_DIR
cp -R Data $RESOURCES_DIR
cp -R "Example Maps" $RESOURCES_DIR
cp -R Manual $RESOURCES_DIR
cp -R Themes $RESOURCES_DIR
cp -R gridmonger.icns $RESOURCES_DIR

# Clean executable
strip -S $MACOS_DIR/$EXE
xattr -cr $MACOS_DIR/$EXE

#codesign --verbose --sign "Developer ID Application: Andrew Belt (VRF26934X5)" --options runtime --entitlements Entitlements.plist --deep dist/Gridmonger.app
#codesign --verify --deep --strict --verbose=2 dist/Gridmonger.app

# Make ZIP
cd dist && zip -q -9 -r $DIST_NAME.zip Gridmonger.app
