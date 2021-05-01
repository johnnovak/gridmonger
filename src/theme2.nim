import math
import options
import parsecfg
import strformat

import nanovg
import with

import common
import cfghelper
import fieldlimits
import macros
import strutils
#import theme


proc `$`(c: Color): string =
  let
    r = round(c.r * 255).int
    g = round(c.g * 255).int
    b = round(c.b * 255).int
    a = round(c.a * 255).int

  fmt"rgba({r}, {g}, {b}, {a})"


proc styleClassName(name: string): string =
  name.capitalizeAscii() & "Style"

proc mkPublicName(name: string): NimNode =
  nnkPostfix.newTree(
    newIdentNode("*"), newIdentNode(name)
  )

proc mkProperty(name: string, typ: NimNode): NimNode =
  nnkIdentDefs.newTree(
    mkPublicName(name), typ, newEmptyNode()
  )

proc mkRefObjectTypeDef(name: string, recList: NimNode): NimNode =
  nnkTypeDef.newTree(
    mkPublicName(name),
    newEmptyNode(),

    nnkRefTy.newTree(
      nnkObjectTy.newTree(
        newEmptyNode(),
        newEmptyNode(),
        recList
      )
    )
  )

proc makeStyleTypeDef(name: string, props: seq[(string, NimNode)]): NimNode =
  var recList = nnkRecList.newTree
  for (propName, propType) in props:
    recList.add(
      mkProperty(propName, propType)
    )

  result = mkRefObjectTypeDef(
    styleClassName(name),
    recList
  )

proc handleProperty(
  prop: NimNode,
  configSectionName: string,
  sectionNameSym, subsectionNameSym: NimNode
): (string, NimNode, NimNode, NimNode) =

  prop[0].expectKind nnkIdent
  let propName = prop[0].strVal

  let propParamsStmt = prop[1]

  var propType: NimNode
  case propParamsStmt[0].kind:
  of nnkIdent:  # no default provided
    propType = propParamsStmt[0]

  of nnkBracketExpr:  # no default provided
    propType = propParamsStmt[0]
    assert propType[0] == newIdentNode("array")
    assert propType[2] == newIdentNode("Color")

  of nnkInfix:  # default provided
    let propParams = propParamsStmt[0]
    propParams.expectLen 3

    assert propParams[0] == newIdentNode("|")
    propType = propParams[1]

  else:
    error("Invalid property definition: " & $propParamsStmt[0].kind)

  # Append loader statement
  let propNameSym = newIdentNode(propName)

  let toProp = quote do:
    result.`sectionNameSym`.`subsectionNameSym`.`propNameSym`

  let fromProp = quote do:
    theme.`sectionNameSym`.`subsectionNameSym`.`propNameSym`

  var parseThemeFrag = nnkStmtList.newTree
  var writeThemeFrag = nnkStmtList.newTree

  if propType.kind == nnkIdent:
    case propType.strVal
    of "string", "bool", "Color", "float":
      let getter = newIdentNode("get" & propType.strVal.capitalizeAscii())

      parseThemeFrag.add quote do:
        config.`getter`(`configSectionName`, `propName`, `toProp`)

      writeThemeFrag.add quote do:
        result.setSectionKey(`configSectionName`, `propName`,
                             $`fromProp`)

    else:  # enum
      parseThemeFrag.add  quote do:
        getEnum[`propType`](config, `configSectionName`, `propName`,
                            `toProp`)

      writeThemeFrag.add  quote do:
        result.setSectionKey(`configSectionName`, `propName`,
                             $`fromProp`)

  elif propType.kind == nnkBracketExpr:
    let propType = propParamsStmt[0]
    assert propType[0] == newIdentNode("array")
    assert propType[2] == newIdentNode("Color")
    let numColors = propType[1].intVal

    for i in 1..numColors:
      let propNameN = propName & $i
      let index = newIntLitNode(i-1)
      let theme = newIdentNode("theme")
      parseThemeFrag.add  quote do:
        config.getColor(`configSectionName`, `propNameN`,
                        `toProp`[`index`])

      writeThemeFrag.add quote do:
        result.setSectionKey(
          `configSectionName`, `propNameN`,
           $`fromProp`[`index`]
         )

  else:
    error("Invalid property type: " & $propType.kind)

  result = (propName, propType, parseThemeFrag, writeThemeFrag)


macro defineTheme(arg: untyped): untyped =
  arg.expectKind nnkStmtList

  var typeSection = nnkTypeSection.newTree
  var themeStyleRecList = nnkRecList.newTree
  var parseThemeBody = nnkStmtList.newTree
  var writeThemeBody = nnkStmtList.newTree

  # Sections
  for section in arg:
    section.expectKind nnkCall
    section.expectLen 2

    section[0].expectKind nnkIdent
    let sectionName = section[0].strVal

    let sectionNameSym = newIdentNode(sectionName)
    let sectionClassNameSym = newIdentNode(styleClassName(sectionName))

    parseThemeBody.add quote do:
      result.`sectionNameSym` = new `sectionClassNameSym`

    section[1].expectKind nnkStmtList

    var sectionPropsToAdd = newSeq[(string, NimNode)]()

    # Sub-sections
    for subsection in section[1]:
      subsection.expectKind nnkCall
      subsection.expectLen 2

      subsection[0].expectKind nnkIdent
      let subsectionName = subsection[0].strVal
      let subsectionNameSym = newIdentNode(subsectionName)

      let prefixedSubsectionName = sectionName & subsectionName.capitalizeAscii()
      let subsectionClassNameSym = newIdentNode(styleClassName(prefixedSubsectionName))

      let propsList = subsection[1]

      var propsToAdd = newSeq[(string, NimNode)]()

      let configSectionName = sectionName & "." & subsectionName

      parseThemeBody.add quote do:
        result.`sectionNameSym`.`subsectionNameSym` = new `subsectionClassNameSym`


      # Properties
      for prop in propsList:
        let (propName, propType, parseThemeFrag, writeThemeFrag) = handleProperty(
          prop,
          configSectionName,
          sectionNameSym, subsectionNameSym
        )
        propsToAdd.add((propName, propType))
        parseThemeBody.add(parseThemeFrag)
        writeThemeBody.add(writeThemeFrag)

      typeSection.add(
        makeStyleTypeDef(prefixedSubsectionName, propsToAdd)
      )

      let sectionPropType = newIdentNode(styleClassName(prefixedSubsectionName))
      sectionPropsToAdd.add((subsectionName, sectionPropType))

    typeSection.add(
      makeStyleTypeDef(sectionName, sectionPropsToAdd)
    )

    themeStyleRecList.add(
      mkProperty(sectionName, newIdentNode(styleClassName(sectionName)))
    )

  typeSection.add(
    mkRefObjectTypeDef("ThemeStyle", themeStyleRecList)
  )

  let config = newIdentNode("config")
  let theme = newIdentNode("theme")

  result = quote do:
    `typeSection`

    proc parseTheme(`config`: Config): ThemeStyle =
      result = new ThemeStyle
      `parseThemeBody`

    proc writeTheme(`theme`: ThemeStyle): Config =
      result = newConfig()
      `writeThemeBody`

  echo result.repr


include themedef2



const
  WidgetCornerRadiusLimits*  = floatLimits(min =   0.0, max = 12.0)

  DialogCornerRadiusLimits*  = floatLimits(min =   0.0, max = 20.0)
  DialogBorderWidthLimits*   = floatLimits(min =   0.0, max = 30.0)
  DialogShadowOffsetLimits*  = floatLimits(min = -10.0, max = 10.0)
  DialogShadowFeatherLimits* = floatLimits(min =   0.0, max = 50.0)

  AlphaLimits*               = floatLimits(min =   0.0, max = 1.0)

  HatchStrokeWidthLimits*    = floatLimits(min =   0.5, max = 10.0)
  HatchSpacingLimits*        = floatLimits(min =   1.0, max = 10.0)

  LevelOutlineWidthLimits*   = floatLimits(min =   0.0, max = 1.0)
  LevelShadowWidthLimits*    = floatLimits(min =   0.0, max = 1.0)


proc loadTheme*(filename: string): ThemeStyle =
  var cfg = loadConfig(filename)
  result = parseTheme(cfg)

  with result.ui.dialog:
    cornerRadius     = cornerRadius.limit(DialogCornerRadiusLimits)
    outerBorderWidth = outerBorderWidth.limit(DialogBorderWidthLimits)
    innerBorderWidth = innerBorderWidth.limit(DialogBorderWidthLimits)
    shadowXOffset    = shadowXOffset.limit(DialogShadowOffsetLimits)
    shadowYOffset    = shadowYOffset.limit(DialogShadowOffsetLimits)
    shadowFeather    = shadowFeather.limit(DialogShadowFeatherLimits)

  with result.ui.widget:
    cornerRadius = cornerRadius.limit(WidgetCornerRadiusLimits)

  with result.ui.splashImage:
    shadowAlpha = shadowAlpha.limit(AlphaLimits)

  with result.level.backgroundHatch:
    width         = width.limit(HatchStrokeWidthLimits)
    spacingFactor = spacingFactor.limit(HatchSpacingLimits)

  with result.level.outline:
    widthFactor = widthFactor.limit(LevelOutlineWidthLimits)

  with result.level.shadow:
    innerWidthFactor = innerWidthFactor.limit(LevelShadowWidthLimits)
    outerWidthFactor = outerWidthFactor.limit(LevelShadowWidthLimits)


proc saveTheme*(theme: ThemeStyle, filename: string) =
  let config = writeTheme(theme)
  config.writeConfig(filename)


#[
proc convertTheme*(theme: ThemeStyle): ThemeStyle2 =
  var t = new ThemeStyle2

  t.ui = new UIStyle2

  #--------------------------------------------------------------------------
  t.ui.window = new UiWindowStyle2
  t.ui.window.backgroundColor = theme.general.backgroundColor
  t.ui.window.titleBackgroundColor = theme.window.backgroundColor
  t.ui.window.titleBackgroundInactiveColor = theme.window.bgColorUnfocused
  t.ui.window.titleColor = theme.window.textColor
  t.ui.window.titleInactiveColor = theme.window.textColorUnfocused
  t.ui.window.modifiedFlagColor = theme.window.modifiedFlagColor
  t.ui.window.buttonColor = theme.window.buttonColor
  t.ui.window.buttonHoverColor = theme.window.buttonColorHover
  t.ui.window.buttonDownColor = theme.window.buttonColorDown

  #--------------------------------------------------------------------------
  t.ui.dialog = new UiDialogStyle2
  t.ui.dialog.cornerRadius = theme.dialog.cornerRadius
  t.ui.dialog.titleBackgroundColor = theme.dialog.titleBarBgColor
  t.ui.dialog.titleColor = theme.dialog.titleBarTextColor
  t.ui.dialog.backgroundColor = theme.dialog.backgroundColor
  t.ui.dialog.labelColor = theme.dialog.textColor
  t.ui.dialog.warningColor = theme.dialog.warningTextColor
  t.ui.dialog.outerBorderColor = theme.dialog.outerBorderColor
  t.ui.dialog.outerBorderWidth = theme.dialog.outerBorderWidth
  t.ui.dialog.innerBorderColor = theme.dialog.innerBorderColor
  t.ui.dialog.innerBorderWidth = theme.dialog.innerBorderWidth
  t.ui.dialog.shadowEnabled = theme.dialog.shadow
  t.ui.dialog.shadowXOffset = theme.dialog.shadowXOffset
  t.ui.dialog.shadowYOffset = theme.dialog.shadowYOffset
  t.ui.dialog.shadowFeather = theme.dialog.shadowFeather
  t.ui.dialog.shadowColor = theme.dialog.shadowColor

  #--------------------------------------------------------------------------
  t.ui.widget = new UiWidgetStyle2
  t.ui.widget.cornerRadius = theme.general.cornerRadius
  t.ui.widget.backgroundColor = theme.widget.bgColor
  t.ui.widget.backgroundHoverColor = theme.widget.bgColorHover
  t.ui.widget.backgroundActiveColor = theme.general.highlightColor
  t.ui.widget.backgroundDisabledColor = theme.widget.bgColorDisabled
  t.ui.widget.foregroundColor = theme.widget.textColor
  t.ui.widget.foregroundActive = theme.widget.textColorActive
  t.ui.widget.foregroundDisabled = theme.widget.textColorDisabled

  #--------------------------------------------------------------------------
  t.ui.textField = new UiTextFieldStyle2
  t.ui.textField.editBackgroundColor = theme.textField.bgColorActive
  t.ui.textField.editTextColor = theme.textField.textColorActive
  t.ui.textField.cursorColor = theme.textField.cursorColor
  t.ui.textField.selectionColor = theme.textField.selectionColor
  t.ui.textField.scrollBarNormalColor = theme.textField.scrollBarColorNormal
  t.ui.textField.scrollBarEditColor = theme.textField.scrollBarColorEdit

  #--------------------------------------------------------------------------
  t.ui.statusBar = new UiStatusBarStyle2
  t.ui.statusBar.backgroundColor = theme.statusBar.backgroundColor
  t.ui.statusBar.textColor = theme.statusBar.textColor
  t.ui.statusBar.commandBackgroundColor = theme.statusBar.commandBgColor
  t.ui.statusBar.commandColor = theme.statusBar.commandColor
  t.ui.statusBar.coordinatesColor = theme.statusBar.coordsColor

  #--------------------------------------------------------------------------
  t.ui.aboutButton = new UiAboutButtonStyle2
  t.ui.aboutButton.labelColor = theme.aboutButton.color
  t.ui.aboutButton.labelHoverColor = theme.aboutButton.colorHover
  t.ui.aboutButton.labelDownColor = theme.aboutButton.colorActive

  #--------------------------------------------------------------------------
  t.ui.aboutDialog = new UiAboutDialogStyle2
  t.ui.aboutDialog.logoColor = theme.aboutDialog.logoColor

  #--------------------------------------------------------------------------
  t.ui.splashImage = new UiSplashImageStyle2
  t.ui.splashImage.logoColor = theme.splashImage.logoColor
  t.ui.splashImage.outlineColor = theme.splashImage.outlineColor
  t.ui.splashImage.shadowAlpha = theme.splashImage.shadowAlpha

  ############################################################################

  t.level = new LevelStyle2

  t.level.general = new LevelGeneralStyle2
  t.level.general.backgroundColor = theme.level.backgroundColor
  t.level.general.foregroundColor = theme.level.drawColor
  t.level.general.foregroundLightColor = theme.level.lightDrawColor
  t.level.general.lineWidth = theme.level.lineWidth
  t.level.general.coordinatesColor = theme.level.coordsColor
  t.level.general.coordinatesHighlightColor = theme.level.coordsHighlightColor
  t.level.general.cursorColor = theme.level.cursorColor
  t.level.general.cursorGuidesColor = theme.level.cursorGuideColor
  t.level.general.selectionColor = theme.level.selectionColor
  t.level.general.pastePreviewColor = theme.level.pastePreviewColor
  t.level.general.linkMarkerColor = theme.level.linkMarkerColor
  t.level.general.trailColor = theme.level.trailColor
  t.level.general.regionBorderColor = theme.level.regionBorderColor
  t.level.general.regionBorderEmptyColor = theme.level.regionBorderEmptyColor

  #--------------------------------------------------------------------------
  t.level.backgroundHatch = new LevelBackgroundHatchStyle2
  t.level.backgroundHatch.enabled = theme.level.bgHatch
  t.level.backgroundHatch.color = theme.level.bgHatchColor
  t.level.backgroundHatch.width = theme.level.bgHatchStrokeWidth
  t.level.backgroundHatch.spacingFactor = theme.level.bgHatchSpacingFactor
  t.level.backgroundHatch.backgroundGridStyle = theme.level.gridStyleBackground
  t.level.backgroundHatch.backgroundGridColor = theme.level.gridColorBackground
  t.level.backgroundHatch.floorGridStyle = theme.level.gridStyleFloor
  t.level.backgroundHatch.floorGridColor = theme.level.gridColorFloor

  #--------------------------------------------------------------------------
  t.level.outline = new LevelOutlineStyle2
  t.level.outline.style = theme.level.outlineStyle
  t.level.outline.fillStyle = theme.level.outlineFillStyle
  t.level.outline.color = theme.level.outlineColor
  t.level.outline.widthFactor = theme.level.outlineWidthFactor
  t.level.outline.overscanEnabled = theme.level.outlineOverscan

  #--------------------------------------------------------------------------
  t.level.shadow = new LevelShadowStyle2
  t.level.shadow.innerColor = theme.level.innerShadowColor
  t.level.shadow.innerWidthFactor = theme.level.innerShadowWidthFactor
  t.level.shadow.outerColor = theme.level.outerShadowColor
  t.level.shadow.outerWidthFactor = theme.level.outerShadowWidthFactor

  #--------------------------------------------------------------------------
  t.level.floorColor = new LevelFloorColorStyle2
  t.level.floorColor.transparentFloor = theme.level.transparentFloor

  for idx, c in theme.level.floorColor:
    t.level.floorColor.color[idx] = c

  #--------------------------------------------------------------------------
  t.level.note = new LevelNoteStyle2
  t.level.note.markerColor = theme.level.noteMarkerColor
  t.level.note.commentColor = theme.level.noteCommentColor

  for idx, c in theme.level.noteIndexBgColor:
    t.level.note.indexBackgroundColor[idx] = c

  t.level.note.indexColor = theme.level.noteIndexColor
  t.level.note.tooltipBackgroundColor = theme.level.noteTooltipBgColor
  t.level.note.tooltipColor = theme.level.noteTooltipTextColor

  #--------------------------------------------------------------------------
  t.level.label = new LevelLabelStyle2
  for idx, c in theme.level.labelColor:
    t.level.label.color[idx] = c

  #--------------------------------------------------------------------------
  t.level.levelDropDown = new LevelLevelDropDownStyle2
  t.level.levelDropDown.buttonColor = theme.leveldropDown.buttonColor
  t.level.levelDropDown.buttonHoverColor = theme.leveldropDown.buttonColorHover
  t.level.levelDropDown.buttonLabelColor = theme.leveldropDown.textColor
  t.level.levelDropDown.itemListBackgroundColor = theme.leveldropDown.itemListColor
  t.level.levelDropDown.itemColor = theme.leveldropDown.itemColor
  t.level.levelDropDown.itemHoverColor = theme.leveldropDown.itemColorHover

  ############################################################################

  t.pane = new PaneStyle2
  t.pane.notes = new PaneNotesStyle2
  t.pane.notes.textColor = theme.notesPane.textColor

  for idx, c in theme.notesPane.indexBgColor:
    t.pane.notes.indexBackgroundColor[idx] = c

  t.pane.notes.indexColor = theme.notesPane.indexColor
  t.pane.notes.scrollBarColor = theme.notesPane.scrollBarColor

  #--------------------------------------------------------------------------
  t.pane.toolbar = new PaneToolbarStyle2
  t.pane.toolbar.buttonColor = theme.toolbarPane.buttonBgColor
  t.pane.toolbar.buttonHoverColor = theme.toolbarPane.buttonBgColorHover

  result = t
]#
