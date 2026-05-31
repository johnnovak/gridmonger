# rle — migrated from src/utils/rle.nim
import std/options
import std/strformat
import std/unittest

import utils/rle

suite "RunLengthEncoder/Decoder":
  test "round-trip on assorted patterns":
    var e: RunLengthEncoder
    var d: RunLengthDecoder

    # {{{ simple case
    block:
      # encode
      let s = "AAAABCDDDEFF"
      initRunLengthEncoder(e, s.len)

      for d in s:
        discard e.encode(d.byte)
      discard e.flush

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
        let b = d.decode
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
        discard e.flush

      template verify(e: RunLengthEncoder, d: RunLengthDecoder, len: Natural) =
        e.buf.setLen(e.encodedLength)
        initRunLengthDecoder(d, e.buf)

        for i in 1..len:
          assert d.decode.get == 5
        assert d.decode == byte.none

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
        discard e.flush

      template verify(e: RunLengthEncoder, d: RunLengthDecoder,
                      repeats: Natural) =
        e.buf.setLen(e.encodedLength)
        initRunLengthDecoder(d, e.buf)

        for i in 0..255:
          for _ in 1..repeats:
            assert d.decode.get == i.byte
        assert d.decode == byte.none

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



# vim: et:ts=2:sw=2:fdm=marker
