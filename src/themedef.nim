defineTheme:
  ui:
    window:
      backgroundColor:              Color  # general.backgroundColor
      backgroundImage:              string
      titleBackgroundColor:         Color  # window.backgroundColor
      titleBackgroundInactiveColor: Color  # window.bgColorUnfocused
      titleColor:                   Color  # window.textColor
      titleInactiveColor:           Color  # window.textColorUnfocused
      modifiedFlagColor:            Color  # window.modifiedFlagColor
      buttonColor:                  Color  # window.buttonColor
      buttonHoverColor:             Color  # window.buttonColorHover
      buttonDownColor:              Color  # window.buttonColorDown

    dialog:
      cornerRadius:                 float  # dialog.cornerRadius
      titleBackgroundColor:         Color  # dialog.titleBarBgColor
      titleColor:                   Color  # dialog.titleBarTextColor
      backgroundColor:              Color  # dialog.backgroundColor
      labelColor:                   Color  # dialog.textColor
      warningColor:                 Color  # dialog.warningTextColor
      outerBorderColor:             Color  # dialog.outerBorderColor
      outerBorderWidth:             float  # dialog.outerBorderWidth
      innerBorderColor:             Color  # dialog.innerBorderColor
      innerBorderWidth:             float  # dialog.innerBorderWidth
      shadowEnabled:                bool   # dialog.shadow
      shadowXOffset:                float  # dialog.shadowXOffset
      shadowYOffset:                float  # dialog.shadowYOffset
      shadowFeather:                float  # dialog.shadowFeather
      shadowColor:                  Color  # dialog.shadowColor

    widget:
      cornerRadius:                 float  # general.cornerRadius
      backgroundColor:              Color  # widget.bgColor
      backgroundHoverColor:         Color  # widget.bgColorHover
      backgroundActiveColor:        Color  # general.highlightColor
      backgroundDisabledColor:      Color  # widget.bgColorDisabled
      foregroundColor:              Color  # widget.textColor
      foregroundActiveColor:        Color  # widget.textColorActive
      foregroundDisabledColor:      Color  # widget.textColorDisabled

    textField:
      editBackgroundColor:          Color  # textField.bgColorActive
      editTextColor:                Color  # textField.textColorActive
      cursorColor:                  Color  # textField.cursorColor
      selectionColor:               Color  # textField.selectionColor
      scrollBarNormalColor:         Color  # textField.scrollBarColorNormal
      scrollBarEditColor:           Color  # textField.scrollBarColorEdit

    statusBar:
      backgroundColor:              Color  # statusBar.backgroundColor
      textColor:                    Color  # statusBar.textColor
      commandBackgroundColor:       Color  # statusBar.commandBgColor
      commandColor:                 Color  # statusBar.commandColor
      coordinatesColor:             Color  # statusBar.coordsColor

    aboutButton:
      labelColor:                   Color  # aboutButton.color
      labelHoverColor:              Color  # aboutButton.colorHover
      labelDownColor:               Color  # aboutButton.colorActive

    aboutDialog:
      logoColor:                    Color  # aboutDialog.logoColor

    splashImage:
      logoColor:                    Color  # splashImage.logoColor
      outlineColor:                 Color  # splashImage.outlineColor
      shadowAlpha:                  float  # splashImage.shadowAlpha

  level:
    general:
      backgroundColor:              Color  # level.backgroundColor
      foregroundColor:              Color  # level.drawColor
      foregroundLightColor:         Color  # level.lightDrawColor
      lineWidth:                    LineWidth # level.lineWidth
      coordinatesColor:             Color  # level.coordsColor
      coordinatesHighlightColor:    Color  # level.coordsHighlightColor
      cursorColor:                  Color  # level.cursorColor
      cursorGuidesColor:            Color  # level.cursorGuideColor
      selectionColor:               Color  # level.selectionColor
      pastePreviewColor:            Color  # level.pastePreviewColor
      linkMarkerColor:              Color  # level.linkMarkerColor
      trailColor:                   Color  # level.trailColor
      regionBorderColor:            Color  # level.regionBorderColor
      regionBorderEmptyColor:       Color  # level.regionBorderEmptyColor

    backgroundHatch:
      enabled:                      bool   # level.bgHatch
      color:                        Color  # level.bgHatchColor
      width:                        float  # level.bgHatchStrokeWidth
      spacingFactor:                float  # level.bgHatchSpacingFactor

    grid:
      backgroundStyle:              GridStyle # level.gridStyleBackground
      backgroundGridColor:          Color     # level.gridColorBackground
      floorStyle:                   GridStyle # level.gridStyleFloor
      floorGridColor:               Color     # level.gridColorFloor

    outline:
      style:                        OutlineStyle # level.outlineStyle
      fillStyle:                    OutlineFillStyle # level.outlineFillStyle
      color:                        Color  # level.outlineColor
      widthFactor:                  float  # level.outlineWidthFactor
      overscanEnabled:              bool   # level.outlineOverscan

    shadow:
      innerColor:                   Color  # level.innerShadowColor
      innerWidthFactor:             float  # level.innerShadowWidthFactor
      outerColor:                   Color  # level.outerShadowColor
      outerWidthFactor:             float  # level.outerShadowWidthFactor

    floorColor:
      transparentFloor:             bool   # level.transparentFloor
      color:                        array[10, Color]  # level.floorColor[0]

    note:
      markerColor:                  Color  # level.noteMarkerColor
      commentColor:                 Color  # level.noteCommentColor
      indexBackgroundColor:         array[4, Color]  # level.noteIndexBgColor[0]
      indexColor:                   Color  # level.noteIndexColor
      tooltipBackgroundColor:       Color  # level.noteTooltipBgColor
      tooltipColor:                 Color  # level.noteTooltipTextColor

    label:
      color:                        array[4, Color] # level.labelColor[0]

    levelDropDown:
      buttonColor:                  Color  # leveldropDown.buttonColor
      buttonHoverColor:             Color  # leveldropDown.buttonColorHover
      buttonLabelColor:             Color  # leveldropDown.textColor
      itemListBackgroundColor:      Color  # leveldropDown.itemListColor
      itemColor:                    Color  # leveldropDown.itemColor
      itemHoverColor:               Color  # leveldropDown.itemColorHover

  pane:
    notes:
      textColor:                    Color  # notesPane.textColor
      indexBackgroundColor:         array[4, Color] # notesPane.indexBgColor[0]
      indexColor:                   Color  # notesPane.indexColor
      scrollBarColor:               Color  # notesPane.scrollBarColor

    toolbar:
      buttonColor:                  Color  # toolbarPane.buttonBgColor
      buttonHoverColor:             Color  # toolbarPane.buttonBgColorHover

