import std/options

# {{{ RLE encoder

type
  RunLengthEncoder* = object
    prevData:  byte
    first:     bool
    runLength: Natural
    buf*:      seq[byte]
    bufIdx:    Natural

using e: var RunLengthEncoder

proc initRunLengthEncoder*(e; bufSize: Positive) =
  e.first     = true
  e.runLength = 0
  e.bufIdx    = 0
  if e.buf.len < bufSize:
    e.buf = newSeq[byte](bufSize)


proc flush*(e): bool =
  assert e.runLength <= 0x80

  if e.prevData > 0x7f or e.runLength > 2:
    if e.bufIdx > e.buf.len-2: return false
    e.buf[e.bufIdx  ] = 0x80 or (e.runLength-1).byte
    e.buf[e.bufIdx+1] = e.prevData
    inc(e.bufIdx, 2)
  else:
    for _ in 1..e.runLength:
      if e.bufIdx >= e.buf.len: return false
      e.buf[e.bufIdx] = e.prevData
      inc(e.bufIdx)
  e.runLength = 1
  result = true


proc encode*(e; data: byte): bool =
  result = true

  if e.first:
    e.prevData = data
    e.first = false

  if data == e.prevData:
    if e.runLength == 0x80:
      result = e.flush
    else:
      inc(e.runLength)
  else:
    result = e.flush

  e.prevData = data


proc encodedLength*(e): Positive = e.bufIdx

# }}}
# {{{ RLE decoder

type
  RunLengthDecoder* = object
    buf:       seq[byte]
    bufIdx:    Natural
    data:      byte
    runLength: Natural

using d: var RunLengthDecoder

proc initRunLengthDecoder*(d; buf: seq[byte]) =
  d.buf = buf
  d.bufIdx = 0
  d.runLength = 0

proc decode*(d): Option[byte] =
  if d.runLength > 0:
    dec(d.runLength)
    return d.data.some
  else:
    if d.bufIdx > d.buf.high: return byte.none
    let data = d.buf[d.bufIdx]
    inc(d.bufIdx)
    if data <= 0x7f: return data.some
    else:
      if d.bufIdx > d.buf.high: return byte.none
      d.runLength = data and 0x7f
      d.data = d.buf[d.bufIdx]
      inc(d.bufIdx)
      return d.data.some

# }}}

# {{{ Tests

# vim: et:ts=2:sw=2:fdm=marker
