import math
import options
import parsecfg
import strformat

import nanovg

import common
import cfghelper
import fieldlimits
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


proc styleClassName(name: string): string =
  name.capitalizeAscii() & "Style2"

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


macro defineTheme2(arg: untyped): untyped =
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
    let styleClassName = newIdentNode(styleClassName(sectionName))

    parseThemeBody.add quote do:
      result.`sectionNameSym` = new `styleClassName`

    section[1].expectKind nnkStmtList

    var sectionPropsToAdd = newSeq[(string, NimNode)]()

    # Sub-sections
    for subsection in section[1]:
      subsection.expectKind nnkCall
      subsection.expectLen 2

      subsection[0].expectKind nnkIdent
      let subsectionName = subsection[0].strVal

      let subsectionNameSym = newIdentNode(subsectionName)
      let propsList = subsection[1]

      var propsToAdd = newSeq[(string, NimNode)]()

      let configSectionName = sectionName & "." & subsectionName

      # Properties
      for prop in propsList:
        prop[0].expectKind nnkIdent
        let propName = prop[0].strVal

        let propParamsStmt = prop[1]

        var propType: NimNode
        case propParamsStmt[0].kind:
        of nnkIdent:  # no default provided
          propType = propParamsStmt[0]
          propsToAdd.add((propName, propType))

        of nnkBracketExpr:  # no default provided
          propType = propParamsStmt[0]
          assert propType[0] == newIdentNode("array")
          assert propType[2] == newIdentNode("Color")

          propsToAdd.add((propName, propType))

        of nnkInfix:  # default provided
          let propParams = propParamsStmt[0]
          propParams.expectLen 3

          assert propParams[0] == newIdentNode("|")
          propType = propParams[1]

          propsToAdd.add((propName, propType))

        else:
          error("Invalid property definition: " & $propParamsStmt[0].kind)

        # Append loader statement
        let propNameSym = newIdentNode(propName)

        let toProp = quote do:
          result.`sectionNameSym`.`subsectionNameSym`.`propNameSym`

        let fromProp = quote do:
          theme.`sectionNameSym`.`subsectionNameSym`.`propNameSym`

        if propType.kind == nnkIdent:
          case propType.strVal
          of "string", "bool", "Color", "float":
            let getter = newIdentNode("get" & propType.strVal.capitalizeAscii())

            parseThemeBody.add quote do:
              config.`getter`(`configSectionName`, `propName`, `toProp`)

            writeThemeBody.add quote do:
              result.setSectionKey(`configSectionName`, `propName`,
                                   $`fromProp`)

          else:  # enum
            parseThemeBody.add quote do:
              getEnum[`propType`](config, `configSectionName`, `propName`,
                                  `toProp`)

            writeThemeBody.add quote do:
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
            parseThemeBody.add quote do:
              config.getColor(`configSectionName`, `propNameN`,
                              `toProp`[`index`])

            writeThemeBody.add quote do:
              result.setSectionKey(
                `configSectionName`, `propNameN`,
                 $`fromProp`[`index`]
               )

      typeSection.add(
        makeStyleTypeDef(subsectionName, propsToAdd)
      )

      let sectionPropType: NimNode = newIdentNode(styleClassName(subsectionName))
      sectionPropsToAdd.add((subsectionName, sectionPropType))

    typeSection.add(
      makeStyleTypeDef(sectionName, sectionPropsToAdd)
    )

    themeStyleRecList.add(
      mkProperty(sectionName, newIdentNode(styleClassName(sectionName)))
    )

  typeSection.add(
    mkRefObjectTypeDef("ThemeStyle2", themeStyleRecList)
  )

  let config = newIdentNode("config")
  let theme = newIdentNode("theme")

  result = quote do:
    `typeSection`

    proc parseTheme(`config`: Config): ThemeStyle2 =
      result = new ThemeStyle2
      `parseThemeBody`

    proc writeTheme(`theme`: ThemeStyle2): Config =
      result = newConfig()
      `writeThemeBody`

  echo result.repr


include themedef2


#[
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

  with result.general:
    cornerRadius = cornerRadius.limit(WidgetCornerRadiusLimits)

  with result.dialog:
    cornerRadius = cornerRadius.limit(DialogCornerRadiusLimits)
    outerBorderWidth = outerBorderWidth.limit(DialogBorderWidthLimits)
    innerBorderWidth = innerBorderWidth.limit(DialogBorderWidthLimits)
    shadowXOffset = shadowXOffset.limit(DialogShadowOffsetLimits)
    shadowYOffset = shadowYOffset.limit(DialogShadowOffsetLimits)
    shadowFeather = shadowFeather.limit(DialogShadowFeatherLimits)

  with result.splashImage:
    shadowAlpha = shadowAlpha.limit(AlphaLimits)

  with result.level:
    bgHatchStrokeWidth = bgHatchStrokeWidth.limit(HatchStrokeWidthLimits)
    bgHatchSpacingFactor = bgHatchSpacingFactor.limit(HatchSpacingLimits)
    outlineWidthFactor = outlineWidthFactor.limit(LevelOutlineWidthLimits)

    innerShadowWidthFactor =
      innerShadowWidthFactor.limit(LevelShadowWidthLimits)

    outerShadowWidthFactor =
      outerShadowWidthFactor.limit(LevelShadowWidthLimits)

]#

#proc saveTheme*(theme: ThemeStyle2, filename: string) =
#  let config = writeTheme(theme)
#  config.writeConfig(filename)

