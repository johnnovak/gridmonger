import options

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
  assert(e.runLength <= 256)

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
    inc(e.runLength)
    if e.runLength == 0x7f:
      result = e.flush()
  else:
    result = e.flush()

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

proc decode(d): Option[byte] =
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
when isMainModule:
  import strformat

  block:
    # encode
    let s = "AAAABCDDDE"
    var e: RunLengthEncoder
    initRunLengthEncoder(e, s.len)

    for d in s:
      discard e.encode(d.byte)
    discard e.flush()

    assert e.buf[0] == 0x83.byte
    assert e.buf[1] == 'A'.byte

    assert e.buf[2] == 'B'.byte
    assert e.buf[3] == 'C'.byte

    assert e.buf[4] == 0x82.byte
    assert e.buf[5] == 'D'.byte

    assert e.buf[6] == 'E'.byte

    # decode
    e.buf.setLen(e.encodedLength)

    var d: RunLengthDecoder
    initRunLengthDecoder(d, e.buf)
    var outbuf = newSeq[byte](s.len)

    var i = 0
    while true:
      let b = d.decode()
      if b.isNone: break
      else:
        outbuf[i] = b.get
        inc(i)

    for i in 0..s.high:
      assert outbuf[i] == s[i].byte

# }}}

# vim: et:ts=2:sw=2:fdm=marker
