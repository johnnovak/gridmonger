# TODO remove comments
defineTheme:
  ui:
    window:
      background:
        color:              Color  # general.backgroundColor
        image:              string
      titleBackground:
        active:             Color  # window.backgroundColor
        inactive:           Color  # window.bgColorUnfocused
      title:
        active:             Color  # window.textColor
        inactive:           Color  # window.textColorUnfocused
      modifiedFlagColor:    Color  # window.modifiedFlagColor
      button:
        normal:             Color  # window.buttonColor
        hover:              Color  # window.buttonColorHover
        down:               Color  # window.buttonColorDown

    dialog:
      cornerRadius:         float  # dialog.cornerRadius
      background:           Color  # dialog.backgroundColor
      label:                Color  # dialog.textColor
      warning:              Color  # dialog.warningTextColor
      title:
        background:         Color  # dialog.titleBarBgColor
        foreground:         Color  # dialog.titleBarTextColor
      outerBorder:
        color:              Color  # dialog.outerBorderColor
        width:              float  # dialog.outerBorderWidth
      innerBorder:
        color:              Color  # dialog.innerBorderColor
        width:              float  # dialog.innerBorderWidth
      shadow:
        enabled:            bool   # dialog.shadow
        xOffset:            float  # dialog.shadowXOffset
        yOffset:            float  # dialog.shadowYOffset
        feather:            float  # dialog.shadowFeather
        color:              Color  # dialog.shadowColor

    widget:
      cornerRadius:                 float  # general.cornerRadius
      background:
        normal:              Color  # widget.bgColor
        hover:         Color  # widget.bgColorHover
        active:        Color  # general.highlightColor
        disabled:      Color  # widget.bgColorDisabled
      foreground:
        color:              Color  # widget.textColor
        active:        Color  # widget.textColorActive
        disabled:      Color  # widget.textColorDisabled

    textField:
      edit:
        background:  Color  # textField.bgColorActive
        text:        Color  # textField.textColorActive
      cursor:          Color  # textField.cursorColor
      selection:       Color  # textField.selectionColor
      scrollBar:
        normal:        Color  # textField.scrollBarColorNormal
        edit:          Color  # textField.scrollBarColorEdit

    statusBar:
      background:      Color  # statusBar.backgroundColor
      text:            Color  # statusBar.textColor
      coordinates:     Color  # statusBar.coordsColor
      command:
        background:    Color  # statusBar.commandBgColor
        text:          Color  # statusBar.commandColor

    aboutButton:
      label:
        normal:              Color  # aboutButton.color
        hover:         Color  # aboutButton.colorHover
        down:          Color  # aboutButton.colorActive

    aboutDialog:
      logo:            Color  # aboutDialog.logoColor

    splashImage:
      logo:            Color  # splashImage.logoColor
      outline:         Color  # splashImage.outlineColor
      shadowAlpha:          float  # splashImage.shadowAlpha

  level:
    general:
      background:      Color  # level.backgroundColor
      foreground:
        normal:              Color  # level.drawColor
        light:         Color  # level.lightDrawColor
      lineWidth:            LineWidth # level.lineWidth
      coordinates:
        normal:              Color  # level.coordsColor
        highlight:     Color  # level.coordsHighlightColor
      cursor:          Color  # level.cursorColor
      cursorGuides:        Color  # level.cursorGuideColor
      selection:       Color  # level.selectionColor
      pastePreview:    Color  # level.pastePreviewColor
      linkMarker:      Color  # level.linkMarkerColor
      trail:           Color  # level.trailColor
      regionBorder:
        normal:              Color  # level.regionBorderColor
        empty:         Color  # level.regionBorderEmptyColor

    backgroundHatch:
      enabled:              bool   # level.bgHatch
      stroke:                Color  # level.bgHatchColor
      width:                float  # level.bgHatchStrokeWidth
      spacingFactor:        float  # level.bgHatchSpacingFactor

    grid:
      background:
        style:              GridStyle # level.gridStyleBackground
        grid:          Color     # level.gridColorBackground
      floor:
        style:              GridStyle # level.gridStyleFloor
        grid:          Color     # level.gridColorFloor

    outline:
      style:                OutlineStyle # level.outlineStyle
      fillStyle:            OutlineFillStyle # level.outlineFillStyle
      color:                Color  # level.outlineColor
      widthFactor:          float  # level.outlineWidthFactor
      overscanEnabled:      bool   # level.outlineOverscan

    shadow:
      inner:
        color:              Color  # level.innerShadowColor
        widthFactor:        float  # level.innerShadowWidthFactor
      outer:
        color:              Color  # level.outerShadowColor
        widthFactor:        float  # level.outerShadowWidthFactor

    floorColor:
      transparentFloor:     bool   # level.transparentFloor
      color:                array[10, Color]  # level.floorColor[0]

    note:
      marker:          Color  # level.noteMarkerColor
      comment:         Color  # level.noteCommentColor
      backgroundShape:      NoteBackgroundShape
      index:
        background:    array[4, Color]  # level.noteIndexBgColor[0]
        text:              Color  # level.noteIndexColor
      tooltip:
        background:    Color  # level.noteTooltipBgColor
        text:              Color  # level.noteTooltipTextColor

    label:
      color:                array[4, Color] # level.labelColor[0]

    levelDropDown:
      button:
        normal:              Color  # leveldropDown.buttonColor
        hover:         Color  # leveldropDown.buttonColorHover
        label:         Color  # leveldropDown.textColor
      itemListBackground:      Color  # leveldropDown.itemListColor
      item:
        normal:              Color  # leveldropDown.itemColor
        hover:         Color  # leveldropDown.itemColorHover

  pane:
    notes:
      text:            Color  # notesPane.textColor
      index:
        background:    array[4, Color] # notesPane.indexBgColor[0]
        text:              Color  # notesPane.indexColor
      scrollBar:       Color  # notesPane.scrollBarColor

    toolbar:
      button:
        normal:              Color  # toolbarPane.buttonBgColor
        hover:         Color  # toolbarPane.buttonBgColorHover

