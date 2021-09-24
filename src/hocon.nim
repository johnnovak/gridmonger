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
  s.readBuf[0] = cast[char](s.stream.readUint8())
  let runeLen = s.readBuf.runeLenAt(0)
  let bytesRead = s.stream.readDataStr(s.readBuf, 1..(1 + runeLen-2))
  if bytesRead + 1 != runeLen:
    raise newException(IOError, "Unexpected end of file")
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
    tkComma, tkNewline,
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

proc peekRune(t): Rune =
  t.scanner.peekRune()

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
  HoconParser = object
    tokeniser: Tokeniser

  HoconParsingError* = object of IOError

  HoconNodeKind = enum
    hnkNull, hnkString, hnkNumber, hnkBool, hnkObject, hnkArray

  HoconNode = ref HoconNodeObj

  HoconNodeObj = object
    key: string
    case kind: HoconNodeKind
    of hnkNull:   discard
    of hnkString: str:    string
    of hnkNumber: num:    float64
    of hnkBool:   bool:   bool
    of hnkObject: fields: OrderedTable[string, HoconNode]
    of hnkArray:  elems:  seq[HoconNode]


using p: var HoconParser

proc initParser(stream: Stream): HoconParser =
  result.tokeniser = initTokeniser(stream)


proc raiseUnexpectedTokenError(p; token: Token) {.noReturn.} =
  raise newException(HoconParsingError,
    fmt"Unexpected token {token.kind} " &
    fmt"at line {token.line}, column {token.column})"
  )


#    of tkRightBrace:
#    of tkRightBracket:
#    of tkComma:
#    of tkNewline:
#    of tkColon:
#    of tkEquals:
#    of tkString:
#    of tkNumber:
#    of tkTrue:
#    of tkFalse:
#    of tkNull:

proc peekToken(p): Token = p.tokeniser.peekToken()
proc eatToken(p):  Token = p.tokeniser.eatToken()

proc eatEither(p; kinds: varargs[TokenKind]): Token =
  let token = p.tokeniser.eatToken()
  if token.kind notin kinds:
    p.raiseUnexpectedTokenError(token)
  else: token

proc eatNewLines(p): bool =
  var token = p.peekToken()
  while token.kind == tkNewLine:
    discard p.eatToken()
    token = p.peekToken()

proc eatNewLinesOrSingleComma(p): bool =
  var newlinesRead = p.eatNewLines()
  if p.peekToken().kind == tkComma:
    discard p.eatNewLines()
    true
  else: newLinesRead

proc parseValue(p): HoconNode =
  new HoconNode

proc parseObject(p): HoconNode =
  discard p.eatEither(tkLeftBrace)
  discard p.eatNewLines()

  var separator = true
  while true:
    let token = p.peekToken()
    case token.kind
    of tkRightBrace:
      discard p.eatToken()
      break

    of tkString:
      if not separator:
        p.raiseUnexpectedTokenError(token)

      let key = token.str
      discard p.eatNewLines()
      discard p.eatEither(tkColon, tkEquals)
      discard p.eatNewLines()

      let value = p.parseValue()
      separator = p.eatNewLinesOrSingleComma()
      # TODO key-value

    else: p.raiseUnexpectedTokenError(token)

  new HoconNode

proc parseArray(p): HoconNode =
  new HoconNode

proc parse(p): HoconNode =
  let token = p.peekToken()
  case token.kind
  of tkLeftBrace: p.parseObject()
  of tkLeftBracket: p.parseArray()
  else: p.raiseUnexpectedTokenError(token)

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

  block: # read test
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

  block: # peek test
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

  block: # tokeniser test - simple
    let testString = "{foo:bar}"
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken() == Token(kind: tkLeftBrace, line: 1, column: 1)
    assert t.eatToken() == Token(kind: tkString, str: "foo", line: 1, column: 2)
    assert t.eatToken() == Token(kind: tkColon, line: 1, column: 5)
    assert t.eatToken() == Token(kind: tkString, str: "bar", line: 1, column: 6)
    assert t.eatToken() == Token(kind: tkRightBrace, line: 1, column: 9)

  block: # tokeniser test - complex
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

  block: # tokeniser test - numbers
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

# vim: et:ts=2:sw=2:fdm=marker
