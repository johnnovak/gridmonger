import options
import parsecfg

import nanovg

import common
import cfghelper
import macros
import strutils
import with


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
        let propDefaultValue = propParams[2]

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

        else: # enum
          parseThemeBody.add quote do:
            getEnum[`propType`](config, `sectionName`, `propName`, result.`sectionNameSym`.`propNameSym`)

      elif propType.kind == nnkBracketExpr:
        let propType = propParamsStmt[0]
        assert propType[0] == newIdentNode("array")
        assert propType[2] == newIdentNode("Color")
        let numColors = propType[1].intVal

        for i in 1..numColors:
          let propNameN = propName & $i
          let index = newIntLitNode(i-1)
          parseThemeBody.add quote do:
            config.getColor(`sectionName`, `propNameN`, result.`sectionNameSym`.`propNameSym`[`index`])

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

  quote do:
    `typeSection`

    proc parseTheme(`config`: Config): ThemeStyle =
      result = new ThemeStyle
      `parseThemeBody`


include themedef

const
  HatchStrokeWidthMin = 0.5
  HatchStrokeWidthMax = 10.0

  HatchSpacingMin = 1.0
  HatchSpacingMax = 10.0

  OutlineWidthMin = 0.0
  OutlineWidthMax = 1.0

  InnerShadowWidthMin = 0.0
  InnerShadowWidthMax = 1.0

  OuterShadowWidthMin = 0.0
  OuterShadowWidthMax = 1.0


proc loadTheme*(filename: string): ThemeStyle =
  var cfg = loadConfig(filename)
  result = parseTheme(cfg)

  with result.level:
    bgHatchStrokeWidth = bgHatchStrokeWidth.clamp(HatchStrokeWidthMin,
                                                  HatchStrokeWidthMax)

    bgHatchSpacingFactor = bgHatchSpacingFactor.clamp(HatchSpacingMin,
                                                      HatchSpacingMax)

    outlineWidthFactor = outlineWidthFactor.clamp(OutlineWidthMin,
                                                  OutlineWidthMax)

    innerShadowWidthFactor = innerShadowWidthFactor.clamp(InnerShadowWidthMin,
                                                          InnerShadowWidthMax)

    outerShadowWidthFactor = outerShadowWidthFactor.clamp(OuterShadowWidthMin,
                                                          OuterShadowWidthMax)

