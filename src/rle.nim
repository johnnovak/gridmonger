const Escape = 0xff

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

  result = true

  if e.prevData == Escape or e.runLength > 3:
    if e.bufIdx > e.buf.len-3: return false
    e.buf[e.bufIdx  ] = Escape
    e.buf[e.bufIdx+1] = (e.runLength-1).byte
    e.buf[e.bufIdx+2] = e.prevData
    inc(e.bufIdx, 3)
  else:
    for _ in 1..e.runLength:
      if e.bufIdx >= e.buf.len: return false
      e.buf[e.bufIdx] = e.prevData
      inc(e.bufIdx)
  e.runLength = 1


proc encode*(e; data: byte): bool =
  result = true

  if e.first:
    e.prevData = data
    e.first = false

  if data == e.prevData:
    inc(e.runLength)
    if e.runLength == 256:
      if not e.flush(): return false
  else:
    if not e.flush(): return false

  e.prevData = data


proc encodedLength*(e): Positive = e.bufIdx

# }}}

# {{{ Tests
when isMainModule:
  block:
    let s = "AAAABCDDDE"
    var e: RunLengthEncoder
    initRunLengthEncoder(e, s.len)

    for d in s:
      discard e.encode(d.byte)
    discard e.flush()

    assert e.buf[0] == 255
    assert e.buf[1] == 3
    assert e.buf[2] == 'A'.byte

    assert e.buf[3] == 'B'.byte
    assert e.buf[4] == 'C'.byte

    assert e.buf[5] == 'D'.byte
    assert e.buf[6] == 'D'.byte
    assert e.buf[7] == 'D'.byte

    assert e.buf[8] == 'E'.byte

# }}}

# vim: et:ts=2:sw=2:fdm=marker
