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
  assert(e.runLength <= 0x80)

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
      result = e.flush()
    else:
      inc(e.runLength)
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
when isMainModule:
  import strformat

  var e: RunLengthEncoder
  var d: RunLengthDecoder

  # {{{ simple case
  block:
    # encode
    let s = "AAAABCDDDEFF"
    initRunLengthEncoder(e, s.len)

    for d in s:
      discard e.encode(d.byte)
    discard e.flush()

    assert e.buf[0] == 0x83
    assert e.buf[1] == 'A'.byte

    assert e.buf[2] == 'B'.byte
    assert e.buf[3] == 'C'.byte

    assert e.buf[4] == 0x82
    assert e.buf[5] == 'D'.byte

    assert e.buf[6] == 'E'.byte
    assert e.buf[7] == 'F'.byte
    assert e.buf[8] == 'F'.byte

    # decode
    e.buf.setLen(e.encodedLength)
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
  # {{{ repeats
  block:
    template fill(e: RunLengthEncoder, len: Natural) =
      initRunLengthEncoder(e, len)

      for i in 1..len:
        discard e.encode(5)
      discard e.flush()

    template verify(e: RunLengthEncoder, d: RunLengthDecoder, len: Natural) =
      e.buf.setLen(e.encodedLength)
      initRunLengthDecoder(d, e.buf)

      for i in 1..len:
        assert d.decode().get == 5
      assert d.decode() == byte.none

    block:
      let len = 127
      fill(e, len)

      assert e.encodedLength == 2
      assert e.buf[0] == 0xfe
      assert e.buf[1] == 5
      assert e.buf[2] == 0

      verify(e, d, len)

    block:
      let len = 128
      fill(e, len)

      assert e.encodedLength == 2
      assert e.buf[0] == 0xff
      assert e.buf[1] == 5
      assert e.buf[2] == 0

      verify(e, d, len)

    block:
      let len = 129
      fill(e, len)

      assert e.encodedLength == 3
      assert e.buf[0] == 0xff
      assert e.buf[1] == 5
      assert e.buf[2] == 5
      assert e.buf[3] == 0

      verify(e, d, len)

    block:
      let len = 300
      fill(e, len)

      assert e.encodedLength == 6
      assert e.buf[0] == 0xff
      assert e.buf[1] == 5
      assert e.buf[2] == 0xff
      assert e.buf[3] == 5
      assert e.buf[4] == 0x80 + 43
      assert e.buf[5] == 5
      assert e.buf[6] == 0

      verify(e, d, len)

  # }}}
  # {{{ escape handling
  block:
    template fill(e: RunLengthEncoder, repeats: Natural) =
      initRunLengthEncoder(e, 1_000_000)

      for i in 0..255:
        for _ in 1..repeats:
          discard e.encode(i.byte)
      discard e.flush()

    template verify(e: RunLengthEncoder, d: RunLengthDecoder,
                    repeats: Natural) =
      e.buf.setLen(e.encodedLength)
      initRunLengthDecoder(d, e.buf)

      for i in 0..255:
        for _ in 1..repeats:
          assert d.decode().get == i.byte
      assert d.decode() == byte.none

    fill(e, 1)
    assert e.encodedLength == 128 + 128*2
    verify(e, d, 1)

    fill(e, 2)
    assert e.encodedLength == 128*2 + 128*2
    verify(e, d, 2)

    fill(e, 3)
    assert e.encodedLength == 128*2 + 128*2
    verify(e, d, 3)

    fill(e, 4)
    assert e.encodedLength == 128*2 + 128*2
    verify(e, d, 4)

  # }}}

# }}}

# vim: et:ts=2:sw=2:fdm=marker
