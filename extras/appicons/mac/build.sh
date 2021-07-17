INFILE="gridmonger-1024x1024.png"
ICONSET_DIR="gridmonger.iconset"
mkdir $ICONSET_DIR

sips -z 16 16     $INFILE --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     $INFILE --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     $INFILE --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     $INFILE --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   $INFILE --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   $INFILE --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   $INFILE --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   $INFILE --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   $INFILE --out "$ICONSET_DIR/icon_512x512.png"

cp $INFILE $ICONSET_DIR/icon_512x512@2x.png
cp $INFILE $ICONSET_DIR/icon_1024x1024.png

iconutil -c icns $ICONSET_DIR

rm -R $ICONSET_DIR
