import deques
import unicode
import streams
import strformat
import strutils
import tables

# {{{ UnicodeScanner

type
  UnicodeScanner = object
    stream:  Stream
    readBuf: string
    peekBuf: Deque[Rune]
    line, column: Natural

using s: var UnicodeScanner

proc initUnicodeScanner(stream: Stream): UnicodeScanner =
  result.stream = stream
  result.readBuf = newStringOfCap(4)
  result.readBuf.setLen(4)
  result.peekBuf = initDeque[Rune]()

proc readNextRune(s): Rune =
  proc raiseEOFError() =
    raise newException(IOError, "Unexpected end of file")

  if s.stream.atEnd: raiseEOFError()
  s.readBuf[0] = cast[char](s.stream.readUint8())
  let runeLen = s.readBuf.runeLenAt(0)
  let bytesRead = s.stream.readDataStr(s.readBuf, 1..(1 + runeLen-2))
  if bytesRead + 1 != runeLen: raiseEOFError()
  s.readBuf.runeAt(0)

proc peekRune(s; lookahead: Natural = 1): Rune =
  assert(lookahead >= 1)
  while lookahead > s.peekBuf.len:
    s.peekBuf.addLast(s.readNextRune())
  s.peekBuf[lookahead-1]

proc eatRune(s): Rune =
  if s.peekBuf.len > 0: s.peekBuf.popFirst()
  else: s.readNextRune()

proc atEnd(s): bool =
  s.stream.atEnd()

proc close(s) =
  s.stream.close()
  s.stream = nil

# }}}
# {{{ Tokeniser

type
  TokenKind = enum
    tkLeftBrace, tkRightBrace,
    tkLeftBracket, tkRightBracket,
    tkComma, tkNewline, # TODO tkWhitespace
    tkColon, tkEquals,
    tkString,
    tkNumber,
    tkTrue, tkFalse,
    tkNull

  Token = object
    case kind: TokenKind
    of tkString: str: string
    of tkNumber: num: string
    else: discard
    line, column: Natural

  Tokeniser = object
    scanner:      UnicodeScanner
    line, column: Natural
    peekBuf:      Deque[Token]

  TokeniserError* = object of IOError


proc `==`(a, b: Token): bool =
  if a.kind == b.kind and
     a.line == b.line and
     a.column == b.column:
    case a.kind
    of tkString: a.str == b.str
    of tkNumber: a.num == b.num
    else: true
  else:
    false


let validQuotedStringRuneRange = 0x0020..0x10fff

let whitespaceRunes = @[
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

let forbiddenRunes = @[
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
  raise newException(TokeniserError,
    fmt"{msg} at line {line}, column {column}: {details}"
  )

proc peekRune(t; lookahead: Natural = 1): Rune =
  t.scanner.peekRune(lookahead)

proc eatRune(t): Rune =
  inc(t.column)
  t.scanner.eatRune()

proc readEscape(t; line, col: Natural): Rune =
  let rune = t.eatRune()
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
    let hexStr = $t.eatRune() & $t.eatRune() & $t.eatRune() & $t.eatRune()
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

  discard t.eatRune()
  let line = t.line
  let col = t.column

  var rune = t.eatRune()

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
      rune = t.eatRune()

  Token(kind: tkString, str: str, line: line, column: col)


proc readUnquotedStringOrBooleanOrNull(t): Token =
  var str = ""
  var rune = t.eatRune()
  let line = t.line
  let col = t.column

  while true:
    str &= rune
    case str
    of "true":  return Token(kind: tkTrue,  line: line, column: col)
    of "false": return Token(kind: tkFalse, line: line, column: col)
    of "null":  return Token(kind: tkNull,  line: line, column: col)
    else:
      rune = t.peekRune()
      if rune == Rune('\n') or
         rune in whitespaceRunes or
         rune in forbiddenRunes: break
      else:
        rune = t.eatRune()

  Token(kind: tkString, str: str, line: line, column: col)


proc readNumberOrString(t): Token =
  var str = ""
  var rune = t.eatRune()
  let line = t.line
  let col = t.column

  while true:
    str &= rune
    rune = t.peekRune()
    if rune == Rune('\n') or
       rune in whitespaceRunes or
       rune in forbiddenRunes: break
    else:
      rune = t.eatRune()

  try:
    discard parseFloat(str)
    Token(kind: tkNumber, num: str, line: line, column: col)
  except ValueError:
    Token(kind: tkString, str: str, line: line, column: col)


proc skipComment(t) =
  while true:
    let rune = t.peekRune()
    if rune == Rune('\n'): return
    discard t.eatRune()


proc readNextToken(t): Token =

  proc mkSimpleToken(t; kind: TokenKind): Token =
    discard t.eatRune()
    Token(kind: kind, line: t.line, column: t.column)

  var rune = t.peekRune()
  while rune in whitespaceRunes:
    discard t.eatRune()
    rune = t.peekRune()

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
    t.readNumberOrString()

  of Rune('"'):
    t.readQuotedString()

  of Rune('#'):
    t.skipComment()
    t.readNextToken()

  of Rune('/'):
    if t.peekRune(2) == Rune('/'):
      t.skipComment()
      t.readNextToken()
    else:
      t.readUnquotedStringOrBooleanOrNull()

  else:
    t.readUnquotedStringOrBooleanOrNull()


proc peekToken(t; lookahead: Natural = 1): Token =
  assert(lookahead >= 1)
  while lookahead > t.peekBuf.len:
    t.peekBuf.addLast(t.readNextToken())
  t.peekBuf[lookahead-1]

proc eatToken(t): Token =
  if t.peekBuf.len > 0: t.peekBuf.popFirst()
  else: t.readNextToken()

proc atEnd(t): bool =
  t.scanner.atEnd()


# }}}
# {{{ HoconParser

type
  HoconParser* = object
    tokeniser: Tokeniser

  HoconParsingError* = object of IOError

  HoconNodeKind* = enum
    hnkNull, hnkString, hnkNumber, hnkBool, hnkObject, hnkArray

  HoconNode* = ref HoconNodeObj

  HoconNodeObj* = object
    case kind*: HoconNodeKind
    of hnkNull:   discard
    of hnkString: str*:    string
    of hnkNumber: num*:    float64
    of hnkBool:   bool*:   bool
    of hnkObject: fields*: OrderedTable[string, HoconNode]
    of hnkArray:  elems*:  seq[HoconNode]


using p: var HoconParser

proc initHoconParser*(stream: Stream): HoconParser =
  result.tokeniser = initTokeniser(stream)

proc raiseUnexpectedTokenError(p; token: Token) {.noReturn.} =
  raise newException(HoconParsingError, fmt"Unexpected token: {token}")

proc peekToken(p): Token = p.tokeniser.peekToken()
proc eatToken(p):  Token = p.tokeniser.eatToken()


proc eatEither(p; kinds: varargs[TokenKind]): Token =
  let token = p.tokeniser.eatToken()
  if token.kind notin kinds:
    p.raiseUnexpectedTokenError(token)
  else: token

proc eatNewLines(p): bool =
  if p.tokeniser.atEnd(): return
  var token = p.peekToken()
  while token.kind == tkNewLine:
    result = true
    discard p.eatToken()
    if p.tokeniser.atEnd(): return
    token = p.peekToken()

proc eatNewLinesOrSingleComma(p): bool =
  var newlinesRead = p.eatNewLines()
  if p.tokeniser.atEnd(): return
  if p.peekToken().kind == tkComma:
    discard p.eatToken()
    true
  else: newLinesRead

proc parseObject(p; allowImplicitBraces: bool = false): HoconNode
proc parseArray(p): HoconNode

proc parseNode(p): HoconNode =
  let token = p.peekToken()
  case token.kind:
  of tkString:
    discard p.eatToken()
    HoconNode(kind: hnkString, str: token.str)

  of tkNumber:
    discard p.eatToken()
    HoconNode(kind: hnkNumber, num: parseFloat(token.num))

  of tkTrue:
    discard p.eatToken()
    HoconNode(kind: hnkBool, bool: true)

  of tkFalse:
    discard p.eatToken()
    HoconNode(kind: hnkBool, bool: false)

  of tkNull:
    discard p.eatToken()
    HoconNode(kind: hnkNull)

  of tkLeftBrace:   p.parseObject()
  of tkLeftBracket: p.parseArray()
  else:
    p.raiseUnexpectedTokenError(token)


proc parseObject(p; allowImplicitBraces: bool = false): HoconNode =
  var implicitBraces = false
  var skipFirstPeek = false

  var token = p.peekToken()
  if token.kind == tkLeftBrace:
    discard p.eatToken()
    discard p.eatNewLines()
  else:
    if allowImplicitBraces:
      implicitBraces = true
      if token.kind == tkNewLine:
        discard p.eatToken()
        discard p.eatNewLines()
      else:
        skipFirstPeek = true
    else:
      p.raiseUnexpectedTokenError(token)

  result = HoconNode(kind: hnkObject)

  var sepa = true
  while true:
    if implicitBraces and p.tokeniser.atEnd():
      break

    if not skipFirstPeek:
      token = p.peekToken()
    skipFirstPeek = false

    case token.kind
    of tkRightBrace:
      if implicitBraces:
        p.raiseUnexpectedTokenError(token)
      else:
        discard p.eatToken()
        break

    of tkString:
      if not sepa:
        p.raiseUnexpectedTokenError(token)
      let key = p.eatToken().str
      discard p.eatNewLines()

      let node = if p.peekToken().kind == tkLeftBrace:
        p.parseObject()
      else:
        discard p.eatEither(tkColon, tkEquals)
        discard p.eatNewLines()
        p.parseNode()

      result.fields[key] = node
      sepa = p.eatNewLinesOrSingleComma()

    else:
      p.raiseUnexpectedTokenError(token)


proc parseArray(p): HoconNode =
  discard p.eatEither(tkLeftBracket)
  discard p.eatNewLines()

  result = HoconNode(kind: hnkArray)

  var sepa = true
  while true:
    let token = p.peekToken()
    case token.kind
    of tkRightBracket:
      discard p.eatToken()
      break
    else:
      if not sepa:
        p.raiseUnexpectedTokenError(token)
      discard p.eatNewLines()

      let node = if p.peekToken().kind == tkLeftBrace:
        p.parseObject()
      else:
        p.parseNode()

      result.elems.add(node)
      sepa = p.eatNewLinesOrSingleComma()


proc parse*(p): HoconNode =
  discard p.eatNewLines()

  let token = p.peekToken()
  if token.kind == tkLeftBracket:
    p.parseArray()
  else:
    p.parseObject(allowImplicitBraces=true)

# }}}

# {{{ Writer

proc write*(node: HoconNode, stream: Stream,
            writeRootObjectBraces: bool = false,
            newlineBeforeObjectDepthLimit: Natural = 1) =

  proc go(curr: HoconNode, parent: HoconNode; depth, indent: int) =
    case curr.kind
    of hnkArray:
      stream.write(" = [\n")
      for val in curr.elems:
        stream.write(" ".repeat((indent+1) * 2))
        go(val, curr, depth+1, indent+1)
        stream.write("\n")
      stream.write(" ".repeat((indent) * 2))
      stream.write("]")

    of hnkObject:
      let writeBraces = depth > 0 or (depth == 0 and writeRootObjectBraces)
      if writeBraces:
        if depth > 0: stream.write(" ")
        stream.write("{\n")

      for key, val in curr.fields:
        if depth <= newlineBeforeObjectDepthLimit and
           val.kind == hnkObject:
          stream.write("\n")

        stream.write(" ".repeat((indent+1) * 2) & key)
        go(val, curr, depth+1, indent+1)
        stream.write("\n")

      if writeBraces:
        stream.write(" ".repeat((indent) * 2))
        stream.write("}")

    of hnkNull:
      if (parent.kind != hnkArray): stream.write(" = ")
      stream.write("null")

    of hnkString:
      if (parent.kind != hnkArray): stream.write(" = ")
      stream.write("\"" & $curr.str & "\"")

    of hnkNumber:
      if (parent.kind != hnkArray): stream.write(" = ")
      stream.write($curr.num)

    of hnkBool:
      if (parent.kind != hnkArray): stream.write(" = ")
      stream.write($curr.bool)

  let startIndent = if writeRootObjectBraces: 0 else: -1
  go(node, nil, depth=0, indent=startIndent)

# }}}
# {{{ Helpers

type HoconPathError* = object of CatchableError

proc newHoconObject(): HoconNode = HoconNode(kind: hnkObject)
proc newHoconArray(): HoconNode = HoconNode(kind: hnkArray)

proc raiseHoconPathError(path, message: string) {.noReturn.} =
  raise newException(HoconPathError,
                     fmt"Invalid object path: {path}, {message}")

proc hasOnlyDigits(s: string): bool =
  for c in s:
    if not c.isDigit(): return false
  true

# {{{ get
proc get*(node: HoconNode, path: string): HoconNode =
  var curr = node
  for key in path.split('.'):
    if key.hasOnlyDigits():
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

# }}}
# {{{ set
template setValue*(node: HoconNode, path: string, body: untyped) =
  var curr {.inject.} = node
  let pathElems = path.split('.')

  for i, key {.inject.} in pathElems.pairs:
    if curr.kind != hnkObject:
      raiseHoconPathError(path, fmt"'{key}' is not an object")

    let isLast = i == pathElems.high
    if isLast: body
    else:
      if not curr.fields.hasKey(key):
        curr.fields[key] = newHoconObject()
      curr = curr.fields[key]


proc set*(node: HoconNode, path: string, str: string) =
  node.setValue(path):
    curr.fields[key] = HoconNode(kind: hnkString, str: str)

proc set*(node: HoconNode, path: string, num: SomeNumber) =
  node.setValue(path):
    curr.fields[key] = HoconNode(kind: hnkNumber, num: num.float)

proc set*(node: HoconNode, path: string, flag: bool) =
  node.setValue(path):
    curr.fields[key] = HoconNode(kind: hnkBool, bool: flag)

proc setNull*(node: HoconNode, path: string) =
  node.setValue(path):
    curr.fields[key] = HoconNode(kind: hnkNull)

# }}}
# }}}

# {{{ Tests
when isMainModule:
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
    assert s.eatRune() == rune1
    assert s.eatRune() == rune2
    assert s.eatRune() == rune3
    assert s.eatRune() == rune4
    assert s.eatRune() == rune5

    try:
      discard s.eatRune()
      assert false
    except IOError:
      discard

  # }}}
  # {{{ scanner test - peek
  block:
    var s = initUnicodeScanner(newStringStream(testString))
    assert s.peekRune()  == rune1
    assert s.peekRune()  == rune1
    assert s.eatRune()  == rune1

    assert s.peekRune()  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune()  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune(2) == rune3
    assert s.peekRune(3) == rune4
    assert s.peekRune(4) == rune5
    assert s.peekRune(4) == rune5
    assert s.peekRune()  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune(3) == rune4
    assert s.peekRune(4) == rune5

    try:
      discard s.peekRune(5)
      assert false
    except IOError:
      discard

    assert s.eatRune()  == rune2
    assert s.eatRune()  == rune3
    assert s.eatRune()  == rune4
    assert s.eatRune()  == rune5

    try:
      discard s.peekRune()
      assert false
    except IOError:
      discard

  # }}}
  # {{{ tokeniser test - simple
  block:
    let testString = "{foo:bar}"
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken() == Token(kind: tkLeftBrace, line: 1, column: 1)
    assert t.eatToken() == Token(kind: tkString, str: "foo", line: 1, column: 2)
    assert t.eatToken() == Token(kind: tkColon, line: 1, column: 5)
    assert t.eatToken() == Token(kind: tkString, str: "bar", line: 1, column: 6)
    assert t.eatToken() == Token(kind: tkRightBrace, line: 1, column: 9)

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
#    assert t.eatToken() == Token(kind: tkLeftBrace, line: 1, column: 1)

#    assert t.eatToken() == Token(kind: tkNewline, line: 1, column: 2)
#    assert t.eatToken() == Token(kind: tkString, str: "true_", line: 2, column: 3)
#    assert t.eatToken() == Token(kind: tkEquals, line: 2, column: 9)
#    assert t.eatToken() == Token(kind: tkNumber, num: "1", line: 2, column: 11)
#    assert t.eatToken() == Token(kind: tkNewline, line: 1, column: 12)

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

    assert t.eatToken() == Token(kind: tkLeftBrace, line: 1, column: 1)
    assert t.eatToken() == Token(kind: tkNewline, line: 1, column: 2)

    assert t.eatToken() == Token(kind: tkString, str: "array", line: 2, column: 3)
    assert t.eatToken() == Token(kind: tkColon, line: 2, column: 8)
    assert t.eatToken() == Token(kind: tkLeftBracket, line: 2, column: 10)
    assert t.eatToken() == Token(kind: tkString, str: "a", line: 2, column: 11)
    assert t.eatToken() == Token(kind: tkComma, line: 2, column: 12)
    assert t.eatToken() == Token(kind: tkString, str: "b", line: 2, column: 14)
    assert t.eatToken() == Token(kind: tkRightBracket, line: 2, column: 15)
    assert t.eatToken() == Token(kind: tkNewline, line: 2, column: 16)

    assert t.eatToken() == Token(kind: tkString, str: "quoted", line: 3, column: 3)
    assert t.eatToken() == Token(kind: tkColon, line: 3, column: 11)
    assert t.eatToken() == Token(kind: tkNull, line: 3, column: 13)
    assert t.eatToken() == Token(kind: tkComma, line: 3, column: 17)
    assert t.eatToken() == Token(kind: tkNewline, line: 3, column: 18)

    assert t.eatToken() == Token(kind: tkString, str: "t", line: 4, column: 3)
    assert t.eatToken() == Token(kind: tkEquals, line: 4, column: 5)
    assert t.eatToken() == Token(kind: tkTrue, line: 4, column: 7)
    assert t.eatToken() == Token(kind: tkNewline, line: 4, column: 11)

    assert t.eatToken() == Token(kind: tkString, str: "f", line: 5, column: 3)
    assert t.eatToken() == Token(kind: tkEquals, line: 5, column: 5)
    assert t.eatToken() == Token(kind: tkFalse, line: 5, column: 7)
    assert t.eatToken() == Token(kind: tkNewline, line: 5, column: 12)
    assert t.eatToken() == Token(kind: tkNewline, line: 6, column: 1)

    assert t.eatToken() == Token(kind: tkString, str: "concat", line: 7, column: 3)
    assert t.eatToken() == Token(kind: tkColon, line: 7, column: 11)
    assert t.eatToken() == Token(kind: tkFalse, line: 7, column: 12)
    assert t.eatToken() == Token(kind: tkString, str: "STRING", line: 7, column: 17)
    assert t.eatToken() == Token(kind: tkNewline, line: 7, column: 23)

    assert t.eatToken() == Token(kind: tkRightBrace, line: 8, column: 1)

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

    assert t.eatToken() == Token(kind: tkNumber, num: "0", line: 1, column: 1)
    assert t.eatToken() == Token(kind: tkNumber, num: "01", line: 1, column: 3)
    assert t.eatToken() == Token(kind: tkNumber, num: "1", line: 1, column: 6)
    assert t.eatToken() == Token(kind: tkNumber, num: "-1", line: 1, column: 8)
    assert t.eatToken() == Token(kind: tkNewline, line: 1, column: 10)

    assert t.eatToken() == Token(kind: tkNumber, num: "1.", line: 2, column: 1)
    assert t.eatToken() == Token(kind: tkNumber, num: "1.0123", line: 2, column: 4)
    assert t.eatToken() == Token(kind: tkNumber, num: ".4", line: 2, column: 11)
    assert t.eatToken() == Token(kind: tkNewline, line: 2, column: 13)

    assert t.eatToken() == Token(kind: tkNumber, num: "1e5", line: 3, column: 1)
    assert t.eatToken() == Token(kind: tkNumber, num: "00e5", line: 3, column: 5)
    assert t.eatToken() == Token(kind: tkNumber, num: "1e-5", line: 3, column: 10)
    assert t.eatToken() == Token(kind: tkNumber, num: "1e04", line: 3, column: 15)
    assert t.eatToken() == Token(kind: tkNumber, num: "-1.e-005", line: 3, column: 20)
    assert t.eatToken() == Token(kind: tkNewline, line: 3, column: 28)

    assert t.eatToken() == Token(kind: tkNumber, num: "1.e-5", line: 4, column: 1)
    assert t.eatToken() == Token(kind: tkNumber, num: "1.234e-5", line: 4, column: 7)
    assert t.eatToken() == Token(kind: tkNewline, line: 4, column: 15)

  # }}}
  # {{{ parser test

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
    let root = p.parse()
    printTree(root)

    echo root.get("a.b")[]
    echo root.get("a.aa.foo")[]
    echo root.get("a.d")[]
    echo root.get("a.e.0")[]
    echo root.get("a.e.1")[]
    echo root.get("a.e.2")[]
    echo root.get("b")[]


  block:
    let testString = """

obj1 { # comment }=;./23!@#//##{
  foo = "fooval"//blah
  bar
    =1234.5
  # line comment
  // line comment
  obj2
  {
    key1 = true, key2 = null
    arr = [//
      1, 2#
      3#
    ]#
    //}
    obj3{a:"b"}}
}
c = "d"
"""
    var p = initHoconParser(newStringStream(testString))
    let root = p.parse()

    echo '-'.repeat(40)
    printTree(root)

    var st = newStringStream()
    echo '-'.repeat(40)
    root.write(st)
    echo st.data

  # }}}

# }}}

# vim: et:ts=2:sw=2:fdm=marker
