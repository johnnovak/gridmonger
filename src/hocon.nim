import deques
import unicode
import streams
import strformat

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

proc readRune(s): Rune =
#  if s.peekBuf.len > 0:
#    s.peekBuf.popFirst()
#  else:
    s.readBuf[0] = cast[char](s.stream.readUint8())
    echo fmt"buf: {cast[uint8](s.readBuf[0]):02x}"

    let len = s.readBuf.runeLenAt(0)
    echo "len ", len
    let bytesRead = s.stream.readDataStr(s.readBuf, 1..(1 + len-1))
    echo fmt"buf: {cast[uint8](s.readBuf[0]):02x} {cast[uint8](s.readBuf[1]):02x} {cast[uint8](s.readBuf[2]):02x} {cast[uint8](s.readBuf[3]):02x}"
    echo ""
  #  if bytesRead != len:
  #    raiseError()
    let r = s.readBuf.runeAt(0)
    echo r
    r

proc peekRune(s; lookahead: Natural = 1): Rune =
  assert(lookahead >= 1)
  while lookahead > s.peekBuf.len:
    s.peekBuf.addLast(readRune(s))
  s.peekBuf[lookahead-1]

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
    of tkNumber: num: float64
    else: discard

  Tokeniser = object
    scanner: UnicodeScanner
    line, column: Natural

# }}}

when isMainModule:
  let a = initDeque[Rune]()
  let testString = "\u0024\u00a2\u0939\u20ac\ud5cc\u10348"
  # byteLen            1     2     3     3     3     4
  # byteOffs           0     1     3     6     9    12
  
#[
  echo testString.runeLenAt(0)
  echo testString.runeLenAt(1)
  echo testString.runeLenAt(3)
  echo testString.runeLenAt(6)
  echo testString.runeLenAt(9)
  echo testString.runeLenAt(12)

  echo "\u1034\u0008".runeLenAt(0)
]#

  var s = initUnicodeScanner(newStringStream(testString))
  assert s.readRune() == Rune(0x0024)
  assert s.readRune() == Rune(0x00a2)

  assert s.readRune() == Rune(0x0939)
  assert s.readRune() == Rune(0x20ac)
  assert s.readRune() == Rune(0xd5cc)
  assert s.readRune() == Rune(0x10348)

# vim: et:ts=2:sw=2:fdm=marker
