import math
import options
import parsecfg
import strformat

import nanovg

import common
import cfghelper
import macros
import strutils
import with


proc `$`(c: Color): string =
  let
    r = round(c.r * 255).int
    g = round(c.g * 255).int
    b = round(c.b * 255).int
    a = round(c.a * 255).int

  fmt"rgba({r}, {g}, {b}, {a})"


proc sectionClassName(sectionName: string): string =
  sectionName.capitalizeAscii() & "Style"

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

proc makeSectionTypeDef(sectionName: string,
                        props: seq[(string, NimNode)]): NimNode =
  var recList = nnkRecList.newTree
  for (propName, propType) in props:
    recList.add(
      mkProperty(propName, propType)
    )

  result = mkRefObjectTypeDef(
    sectionClassName(sectionName),
    recList
  )


macro defineTheme(arg: untyped): untyped =
  arg.expectKind nnkStmtList

  var typeSection = nnkTypeSection.newTree
  var themeStyleRecList = nnkRecList.newTree
  var parseThemeBody = nnkStmtList.newTree
  var writeThemeBody = nnkStmtList.newTree

  for section in arg:
    section.expectKind nnkCall
    section.expectLen 2

    section[0].expectKind nnkIdent
    let sectionName = section[0].strVal

    let sectionNameSym = newIdentNode(sectionName)
    let styleClassName = newIdentNode(sectionClassName(sectionName))

    parseThemeBody.add quote do:
      result.`sectionNameSym` = new `styleClassName`

    var propsToAdd = newSeq[(string, NimNode)]()

    let propsList = section[1]
    for prop in propsList:
      prop[0].expectKind nnkIdent
      let propName = prop[0].strVal

      let propParamsStmt = prop[1]

      var propType: NimNode
      case propParamsStmt[0].kind:
      of nnkIdent:   # no default provided
        propType = propParamsStmt[0]
        propsToAdd.add((propName, propType))

      of nnkBracketExpr:   # no default provided
        propType = propParamsStmt[0]
        assert propType[0] == newIdentNode("array")
        assert propType[2] == newIdentNode("Color")

        propsToAdd.add((propName, propType))

      of nnkInfix:   # default provided
        let propParams = propParamsStmt[0]
        propParams.expectLen 3

        assert propParams[0] == newIdentNode("|")
        propType = propParams[1]
        # TODO
#        let propDefaultValue = propParams[2]

        propsToAdd.add((propName, propType))

      else:
        error("Invalid property definition: " & $propParamsStmt[0].kind)

      # Append loader statement
      let propNameSym = newIdentNode(propName)

      if propType.kind == nnkIdent:
        case propType.strVal
        of "string", "bool", "Color", "float":
          let getter = newIdentNode("get" & propType.strVal.capitalizeAscii())
          parseThemeBody.add quote do:
            config.`getter`(`sectionName`, `propName`, result.`sectionNameSym`.`propNameSym`)

          writeThemeBody.add quote do:
            result.setSectionKey(`sectionName`, `propName`, $theme.`sectionNameSym`.`propNameSym`)

        else: # enum
          parseThemeBody.add quote do:
            getEnum[`propType`](config, `sectionName`, `propName`, result.`sectionNameSym`.`propNameSym`)

          writeThemeBody.add quote do:
            result.setSectionKey(`sectionName`, `propName`, $theme.`sectionNameSym`.`propNameSym`)

      elif propType.kind == nnkBracketExpr:
        let propType = propParamsStmt[0]
        assert propType[0] == newIdentNode("array")
        assert propType[2] == newIdentNode("Color")
        let numColors = propType[1].intVal

        for i in 1..numColors:
          let propNameN = propName & $i
          let index = newIntLitNode(i-1)
          let theme = newIdentNode("theme")
          parseThemeBody.add quote do:
            config.getColor(`sectionName`, `propNameN`, result.`sectionNameSym`.`propNameSym`[`index`])

          writeThemeBody.add quote do:
            result.setSectionKey(`sectionName`, `propNameN`, $`theme`.`sectionNameSym`.`propNameSym`[`index`])

    typeSection.add(
      makeSectionTypeDef(sectionName, propsToAdd)
    )

    themeStyleRecList.add(
      mkProperty(sectioNName, newIdentNode(sectionClassName(sectionName)))
    )

  typeSection.add(
    mkRefObjectTypeDef("ThemeStyle", themeStyleRecList)
  )

  let config = newIdentNode("config")
  let theme = newIdentNode("theme")

  quote do:
    `typeSection`

    proc parseTheme(`config`: Config): ThemeStyle =
      result = new ThemeStyle
      `parseThemeBody`

    proc writeTheme(`theme`: ThemeStyle): Config =
      result = newConfig()
      `writeThemeBody`


include themedef


const
  WidgetCornerRadiusLimits*  = (min:   0.0, max: 12.0)

  DialogCornerRadiusLimits*  = (min:   0.0, max: 20.0)
  DialogBorderWidthLimits*   = (min:   0.0, max: 30.0)
  DialogShadowOffsetLimits*  = (min: -10.0, max: 10.0)
  DialogShadowFeatherLimits* = (min:   0.0, max: 50.0)

  AlphaLimits*               = (min:   0.0, max: 1.0)

  HatchStrokeWidthLimits*    = (min:   0.5, max: 10.0)
  HatchSpacingLimits*        = (min:   1.0, max: 10.0)

  LevelOutlineWidthLimits*   = (min:   0.0, max: 1.0)
  LevelShadowWidthLimits*    = (min:   0.0, max: 1.0)


proc limit(v: var float, limits: tuple[min: float, max: float]) =
  v = v.clamp(limits.min, limits.max)


proc loadTheme*(filename: string): ThemeStyle =
  var cfg = loadConfig(filename)
  result = parseTheme(cfg)

  with result.general:
    limit(cornerRadius, WidgetCornerRadiusLimits)

  with result.dialog:
    limit(cornerRadius, DialogCornerRadiusLimits)
    limit(outerBorderWidth, DialogBorderWidthLimits)
    limit(innerBorderWidth, DialogBorderWidthLimits)
    limit(shadowXOffset, DialogShadowOffsetLimits)
    limit(shadowYOffset, DialogShadowOffsetLimits)
    limit(shadowFeather, DialogShadowFeatherLimits)

  with result.splashImage:
    limit(shadowAlpha, AlphaLimits)

  with result.level:
    limit(bgHatchStrokeWidth, HatchStrokeWidthLimits)
    limit(bgHatchSpacingFactor, HatchSpacingLimits)
    limit(outlineWidthFactor, LevelOutlineWidthLimits)
    limit(innerShadowWidthFactor, LevelShadowWidthLimits)
    limit(outerShadowWidthFactor, LevelShadowWidthLimits)

proc saveTheme*(theme: ThemeStyle, filename: string) =

  let config = writeTheme(theme)
  config.writeConfig(filename)

