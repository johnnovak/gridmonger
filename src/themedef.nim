defineTheme:
  general:
    cornerRadius:       float
    backgroundColor:    Color
    backgroundImage:    string
    highlightColor:     Color

  widget:
    bgColor:            Color
    bgColorHover:       Color
    bgColorDisabled:    Color
    textColor:          Color
    textColorActive:    Color
    textColorDisabled:  Color

  textField:
    bgColorActive:      Color
    textColorActive:    Color
    cursorColor:        Color
    selectionColor:     Color

  dialog:
    cornerRadius:       float
    titleBarBgColor:    Color
    titleBarTextColor:  Color
    backgroundColor:    Color
    textColor:          Color
    warningTextColor:   Color
    outerBorderColor:   Color
    innerBorderColor:   Color
    outerBorderWidth:   float
    innerBorderWidth:   float

    shadow:             bool
    shadowXOffset:      float
    shadowYOffset:      float
    shadowFeather:      float
    shadowColor:        Color

  window:
    backgroundColor:    Color
    bgColorUnfocused:   Color
    textColor:          Color
    textColorUnfocused: Color
    buttonColor:        Color
    buttonColorHover:   Color
    buttonColorDown:    Color
    modifiedFlagColor:  Color

  statusBar:
    backgroundColor:    Color
    textColor:          Color
    commandBgColor:     Color
    commandColor:       Color
    coordsColor:        Color

  levelDropdown:
    buttonColor:        Color
    buttonColorHover:   Color
    textColor:          Color
    itemListColor:      Color
    itemColor:          Color
    itemColorHover:     Color

  aboutButton:
    color:              Color
    colorHover:         Color
    colorActive:        Color

  level:
    backgroundColor:        Color
    drawColor:              Color
    lightDrawColor:         Color
    floorColor:             array[9, Color]
    lineWidth:              LineWidth

    bgHatch:                bool
    bgHatchColor:           Color
    bgHatchStrokeWidth:     float
    bgHatchSpacingFactor:   float

    coordsColor:            Color
    coordsHighlightColor:   Color

    cursorColor:            Color
    cursorGuideColor:       Color

    gridStyleBackground:    GridStyle
    gridStyleFloor:         GridStyle
    gridColorBackground:    Color
    gridColorFloor:         Color

    outlineStyle:           OutlineStyle
    outlineFillStyle:       OutlineFillStyle
    outlineOverscan:        bool
    outlineColor:           Color
    outlineWidthFactor:     float

    innerShadowColor:       Color
    innerShadowWidthFactor: float
    outerShadowColor:       Color
    outerShadowWidthFactor: float

    pastePreviewColor:      Color
    selectionColor:         Color

    noteMarkerColor:        Color
    noteCommentColor:       Color
    noteIndexColor:         Color
    noteIndexBgColor:       array[4, Color]

    noteTooltipBgColor:     Color
    noteTooltipTextColor:   Color

    linkMarkerColor:        Color

    regionBorderColor:      Color
    regionBorderEmptyColor: Color

  notesPane:
    textColor:          Color
    indexColor:         Color
    indexBgColor:       array[4, Color]

  toolbarPane:
    buttonBgColor:      Color
    buttonBgColorHover: Color

