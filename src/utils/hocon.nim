import std/deques
import std/math
import std/options
import std/streams
import std/strformat
import std/strutils
import std/tables
import std/unicode

# {{{ UnicodeScanner

type
  UnicodeScanner = object
    stream:  Stream
    readBuf: string
    peekBuf: Deque[Rune]
    line, column: Natural

using s: var UnicodeScanner

proc initUnicodeScanner(stream: Stream): UnicodeScanner =
  if stream == nil:
    raise newException(IOError, "Stream is not initialised")

  result.stream = stream
  result.readBuf = newStringOfCap(4)
  result.readBuf.setLen(4)
  result.peekBuf = initDeque[Rune]()


proc readNextRune(s): Rune =
  proc raiseEOFError() =
    raise newException(IOError, "Unexpected end of file")

  if s.stream.atEnd: raiseEOFError()
  s.readBuf[0] = cast[char](s.stream.readUint8)

  let
    runeLen = s.readBuf.runeLenAt(0)
    bytesRead = s.stream.readDataStr(s.readBuf, 1..(1 + runeLen-2))

  if bytesRead + 1 != runeLen:
    raiseEOFError()

  s.readBuf.runeAt(0)


proc peekRune(s; lookahead: Natural = 1): Rune =
  assert lookahead >= 1
  while lookahead > s.peekBuf.len:
    s.peekBuf.addLast(s.readNextRune)
  s.peekBuf[lookahead-1]

proc eatRune(s): Rune =
  if s.peekBuf.len > 0: s.peekBuf.popFirst
  else: s.readNextRune

proc atEnd(s): bool =
  s.stream.atEnd

proc close(s) =
  if s.stream != nil:
    s.stream.close
    s.stream = nil

# }}}
# {{{ Tokeniser

type
  TokenKind = enum
    tkLeftBrace    = "left brace ('{')"
    tkRightBrace   = "right brace ('}')"
    tkLeftBracket  = "left bracket ('[')"
    tkRightBracket = "right bracket (']')"
    tkComma        = "comma (',')"
    tkNewline      = "newline"
    # TODO tkWhitespa
    tkColon        = "colon (':')"
    tkEquals       = "equals sign ('=')"
    tkString       = "string"
    tkNumber       = "number"
    tkTrue         = "true"
    tkFalse        = "false"
    tkNull         = "null"

  Token = object
    case  kind:     TokenKind
    of    tkString: str: string
    of    tkNumber: num: string
    else: discard
    line, column:   Natural

  Tokeniser = object
    scanner:      UnicodeScanner
    line, column: Natural
    peekBuf:      Deque[Token]

  HoconTokeniserError* = object of IOError


const validQuotedStringRuneRange = 0x0020..0x10fff

const whitespaceRunes = @[
  Rune(0x0020), Rune(0x00a0), Rune(0x1680), Rune(0x2000),
  Rune(0x2001), Rune(0x2002), Rune(0x2003), Rune(0x2004),
  Rune(0x2005), Rune(0x2006), Rune(0x2007), Rune(0x2008),
  Rune(0x2009), Rune(0x200a), Rune(0x202f), Rune(0x205f),
  Rune(0x3000), # space separators (Zs) (incl. non-breaking spaces)

  Rune(0xfeff), # byte-order-marker (BOM)
  Rune(0x2028), # line separators (Zl)
  Rune(0x2029), # paragraph separators (Zp)
  Rune('\t'),   # tab
  Rune(0x000b), # vertical tab
  Rune('\f'),   # form feed
  Rune('\r'),   # carriage return
  Rune(0x001c), # file separator
  Rune(0x001d), # group separator
  Rune(0x001e), # record separator
  Rune(0x001f)  # unit separator
]

const forbiddenRunes = @[
  Rune('$'), Rune('"'), Rune('{'), Rune('}'), Rune('['), Rune(']'), Rune(':'),
  Rune('='), Rune(','), Rune('+'), Rune('#'), Rune('`'), Rune('^'), Rune('?'),
  Rune('!'), Rune('@'), Rune('*'), Rune('&'), Rune('\\')
]


using t: var Tokeniser

proc initTokeniser(stream: Stream): Tokeniser =
  result.scanner = initUnicodeScanner(stream)
  result.line = 1
  result.column = 0
  result.peekBuf = initDeque[Token]()


proc raiseTokeniserError(t; msg, details: string,
                         line = t.line, column = t.column) {.noReturn.} =
  t.scanner.close
  raise newException(HoconTokeniserError,
    fmt"{msg} at line {line}, column {column}: {details}"
  )

proc peekRune(t; lookahead: Natural = 1): Rune =
  t.scanner.peekRune(lookahead)

proc eatRune(t): Rune =
  inc(t.column)
  t.scanner.eatRune

proc readEscape(t; line, col: Natural): Rune =
  let rune = t.eatRune
  case rune
  of Rune('"'):  Rune('"')
  of Rune('\\'): Rune('\\')
  of Rune('/'):  Rune('/')
  of Rune('b'):  Rune('\b')
  of Rune('f'):  Rune('\f')
  of Rune('n'):  Rune('\n')
  of Rune('r'):  Rune('\r')
  of Rune('t'):  Rune('\t')
  of Rune('u'):
    let hexStr = $t.eatRune & $t.eatRune & $t.eatRune & $t.eatRune
    try:
      Rune(fromHex[int32](hexStr))
    except ValueError:
      t.raiseTokeniserError(
        msg = "Invalid Unicode escape sequence", details = fmt"\u{hexStr}",
        line = line, column = col
      )
  else:
    t.raiseTokeniserError(
      msg = "Invalid escape sequence", details = fmt"\{rune} (\u{rune.ord:04x})",
      line = line, column = col
    )

proc readQuotedString(t): Token =
  var str = ""

  discard t.eatRune
  let line = t.line
  let col = t.column

  var rune = t.eatRune

  while rune != Rune('"'):
    if rune.ord notin validQuotedStringRuneRange:
      t.raiseTokeniserError(
        msg = "Invalid quoted string character",
        details = fmt"{rune} (\u{rune.ord:04x})" # TODO
      )
    elif rune == Rune('\\'):
      str &= t.readEscape(t.line, t.column)
    else:
      str &= rune

    rune = t.eatRune

  Token(kind: tkString, str: str, line: line, column: col)


proc readUnquotedStringOrBooleanOrNull(t): Token =
  var str = ""
  var rune = t.eatRune
  let line = t.line
  let col = t.column

  while true:
    str &= rune
    rune = t.peekRune
    if rune == Rune('\n') or
       rune in whitespaceRunes or
       rune in forbiddenRunes: break
    else:
      rune = t.eatRune

  case str
  of "true", "yes", "on":
    return Token(kind: tkTrue,  line: line, column: col)
  of "false", "no",  "off":
    return Token(kind: tkFalse, line: line, column: col)
  of "null":
    return Token(kind: tkNull,  line: line, column: col)
  else:
    Token(kind: tkString, str: str, line: line, column: col)


proc readNumberOrString(t): Token =
  var str = ""
  var rune = t.eatRune
  let line = t.line
  let col = t.column

  while true:
    str &= rune
    rune = t.peekRune
    if rune == Rune('\n') or
       rune in whitespaceRunes or
       rune in forbiddenRunes: break
    else:
      rune = t.eatRune

  try:
    discard parseFloat(str)
    Token(kind: tkNumber, num: str, line: line, column: col)
  except ValueError:
    Token(kind: tkString, str: str, line: line, column: col)


proc skipComment(t) =
  while true:
    let rune = t.peekRune
    if rune == Rune('\n'): return
    discard t.eatRune


proc readNextToken(t): Token =

  proc mkSimpleToken(t; kind: TokenKind): Token =
    discard t.eatRune
    Token(kind: kind, line: t.line, column: t.column)

  var rune = t.peekRune
  while rune in whitespaceRunes:
    discard t.eatRune
    rune = t.peekRune

  case rune
  of Rune('{'): t.mkSimpleToken(tkLeftBrace)
  of Rune('}'): t.mkSimpleToken(tkRightBrace)
  of Rune('['): t.mkSimpleToken(tkLeftBracket)
  of Rune(']'): t.mkSimpleToken(tkRightBracket)
  of Rune(','): t.mkSimpleToken(tkComma)
  of Rune(':'): t.mkSimpleToken(tkColon)
  of Rune('='): t.mkSimpleToken(tkEquals)

  of Rune('\n'):
    let token = t.mkSimpleToken(tkNewLine)
    inc(t.line)
    t.column = 0
    token

  of Rune('0')..Rune('9'), Rune('-'), Rune('.'):
    t.readNumberOrString

  of Rune('"'):
    t.readQuotedString

  of Rune('#'):
    t.skipComment
    t.readNextToken

  of Rune('/'):
    if t.peekRune(2) == Rune('/'):
      t.skipComment
      t.readNextToken
    else:
      t.readUnquotedStringOrBooleanOrNull

  else:
    t.readUnquotedStringOrBooleanOrNull


proc peekToken(t; lookahead: Natural = 1): Token =
  assert lookahead >= 1
  while lookahead > t.peekBuf.len:
    t.peekBuf.addLast(t.readNextToken)
  t.peekBuf[lookahead-1]

proc eatToken(t): Token =
  if t.peekBuf.len > 0: t.peekBuf.popFirst
  else: t.readNextToken

proc atEnd(t): bool =
  t.scanner.atEnd

proc close(t) =
  t.scanner.close

# }}}
# {{{ HoconParser

type
  HoconParser* = object
    tokeniser: Tokeniser

  HoconParseError* = object of IOError

  HoconNodeKind* = enum
    hnkNull   = "null"
    hnkString = "string"
    hnkNumber = "number"
    hnkBool   = "bool"
    hnkObject = "object"
    hnkArray  = "array"

  HoconNode* = ref HoconNodeObj

  HoconNodeObj* = object
    case kind*: HoconNodeKind
    of hnkNull:   discard
    of hnkString: str*:    string
    of hnkNumber: num*:    float64
    of hnkBool:   bool*:   bool
    of hnkObject: fields*: OrderedTable[string, HoconNode]
    of hnkArray:  elems*:  seq[HoconNode]


proc `==`*(a, b: HoconNode): bool =
  if cast[int](a) == 0: return cast[int](b) == 0  # HACK
  if a.kind != b.kind: return false
  case a.kind
  of hnkNull:   true
  of hnkString: a.str == b.str
  of hnkNumber: a.num == b.num
  of hnkBool:   a.bool == b.bool

  of hnkObject:
    if a.fields.len != b.fields.len: return false
    for k,v in a.fields:
      if not b.fields.hasKey(k): return false
      if v != b.fields[k]: return false
    true

  of hnkArray:
    if a.elems.len != b.elems.len: return false
    for i,v in a.elems:
      if v != b.elems[i]: return false
    true


proc `$`*(n: HoconNode): string =
  case n.kind
  of hnkNull:   "Null"
  of hnkString: fmt"Str({n.str})"
  of hnkNumber: fmt"Num({n.num})"
  of hnkBool:   fmt"Bool({n.bool})"
  of hnkObject:
    var s = "{"
    for k,v in n.fields:
      s &= "\"" & k & "\": " & $v & ", " #TODO
    s &= "}"
    s
  of hnkArray:
    var s = "["
    for e in n.elems:
      s &= fmt"{e}, " #TODO
    s &= "]"
    s


using p: var HoconParser

proc initHoconParser*(stream: Stream): HoconParser =
  result.tokeniser = initTokeniser(stream)

proc raiseUnexpectedTokenError(p; token: Token) {.noReturn.} =
  p.tokeniser.close
  raise newException(HoconParseError, fmt"Unexpected token: {token}")

proc peekToken(p): Token = p.tokeniser.peekToken
proc eatToken(p):  Token = p.tokeniser.eatToken


proc eatEither(p; kinds: varargs[TokenKind]): Token =
  let token = p.tokeniser.eatToken
  if token.kind notin kinds:
    p.raiseUnexpectedTokenError(token)
  else: token

proc eatNewLines(p): bool =
  if p.tokeniser.atEnd: return
  var token = p.peekToken
  while token.kind == tkNewLine:
    result = true
    discard p.eatToken
    if p.tokeniser.atEnd: return
    token = p.peekToken

proc eatNewLinesOrSingleComma(p): bool =
  var newlinesRead = p.eatNewLines
  if p.tokeniser.atEnd: return
  if p.peekToken.kind == tkComma:
    discard p.eatToken
    true
  else: newLinesRead

proc parseObject(p; allowImplicitBraces: bool = false): HoconNode
proc parseArray(p): HoconNode

proc parseNode(p): HoconNode =
  let token = p.peekToken
  case token.kind:
  of tkString:
    discard p.eatToken
    HoconNode(kind: hnkString, str: token.str)

  of tkNumber:
    discard p.eatToken
    HoconNode(kind: hnkNumber, num: parseFloat(token.num))

  of tkTrue:
    discard p.eatToken
    HoconNode(kind: hnkBool, bool: true)

  of tkFalse:
    discard p.eatToken
    HoconNode(kind: hnkBool, bool: false)

  of tkNull:
    discard p.eatToken
    HoconNode(kind: hnkNull)

  of tkLeftBrace:   p.parseObject
  of tkLeftBracket: p.parseArray
  else:
    p.raiseUnexpectedTokenError(token)


proc parseObject(p; allowImplicitBraces: bool = false): HoconNode =
  var implicitBraces = false
  var skipFirstPeek = false

  var token = p.peekToken
  if token.kind == tkLeftBrace:
    discard p.eatToken
    discard p.eatNewLines
  else:
    if allowImplicitBraces:
      implicitBraces = true
      if token.kind == tkNewLine:
        discard p.eatToken
        discard p.eatNewLines
      else:
        skipFirstPeek = true
    else:
      p.raiseUnexpectedTokenError(token)

  result = HoconNode(kind: hnkObject)

  var sepa = true
  while true:
    if implicitBraces and p.tokeniser.atEnd:
      break

    if not skipFirstPeek:
      token = p.peekToken
    skipFirstPeek = false

    case token.kind
    of tkRightBrace:
      if implicitBraces:
        p.raiseUnexpectedTokenError(token)
      else:
        discard p.eatToken
        break

    of tkString:
      if not sepa:
        p.raiseUnexpectedTokenError(token)
      let key = p.eatToken.str
      discard p.eatNewLines

      let node = if p.peekToken.kind == tkLeftBrace:
        p.parseObject
      else:
        discard p.eatEither(tkColon, tkEquals)
        discard p.eatNewLines
        p.parseNode

      result.fields[key] = node
      sepa = p.eatNewLinesOrSingleComma

    else:
      p.raiseUnexpectedTokenError(token)


proc parseArray(p): HoconNode =
  discard p.eatEither(tkLeftBracket)
  discard p.eatNewLines

  result = HoconNode(kind: hnkArray)

  var sepa = true
  while true:
    let token = p.peekToken
    case token.kind
    of tkRightBracket:
      discard p.eatToken
      break
    else:
      if not sepa:
        p.raiseUnexpectedTokenError(token)
      discard p.eatNewLines

      let node = if p.peekToken.kind == tkLeftBrace:
        p.parseObject
      else:
        p.parseNode

      result.elems.add(node)
      sepa = p.eatNewLinesOrSingleComma


proc parse*(p): HoconNode =
  discard p.eatNewLines

  let token = p.peekToken
  result = if token.kind == tkLeftBracket:
    p.parseArray
  else:
    p.parseObject(allowImplicitBraces=true)

  p.tokeniser.close

# }}}

# {{{ Writer

type WrittenType = enum
  wtObjectOpen, wtObjectClose, wtFieldName, wtSimpleField, wtOther


proc write*(node: HoconNode, stream: Stream,
            indentSize: Natural = 2,
            writeRootObjectBraces: bool = false,
            newlineAfterSimpleFields: bool = true,
            newlinesAroundObjects: bool = true,
            newlinesAroundObjectsMaxDepth: Natural = 1,
            yesNoBool: bool = true) =

  proc go(curr: HoconNode, parent: HoconNode, depth, indent: int,
          prevType: WrittenType): WrittenType =

    var prevType = prevType

    case curr.kind
    of hnkArray:
      if prevType == wtFieldName: stream.write(" = ")

      if curr.elems.len <= 4:
        stream.write("[")
        for idx, val in curr.elems:
          prevType = go(val, curr, depth+1, indent+1, wtOther)
          if idx < curr.elems.high:
            stream.write(", ")
      else:
        stream.write("[\n")
        for val in curr.elems:
          stream.write(" ".repeat((indent+1) * indentSize))
          prevType = go(val, curr, depth+1, indent+1, wtOther)
          stream.write("\n")
        stream.write(" ".repeat((indent) * indentSize))

      stream.write("]")

    of hnkObject:
      let writeBraces = depth > 0 or (depth == 0 and writeRootObjectBraces)
      if writeBraces:
        if depth > 0 and prevType == wtFieldName: stream.write(" ")
        stream.write("{\n")

      if newlinesAroundObjects:
        prevType = wtObjectOpen

      for key, val in curr.fields:
        if val.kind == hnkObject:
          if (newlinesAroundObjects and
             prevType == wtObjectClose and
             depth <= newlinesAroundObjectsMaxDepth) or
             (newlineAfterSimpleFields and prevType == wtSimpleField):
            stream.write("\n")

        if val.kind notin {hnkObject} and prevType == wtObjectClose:
          stream.write("\n")

        stream.write(" ".repeat((indent+1) * indentSize) & key)
        prevType = go(val, curr, depth+1, indent+1, wtFieldName)
        stream.write("\n")

        if val.kind notin {hnkObject}:
          prevType = wtSimpleField

      if writeBraces:
        stream.write(" ".repeat((indent) * indentSize))
        stream.write("}")
        prevType = wtObjectClose

    of hnkNull:
      if (parent.kind != hnkArray): stream.write(" = ")
      stream.write("null")

    of hnkString:
      if (parent.kind != hnkArray): stream.write(" = ")

      var escape = curr.str == ""
      for r in curr.str.runes:
        if r in whitespaceRunes or r in forbiddenRunes:
          escape = true
          break

      if escape: stream.write(curr.str.escape)
      else:      stream.write(curr.str)

    of hnkNumber:
      if (parent.kind != hnkArray): stream.write(" = ")
      let (i, f) = splitDecimal(curr.num)
      if f == 0.0:
        stream.write($i.int)
      else:
        stream.write($curr.num)

    of hnkBool:
      if (parent.kind != hnkArray): stream.write(" = ")
      if yesNoBool:
        let val = if curr.bool: "yes" else: "no"
        stream.write(val)
      else:
        stream.write($curr.bool)

    return prevType

  let startIndent = if writeRootObjectBraces: 0 else: -1
  discard go(node, nil, depth=0, indent=startIndent, prevType=wtOther)
  stream.write("\n")

# }}}
# {{{ Helpers

type
  HoconPathError*  = object of KeyError
  HoconValueError* = object of ValueError

proc newHoconObject*: HoconNode = HoconNode(kind: hnkObject)
proc newHoconArray*:  HoconNode = HoconNode(kind: hnkArray)

proc raiseHoconPathError*(path, message: string) {.noReturn.} =
  raise newException(HoconPathError,
                     fmt"Invalid object path: {path}, {message}")


proc raiseHoconValueError*(src, target: HoconNodeKind,
                           path: string) {.noReturn.} =
  raise newException(HoconValueError,
                     fmt"Cannot read {src} as {target}, path: {path}")

proc isEmpty*(node: HoconNode): bool =
  case node.kind
  of hnkObject: node.fields.len == 0
  of hnkArray: node.elems.len == 0
  else:
    raise newException(HoconValueError, fmt"Not an object or array")

proc hasOnlyDigits(s: string): bool =
  for c in s:
    if not c.isDigit: return false
  true

template hoconNode*[T: SomeNumber](val: T): HoconNode =
  HoconNode(kind: hnkNumber, num: val.float)

template hoconNode*(val: string): HoconNode =
  HoconNode(kind: hnkString, str: val)

template hoconNode*(val: bool): HoconNode =
  HoconNode(kind: hnkBool, bool: val)

proc hoconNode*[T: SomeNumber | string | bool](s: seq[T]): HoconNode =
  result = newHoconArray()
  for v in s:
    result.elems.add(hoconNode(v))

proc hoconNode*(s: seq[HoconNode]): HoconNode =
  result = newHoconArray()
  for v in s:
    result.elems.add(v)

template hoconNodeNull*: HoconNode =
  HoconNode(kind: hnkNull)

# {{{ Getters

proc get*(node: HoconNode, path: string): HoconNode =
  var curr = node
  for key in path.split('.'):
    if key.hasOnlyDigits:
      let idx = parseInt(key)
      if curr.kind != hnkArray:
        raiseHoconPathError(path, fmt"'{key}' is not an array")

      if not (idx >= 0 and idx <= curr.elems.high):
        raiseHoconPathError(path, fmt"invalid array index: {idx}")

      curr = curr.elems[idx]

    else:
      if curr.kind != hnkObject:
        raiseHoconPathError(path, fmt"'{key}' is not an object")

      if not curr.fields.hasKey(key):
        raiseHoconPathError(path, fmt"key '{key}' not found")

      curr = curr.fields[key]

  result = curr


proc getOpt*(node: HoconNode, path: string): Option[HoconNode] =
  var curr = node
  for key in path.split('.'):
    if key.hasOnlyDigits:
      let idx = parseInt(key)
      if curr.kind != hnkArray:
        return
      if not (idx >= 0 and idx <= curr.elems.high):
        return
      curr = curr.elems[idx]

    else:
      if curr.kind != hnkObject:
        return
      if not curr.fields.hasKey(key):
        return
      curr = curr.fields[key]

  result = curr.some


proc getString*(node: HoconNode; path: string): string =
  let v = node.get(path)
  case v.kind
  of hnkString: v.str
  of hnkNumber: $v.num
  of hnkBool:   $v.bool
  else: raiseHoconValueError(v.kind, hnkString, path)

proc getBool*(node: HoconNode; path: string): bool =
  let v = node.get(path)
  case v.kind
  of hnkBool: v.bool
  of hnkString:
    case v.str
    of "true",  "yes", "on":  true
    of "false", "no",  "off": false
    else: raiseHoconValueError(v.kind, hnkBool, path)
  else:
    raiseHoconValueError(v.kind, hnkBool, path)


proc doGetFloat(n: HoconNode, path: string): float =
  case n.kind
  of hnkNumber: n.num
  of hnkString:
    try:
      parseFloat(n.str)
    except ValueError:
      raiseHoconValueError(n.kind, hnkNumber, path)
  else:
    raiseHoconValueError(n.kind, hnkNumber, path)

proc getFloat*(node: HoconNode, path: string): float =
  let v = node.get(path)
  v.doGetFloat(path)

proc getInt*(node: HoconNode, path: string): int =
  node.getFloat(path).int

proc getNatural*(node: HoconNode, path: string): Natural =
  let n = node.get(path)
  let v = n.doGetFloat(path)
  if v >= 0: v.Natural
  else: raiseHoconValueError(n.kind, hnkNumber, path)

proc getObject*(node: HoconNode, path: string): OrderedTable[string, HoconNode] =
  let n = node.get(path)
  if n.kind == hnkObject: n.fields
  else: raiseHoconValueError(n.kind, hnkObject, path)

proc getArray*(node: HoconNode, path: string): seq[HoconNode] =
  let n = node.get(path)
  if n.kind == hnkArray: n.elems
  else: raiseHoconValueError(n.kind, hnkArray, path)

# }}}
# {{{ Setters

proc set*(node: HoconNode, path: string, value: HoconNode, createPath = true) =

  proc isInt(s: string): bool =
    try:
      discard parseInt(s)
      true
    except ValueError:
      false

  var curr = node
  let pathElems = path.split('.')

  for i, key {.inject.} in pathElems:
    let isLast = i == pathElems.high

    var arrayIdx = int.none
    try:
      arrayIdx = parseInt(key).some
    except ValueError:
      discard

    if arrayIdx.isSome and arrayIdx.get < 0:
      raiseHoconPathError(path,
                          fmt"Array index must be positive: {arrayIdx.get}")

    if arrayIdx.isSome: # array index
      let arrayIdx = arrayIdx.get

      if curr.kind != hnkArray:
        if createPath:
          curr = newHoconArray()
        else:
          raiseHoconPathError(path, fmt"'{key}' is not an array")

      var arrayExtended = false
      if arrayIdx > curr.elems.high:
        if createPath:
          var elemsToAdd = if curr.elems.len == 0: arrayIdx+1
                           else: arrayIdx - curr.elems.high
          while elemsToAdd > 0:
            curr.elems.add(HoconNode(kind: hnkNull))
            dec(elemsToAdd)
          arrayExtended = true
        else:
          raiseHoconPathError(path, fmt"Invalid array index: {arrayIdx}")

      if isLast:
        curr.elems[arrayIdx] = value
      else:
        if arrayExtended:
          curr.elems[arrayIdx] = if pathElems[i+1].isInt: newHoconArray()
                                 else:                    newHoconObject()
        curr = curr.elems[arrayIdx]

    else: # object key
      if curr.kind != hnkObject:
        if createPath:
          curr = newHoconObject()
        else:
          raiseHoconPathError(path, fmt"'{key}' is not an object")

      if isLast:
        curr.fields[key] = value
      else:
        if not curr.fields.hasKey(key):
          if createPath:
            curr.fields[key] = if pathElems[i+1].isInt: newHoconArray()
                               else:                    newHoconObject()
          else:
            raiseHoconPathError(path, fmt"'{key}' not found")
        curr = curr.fields[key]


proc setNull*(node: HoconNode, path: string, createPath = true) =
  let value = HoconNode(kind: hnkNull)
  node.set(path, value, createPath)

proc set*(node: HoconNode, path: string, str: string, createPath = true) =
  let value = HoconNode(kind: hnkString, str: str)
  node.set(path, value, createPath)

proc set*(node: HoconNode, path: string, num: SomeNumber, createPath = true) =
  let value = HoconNode(kind: hnkNumber, num: num.float)
  node.set(path, value, createPath)

proc set*(node: HoconNode, path: string, flag: bool, createPath = true) =
  let value = HoconNode(kind: hnkBool, bool: flag)
  node.set(path, value, createPath)


proc merge*(dest: HoconNode, src: HoconNode, path: string = "") =
  proc append(path, el: string): string =
    if path == "": el
    else: fmt"{path}.{el}"

  case src.kind
  of hnkArray:
    for idx, child in src.elems:
      merge(dest, child, path.append($idx))
  of hnkObject:
    for key, child in src.fields:
      merge(dest, child, path.append($key))
  else:
    if path != "":
      dest.set(path, src)

# }}}

# }}}

# {{{ Tests
when isMainModule:

  proc `==`*(a, b: Token): bool =
    if a.kind != b.kind: return false
    case a.kind
    of tkString: a.str == b.str
    of tkNumber: a.num == b.num
    else: true

  proc printTree(node: HoconNode, depth: int = 0) =
    let indent = " ".repeat(depth * 2)
    case node.kind
    of hnkArray:
      echo ""
      for val in node.elems:
        stdout.write indent
        printTree(val, depth+1)
    of hnkObject:
      echo ""
      for key, val in node.fields:
        stdout.write indent & key & ": "
        printTree(val, depth+1)
    of hnkNull:   echo "null"
    of hnkString: echo "\"" & $node.str & "\""
    of hnkNumber: echo $node.num
    of hnkBool:   echo $node.bool

  let testString = "\u0024\u00a2\u0939\u20ac\ud5cc"
  # byteLen            1     2     3     3     3
  # byteOffs           0     1     3     6     9

  let
    rune1 = Rune(0x0024)
    rune2 = Rune(0x00a2)
    rune3 = Rune(0x0939)
    rune4 = Rune(0x20ac)
    rune5 = Rune(0xd5cc)

  # {{{ scanner test - read
  block:
    var s = initUnicodeScanner(newStringStream(testString))
    assert s.eatRune == rune1
    assert s.eatRune == rune2
    assert s.eatRune == rune3
    assert s.eatRune == rune4
    assert s.eatRune == rune5

    try:
      discard s.eatRune
      assert false
    except IOError:
      discard

  # }}}
  # {{{ scanner test - peek
  block:
    var s = initUnicodeScanner(newStringStream(testString))
    assert s.peekRune  == rune1
    assert s.peekRune  == rune1
    assert s.eatRune  == rune1

    assert s.peekRune  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune(2) == rune3
    assert s.peekRune(3) == rune4
    assert s.peekRune(4) == rune5
    assert s.peekRune(4) == rune5
    assert s.peekRune  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune(3) == rune4
    assert s.peekRune(4) == rune5

    try:
      discard s.peekRune(5)
      assert false
    except IOError:
      discard

    assert s.eatRune  == rune2
    assert s.eatRune  == rune3
    assert s.eatRune  == rune4
    assert s.eatRune  == rune5

    try:
      discard s.peekRune
      assert false
    except IOError:
      discard

  # }}}
  # {{{ tokeniser test - simple
  block:
    let testString = "{foo:bar}"
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken == Token(kind: tkLeftBrace, line: 1, column: 1)
    assert t.eatToken == Token(kind: tkString, str: "foo", line: 1, column: 2)
    assert t.eatToken == Token(kind: tkColon, line: 1, column: 5)
    assert t.eatToken == Token(kind: tkString, str: "bar", line: 1, column: 6)
    assert t.eatToken == Token(kind: tkRightBrace, line: 1, column: 9)

  # }}}
  # {{{ tokeniser test - strings
  block:
    let testString = """
"C:\\AUTOEXEC.BAT"
"""
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken == Token(kind: tkString, str: "C:\\AUTOEXEC.BAT", line: 1, column: 1)

  # }}}
  # {{{ tokeniser test - booleans & null
  block:
    let testString = """
{
  true_ = 1
  false2 = 2
  nulltrue = 3
  falsenull = 4
}
"""
    var t = initTokeniser(newStringStream(testString))

    # TODO
#    assert t.eatToken == Token(kind: tkLeftBrace, line: 1, column: 1)

#    assert t.eatToken == Token(kind: tkNewline, line: 1, column: 2)
#    assert t.eatToken == Token(kind: tkString, str: "true_", line: 2, column: 3)
#    assert t.eatToken == Token(kind: tkEquals, line: 2, column: 9)
#    assert t.eatToken == Token(kind: tkNumber, num: "1", line: 2, column: 11)
#    assert t.eatToken == Token(kind: tkNewline, line: 1, column: 12)

  # }}}
  # {{{ tokeniser test - complex
  block:
    let testString = """
{
  array: [a, b]
  "quoted": null,
  t = true
  f = false

  "concat":falseSTRING
}
"""
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken == Token(kind: tkLeftBrace, line: 1, column: 1)
    assert t.eatToken == Token(kind: tkNewline, line: 1, column: 2)

    assert t.eatToken == Token(kind: tkString, str: "array", line: 2, column: 3)
    assert t.eatToken == Token(kind: tkColon, line: 2, column: 8)
    assert t.eatToken == Token(kind: tkLeftBracket, line: 2, column: 10)
    assert t.eatToken == Token(kind: tkString, str: "a", line: 2, column: 11)
    assert t.eatToken == Token(kind: tkComma, line: 2, column: 12)
    assert t.eatToken == Token(kind: tkString, str: "b", line: 2, column: 14)
    assert t.eatToken == Token(kind: tkRightBracket, line: 2, column: 15)
    assert t.eatToken == Token(kind: tkNewline, line: 2, column: 16)

    assert t.eatToken == Token(kind: tkString, str: "quoted", line: 3, column: 3)
    assert t.eatToken == Token(kind: tkColon, line: 3, column: 11)
    assert t.eatToken == Token(kind: tkNull, line: 3, column: 13)
    assert t.eatToken == Token(kind: tkComma, line: 3, column: 17)
    assert t.eatToken == Token(kind: tkNewline, line: 3, column: 18)

    assert t.eatToken == Token(kind: tkString, str: "t", line: 4, column: 3)
    assert t.eatToken == Token(kind: tkEquals, line: 4, column: 5)
    assert t.eatToken == Token(kind: tkTrue, line: 4, column: 7)
    assert t.eatToken == Token(kind: tkNewline, line: 4, column: 11)

    assert t.eatToken == Token(kind: tkString, str: "f", line: 5, column: 3)
    assert t.eatToken == Token(kind: tkEquals, line: 5, column: 5)
    assert t.eatToken == Token(kind: tkFalse, line: 5, column: 7)
    assert t.eatToken == Token(kind: tkNewline, line: 5, column: 12)
    assert t.eatToken == Token(kind: tkNewline, line: 6, column: 1)

    assert t.eatToken == Token(kind: tkString, str: "concat", line: 7, column: 3)
    assert t.eatToken == Token(kind: tkColon, line: 7, column: 11)
    assert t.eatToken == Token(kind: tkString, str: "falseSTRING", line: 7, column: 12)
    assert t.eatToken == Token(kind: tkNewline, line: 7, column: 23)

    assert t.eatToken == Token(kind: tkRightBrace, line: 8, column: 1)

  # }}}
  # {{{ tokeniser test - numbers
  block:
    let testString = """
0 01 1 -1
1. 1.0123 .4
1e5 00e5 1e-5 1e04 -1.e-005
1.e-5 1.234e-5
"""
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken == Token(kind: tkNumber, num: "0", line: 1, column: 1)
    assert t.eatToken == Token(kind: tkNumber, num: "01", line: 1, column: 3)
    assert t.eatToken == Token(kind: tkNumber, num: "1", line: 1, column: 6)
    assert t.eatToken == Token(kind: tkNumber, num: "-1", line: 1, column: 8)
    assert t.eatToken == Token(kind: tkNewline, line: 1, column: 10)

    assert t.eatToken == Token(kind: tkNumber, num: "1.", line: 2, column: 1)
    assert t.eatToken == Token(kind: tkNumber, num: "1.0123", line: 2, column: 4)
    assert t.eatToken == Token(kind: tkNumber, num: ".4", line: 2, column: 11)
    assert t.eatToken == Token(kind: tkNewline, line: 2, column: 13)

    assert t.eatToken == Token(kind: tkNumber, num: "1e5", line: 3, column: 1)
    assert t.eatToken == Token(kind: tkNumber, num: "00e5", line: 3, column: 5)
    assert t.eatToken == Token(kind: tkNumber, num: "1e-5", line: 3, column: 10)
    assert t.eatToken == Token(kind: tkNumber, num: "1e04", line: 3, column: 15)
    assert t.eatToken == Token(kind: tkNumber, num: "-1.e-005", line: 3, column: 20)
    assert t.eatToken == Token(kind: tkNewline, line: 3, column: 28)

    assert t.eatToken == Token(kind: tkNumber, num: "1.e-5", line: 4, column: 1)
    assert t.eatToken == Token(kind: tkNumber, num: "1.234e-5", line: 4, column: 7)
    assert t.eatToken == Token(kind: tkNewline, line: 4, column: 15)

  # }}}
  # {{{ equality test
  block:
    let n1 = HoconNode(kind: hnkBool, bool: true)
    assert n1 == n1.deepCopy

    let n2 = HoconNode(kind: hnkString, str: "foo")
    assert n2 == n2.deepCopy

    let n3 = HoconNode(kind: hnkNull)
    assert n3 == n3.deepCopy

    let n4 = HoconNode(kind: hnkNumber, num: 123.456)
    assert n4 == n4.deepCopy

    var arr = newHoconArray()
    arr.elems.add(n1)
    arr.elems.add(n2)
    arr.elems.add(n3)
    assert arr == arr.deepCopy

    var obj = newHoconObject()
    obj.set("a", true)
    obj.set("b", 42)
    obj.set("c", "foo")
    assert obj == obj.deepCopy

    var obj2 = newHoconObject()
    obj.set("o2", obj.deepCopy)
    obj.set("a", arr.deepCopy)
    assert obj2 == obj2.deepCopy

  # }}}
  # {{{ parser test

  block:
    let testString = """
{
  a {
    b = "c"
    aa {
      foo = false
    }
    d = 5
    e = [1,2,3]
  }
  b = 123
}
"""

    var p = initHoconParser(newStringStream(testString))
    let root = p.parse
#    printTree(root)

    block:
      let ab  = root.get("a.b")
      assert ab == HoconNode(kind: hnkString, str: "c")

      let foo = root.get("a.aa.foo")
      assert foo == HoconNode(kind: hnkBool, bool: false)

      let d   = root.get("a.d")
      assert d == HoconNode(kind: hnkNumber, num: 5.0)

      let e0  = root.get("a.e.0")
      assert e0 == HoconNode(kind: hnkNumber, num: 1.0)

      let e1  = root.get("a.e.1")
      assert e1 == HoconNode(kind: hnkNumber, num: 2.0)

      let e2  = root.get("a.e.2")
      assert e2 == HoconNode(kind: hnkNumber, num: 3.0)

      let b   = root.get("b")
      assert b == HoconNode(kind: hnkNumber, num: 123.0)

    block:
      let ab  = root.getString("a.b")
      assert ab == "c"

      let foo = root.getBool("a.aa.foo")
      assert foo == false

      let d   = root.getNatural("a.d")
      assert d == 5

      let e0  = root.getFloat("a.e.0")
      assert e0 == 1.0

      let e1  = root.getInt("a.e.1")
      assert e1 == 2

      let e2  = root.getFloat("a.e.2")
      assert e2 == 3.0

      let b   = root.getString("b")
      assert b == "123.0"

  block:
    let testString = """

objA { # comment }=;./23!@#//##{
  foo = "fooval"//blah
  # line comment
  // line comment
  obj2
  {
    arr = [//
      1, 2#
      3#
    ]#
    //}
    obj3{a:"b"}
    key1 = true, key2 = null
    obj4{c:"d"}}
  bar
    =1234.5
    obj5 {"x"=y }
}
objB { b: false }
c = "d"
"""
    var p = initHoconParser(newStringStream(testString))
    let root = p.parse

#    echo '-'.repeat(40)
#    printTree(root)

    var st = newStringStream()
#    echo '-'.repeat(40)
    root.write(st)
#    echo st.data

  # }}}
  # {{{ setter test
  block:
    var obj = newHoconObject()
    obj.set("a.b.c1.d1", true)
    obj.set("a.b.c1.d2", 42)
    obj.set("a.b.c2.0", "x")
    obj.set("a.b.c2.2", "z")
    obj.set("a.b.c2.1", "y")
    obj.set("a.b.c2.5.2.foo.1", "bar")

    assert obj.getBool("a.b.c1.d1") == true
    assert obj.getInt("a.b.c1.d2") == 42
    assert obj.getString("a.b.c2.0") == "x"
    assert obj.getString("a.b.c2.2") == "z"
    assert obj.getString("a.b.c2.1") == "y"
    assert obj.getString("a.b.c2.5.2.foo.1") == "bar"

    var st = newStringStream()
#    echo '-'.repeat(40)
    obj.write(st)
#    echo st.data

# }}}
  # {{{ merge test
  block:
    let srcObj = """
{
  a = {
    b = {
      c = 5
    }
    d = "foo"
    e = [1,2,3]
  }
  f = [
    {
      g = 11
      h = 12
    },
    42
  ]
  i = "end"
  j = false
}
"""
    var p = initHoconParser(newStringStream(srcObj))
    let src = p.parse

    block:
      var st = newStringStream()
#      echo '-'.repeat(40)
      src.write(st)
#      echo st.data

    let destObj = """
{
  a = {
    b = {
      x1 = 5
    }
    x2 = true
  }
  f = ["A", "B"]
  x = "X"
  y = "Y"
  j = [true, false]
}
"""
    p = initHoconParser(newStringStream(destObj))
    let dest = p.parse

    dest.merge(src)

    block:
      var st = newStringStream()
#      echo '-'.repeat(40)
      dest.write(st)
#      echo st.data

# }}}
# }}}

# vim: et:ts=2:sw=2:fdm=marker
