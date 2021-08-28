import deques
import unicode
import streams
import strformat
import strutils

# {{{ UnicodeScanner

type
  UnicodeScanner = object
    stream:  Stream
    readBuf: string
    peekBuf: Deque[Rune]
    line, column: Natural

using s: var UnicodeScanner

proc initUnicodeScanner*(stream: Stream): UnicodeScanner =
  result.stream = stream
  result.readBuf = newStringOfCap(4)
  result.readBuf.setLen(4)
  result.peekBuf = initDeque[Rune]()

proc doReadRune(s): Rune =
  s.readBuf[0] = cast[char](s.stream.readUint8())
  let runeLen = s.readBuf.runeLenAt(0)
  let bytesRead = s.stream.readDataStr(s.readBuf, 1..(1 + runeLen-2))
  if bytesRead + 1 != runeLen:
    raise newException(IOError, "Unexpected end of file")
  s.readBuf.runeAt(0)

proc readRune*(s): Rune =
  if s.peekBuf.len > 0: s.peekBuf.popFirst()
  else: doReadRune(s)

proc peekRune*(s; lookahead: Natural = 1): Rune =
  assert(lookahead >= 1)
  while lookahead > s.peekBuf.len:
    s.peekBuf.addLast(doReadRune(s))
  s.peekBuf[lookahead-1]

proc close*(s) =
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
    scanner: UnicodeScanner
    line, column: Natural

  TokeniserError* = object of IOError


proc `==`*(a, b: Token): bool =
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

let forbiddenUnquotedStringRunes = @[
  Rune('$'), Rune('"'), Rune('{'), Rune('}'), Rune('['), Rune(']'), Rune(':'),
  Rune('='), Rune(','), Rune('+'), Rune('#'), Rune('`'), Rune('^'), Rune('?'),
  Rune('!'), Rune('@'), Rune('*'), Rune('&'), Rune('\\')
]


using t: var Tokeniser

proc initTokeniser(stream: Stream): Tokeniser =
  result.scanner = initUnicodeScanner(stream)
  result.line = 1
  result.column = 0


proc raiseTokeniserError(t; msg, details: string,
                         line = t.line, column = t.column) {.noReturn.} =
  raise newException(TokeniserError,
    fmt"{msg} at line {line}, column: {column}: {details}"
  )

proc readRune(t): Rune =
  inc(t.column)
  t.scanner.readRune()

proc readEscape(t; line, col: Natural): Rune =
  let rune = t.readRune()
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
    let hexStr = $t.readRune() & $t.readRune() & $t.readRune() & $t.readRune()
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

proc readQuotedString(t; line, col: Natural): Token =
  var str = ""
  let rune = t.readRune()

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

  Token(kind: tkString, str: str, line: line, column: col)


proc readUnquotedStringOrBooleanOrNull(t; rune: Rune,
                                       line, col: Natural): Token =
  var str = ""
  var rune = rune

  while true:
    str &= rune
    case str
    of "true":  return Token(kind: tkTrue,  line: line, column: col)
    of "false": return Token(kind: tkFalse, line: line, column: col)
    of "null":  return Token(kind: tkNull,  line: line, column: col)
    else:
      rune = t.scanner.peekRune()
      if rune in whitespaceRunes or
         rune in forbiddenUnquotedStringRunes: break
      else:
        rune = t.readRune()

  Token(kind: tkString, str: str, line: line, column: col)



proc next(t): Token =
  var rune = t.readRune()
  while rune in whitespaceRunes:
    rune = t.readRune()

  case rune
  of Rune('{'): Token(kind: tkLeftBrace,    line: t.line, column: t.column)
  of Rune('}'): Token(kind: tkRightBrace,   line: t.line, column: t.column)
  of Rune('['): Token(kind: tkLeftBracket,  line: t.line, column: t.column)
  of Rune(']'): Token(kind: tkRightBracket, line: t.line, column: t.column)
  of Rune(','): Token(kind: tkComma,        line: t.line, column: t.column)
  of Rune(':'): Token(kind: tkColon,        line: t.line, column: t.column)
  of Rune('='): Token(kind: tkEquals,       line: t.line, column: t.column)

  of Rune('\n'):
    inc(t.line)
    t.column = 0
    Token(kind: tkNewLine, line: t.line, column: t.column)

#  of Rune('0')..Rune('9'), Rune('-'): t.readNumber()

  of Rune('"'): t.readQuotedString(t.line, t.column)

  else:
    t.readUnquotedStringOrBooleanOrNull(rune, t.line, t.column)

# }}}

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
    assert s.readRune() == rune1
    assert s.readRune() == rune2
    assert s.readRune() == rune3
    assert s.readRune() == rune4
    assert s.readRune() == rune5

    try:
      discard s.readRune()
      assert false
    except IOError:
      discard

  block: # peek test
    var s = initUnicodeScanner(newStringStream(testString))
    assert s.peekRune()  == rune1
    assert s.peekRune()  == rune1
    assert s.readRune()  == rune1

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

    assert s.readRune()  == rune2
    assert s.readRune()  == rune3
    assert s.readRune()  == rune4
    assert s.readRune()  == rune5

    try:
      discard s.peekRune()
      assert false
    except IOError:
      discard

  block: # tokeniser test 1
    let testString = "{foo:bar}"
    var s = initTokeniser(newStringStream(testString))

    assert s.next() == Token(kind: tkLeftBrace, line: 1, column: 1)
    assert s.next() == Token(kind: tkString, str: "foo", line: 1, column: 2)
    assert s.next() == Token(kind: tkColon, line: 1, column: 5)
    assert s.next() == Token(kind: tkString, str: "bar", line: 1, column: 6)
    assert s.next() == Token(kind: tkRightBrace, line: 1, column: 9)

  block: # tokeniser test 2
    let testString = """{
      array: [a, b]
      "quoted": null
      "concat": falseSTRING
    }
    """
    var s = initTokeniser(newStringStream(testString))


# vim: et:ts=2:sw=2:fdm=marker
