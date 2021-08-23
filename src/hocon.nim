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
    of tkNumber: num: float64
    else: discard

  Tokeniser = object
    scanner: UnicodeScanner
    line, column: Natural

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
    except IOError: discard

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
    except IOError: discard

    assert s.readRune()  == rune2
    assert s.readRune()  == rune3
    assert s.readRune()  == rune4
    assert s.readRune()  == rune5

    try:
      discard s.peekRune()
      assert false
    except IOError: discard


# vim: et:ts=2:sw=2:fdm=marker
