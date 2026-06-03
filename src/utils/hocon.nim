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

proc initUnicodeScanner*(stream: Stream): UnicodeScanner =
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


proc peekRune*(s; lookahead: Natural = 1): Rune =
  assert lookahead >= 1
  while lookahead > s.peekBuf.len:
    s.peekBuf.addLast(s.readNextRune)
  s.peekBuf[lookahead-1]

proc eatRune*(s): Rune =
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
  TokenKind* = enum
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

  Token* = object
    case  kind*:    TokenKind
    of    tkString: str*: string
    of    tkNumber: num*: string
    else: discard
    line*, column*:   Natural

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

proc initTokeniser*(stream: Stream): Tokeniser =
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

proc peekRune*(t; lookahead: Natural = 1): Rune =
  t.scanner.peekRune(lookahead)

proc eatRune*(t): Rune =
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


proc peekToken*(t; lookahead: Natural = 1): Token =
  assert lookahead >= 1
  while lookahead > t.peekBuf.len:
    t.peekBuf.addLast(t.readNextToken)
  t.peekBuf[lookahead-1]

proc eatToken*(t): Token =
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

proc peekToken*(p): Token = p.tokeniser.peekToken
proc eatToken*(p):  Token = p.tokeniser.eatToken


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

# }}}
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

# {{{ set*() - HoconNode
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

# }}}
# {{{ set*() - primitive types
proc set*(node: HoconNode, path: string, str: string, createPath = true) =
  let value = HoconNode(kind: hnkString, str: str)
  node.set(path, value, createPath)

proc set*(node: HoconNode, path: string, num: SomeNumber, createPath = true) =
  let value = HoconNode(kind: hnkNumber, num: num.float)
  node.set(path, value, createPath)

proc set*(node: HoconNode, path: string, flag: bool, createPath = true) =
  let value = HoconNode(kind: hnkBool, bool: flag)
  node.set(path, value, createPath)

# }}}
# {{{ setNull*()
proc setNull*(node: HoconNode, path: string, createPath = true) =
  let value = HoconNode(kind: hnkNull)
  node.set(path, value, createPath)

# }}}
#
# {{{ merge*()
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

# {{{ del*()
proc del*(node: HoconNode, path: string) =

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
      if curr.kind != hnkArray:
        raiseHoconPathError(path, fmt"'{key}' is not an array")

      var arrayExtended = false
      let arrayIdx = arrayIdx.get
      if arrayIdx > curr.elems.high:
        raiseHoconPathError(path, fmt"Invalid array index: {arrayIdx}")

      if isLast:
        curr.elems.delete(arrayIdx)
      else:
        curr = curr.elems[arrayIdx]

    else: # object key
      if curr.kind != hnkObject:
        raiseHoconPathError(path, fmt"'{key}' is not an object")

      if isLast:
        curr.fields.del(key)
      else:
        if not curr.fields.hasKey(key):
          raiseHoconPathError(path, fmt"'{key}' not found")
        curr = curr.fields[key]

# }}}

# }}}

# vim: et:ts=2:sw=2:fdm=marker
