import unicode
import streams

# {{{ UnicodeScanner

type
  UnicodeScanner = object
    stream:  Stream
    readBuf: string
    peekBuf: seq[Rune]


using s: var UnicodeScanner

proc initScanner(stream: Stream, maxPeek: Natural = 1): UnicodeScanner =
  assert(maxPeek >= 1)
  result.stream = stream
  result.readBuf = newStringOfCap(4)
  result.peekBuf = newSeqOfCap[Rune](maxPeek)
  for i in 0..<maxPeek:
    result.peekBuf.add(Rune(0))

proc readRune(s): Rune =
  s.readBuf[0] = cast[char](s.stream.readInt8())
  let len = s.readBuf.runeLenAt(0)
  let bytesRead = s.stream.readDataStr(s.readBuf, 1..(1 + len-1))
#  if bytesRead != len: error
  result = s.readBuf.runeAt(0)

proc peekRune(s; lookahead: Natural = 1): Rune =

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

# vim: et:ts=2:sw=2:fdm=marker
