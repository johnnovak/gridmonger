macro prop(label: static[string], path: untyped): untyped =

  proc getRefObjType(sym: NimNode): NimNode =
    sym.getTypeImpl[0].getTypeImpl

  proc findProp(objType: NimNode, name: string): NimNode =
    let recList = objType[2]
    for identDef in recList:
      let propName = identDef[0].strVal
      if propName == name:
        let propType = identDef[1]
        return propType
    error("Cannot find property: " & name)

  let
    pathStr = path.repr
    pathArr = pathStr.split(".")
    sectionName = pathArr[0]
    subsectionName = pathArr[1]
    propNameWithIndex = pathArr[2]

  let
    p = propNameWithIndex.find('[')
    propName = if p > -1: propNameWithIndex.substr(0, p-1)
               else: propNameWithIndex

  let
    rootObjType = getRefObjType(ThemeStyle.getTypeInst)
    sectionObjType = findProp(rootObjType, sectionName).getRefObjType
    subsectionObjType = findProp(sectionObjType, subsectionName).getRefObjType
    propType = findProp(subsectionObjType, propName)

  let fullPath = parseExpr("ts." & pathStr)

  result = nnkStmtList.newTree
  result.add quote do:
    koi.label(`label`)
    koi.setNextId(`pathStr`)

  if propType == Color.getTypeInst or
     # a bit hacky; all arrays are of type Color
     propType.getTypeImpl.kind == nnkBracketExpr:
    result.add quote do:
      koi.color(`fullPath`)

  elif propType == float.getTypeInst:
    let limitSym = newIdentNode(
      sectionName.capitalizeAscii() &
      subsectionName.capitalizeAscii() &
      propName.capitalizeAscii() &
      "Limits"
    )

    result.add quote do:
      # TODO limits
      koi.horizSlider(startVal=`limitSym`.minFloat,
                      endVal=`limitSym`.maxFloat,
                      `fullPath`,
                      style=ThemeEditorSliderStyle)

  elif propType == bool.getTypeInst:
    result.add quote do:
      koi.checkBox(`fullPath`)

  elif propType.getTypeImpl.kind == nnkEnumTy:
    result.add quote do:
      koi.dropDown(`fullPath`)

  else:
    echo propType.treeRepr
    error("Unknown type: " & propType.strVal)

#    echo result.repr

  let prevFullPath = parseExpr("te.prevState." & pathStr)

  result.add quote do:
    if `prevFullPath` != `fullPath`:
      te.modified = true

