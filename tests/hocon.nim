import std/streams
import std/strutils
import std/tables
import std/unicode
import std/unittest

import utils/hocon


proc `==`*(a, b: Token): bool =
  if a.kind != b.kind: return false
  case a.kind
  of tkString: a.str == b.str
  of tkNumber: a.num == b.num
  else: true

proc printTree(node: HoconNode, depth: int = 0) =
  let indent = " ".repeat(depth * 2)
  case node.kind
  of hnkArray:
    echo ""
    for val in node.elems:
      stdout.write indent
      printTree(val, depth+1)
  of hnkObject:
    echo ""
    for key, val in node.fields:
      stdout.write indent & key & ": "
      printTree(val, depth+1)
  of hnkNull:   echo "null"
  of hnkString: echo "\"" & $node.str & "\""
  of hnkNumber: echo $node.num
  of hnkBool:   echo $node.bool

let testString = "\u0024\u00a2\u0939\u20ac\ud5cc"
# byteLen            1     2     3     3     3
# byteOffs           0     1     3     6     9


suite "Hocon":
  let
    rune1 = Rune(0x0024)
    rune2 = Rune(0x00a2)
    rune3 = Rune(0x0939)
    rune4 = Rune(0x20ac)
    rune5 = Rune(0xd5cc)

  test "scanner test - read":
    var s = initUnicodeScanner(newStringStream(testString))
    assert s.eatRune == rune1
    assert s.eatRune == rune2
    assert s.eatRune == rune3
    assert s.eatRune == rune4
    assert s.eatRune == rune5

    try:
      discard s.eatRune
      assert false
    except IOError:
      discard

  test "scanner test - peek":
    var s = initUnicodeScanner(newStringStream(testString))
    assert s.peekRune  == rune1
    assert s.peekRune  == rune1
    assert s.eatRune  == rune1

    assert s.peekRune  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune(2) == rune3
    assert s.peekRune(3) == rune4
    assert s.peekRune(4) == rune5
    assert s.peekRune(4) == rune5
    assert s.peekRune  == rune2
    assert s.peekRune(2) == rune3
    assert s.peekRune(3) == rune4
    assert s.peekRune(4) == rune5

    try:
      discard s.peekRune(5)
      assert false
    except IOError:
      discard

    assert s.eatRune  == rune2
    assert s.eatRune  == rune3
    assert s.eatRune  == rune4
    assert s.eatRune  == rune5

    try:
      discard s.peekRune
      assert false
    except IOError:
      discard

  test "tokeniser test - simple":
    let testString = "{foo:bar}"
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken == Token(kind: tkLeftBrace, line: 1, column: 1)
    assert t.eatToken == Token(kind: tkString, str: "foo", line: 1, column: 2)
    assert t.eatToken == Token(kind: tkColon, line: 1, column: 5)
    assert t.eatToken == Token(kind: tkString, str: "bar", line: 1, column: 6)
    assert t.eatToken == Token(kind: tkRightBrace, line: 1, column: 9)

  test "tokeniser test - strings":
    let testString = """
"C:\\AUTOEXEC.BAT"
"""
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken == Token(kind: tkString, str: "C:\\AUTOEXEC.BAT", line: 1, column: 1)

  test "tokeniser test - booleans & null":
    let testString = """
{
  true_ = 1
  false2 = 2
  nulltrue = 3
  falsenull = 4
}
"""
    var t = initTokeniser(newStringStream(testString))

    # TODO
#    assert t.eatToken == Token(kind: tkLeftBrace, line: 1, column: 1)

#    assert t.eatToken == Token(kind: tkNewline, line: 1, column: 2)
#    assert t.eatToken == Token(kind: tkString, str: "true_", line: 2, column: 3)
#    assert t.eatToken == Token(kind: tkEquals, line: 2, column: 9)
#    assert t.eatToken == Token(kind: tkNumber, num: "1", line: 2, column: 11)
#    assert t.eatToken == Token(kind: tkNewline, line: 1, column: 12)

  test "tokeniser test - complex":
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

    assert t.eatToken == Token(kind: tkLeftBrace, line: 1, column: 1)
    assert t.eatToken == Token(kind: tkNewline, line: 1, column: 2)

    assert t.eatToken == Token(kind: tkString, str: "array", line: 2, column: 3)
    assert t.eatToken == Token(kind: tkColon, line: 2, column: 8)
    assert t.eatToken == Token(kind: tkLeftBracket, line: 2, column: 10)
    assert t.eatToken == Token(kind: tkString, str: "a", line: 2, column: 11)
    assert t.eatToken == Token(kind: tkComma, line: 2, column: 12)
    assert t.eatToken == Token(kind: tkString, str: "b", line: 2, column: 14)
    assert t.eatToken == Token(kind: tkRightBracket, line: 2, column: 15)
    assert t.eatToken == Token(kind: tkNewline, line: 2, column: 16)

    assert t.eatToken == Token(kind: tkString, str: "quoted", line: 3, column: 3)
    assert t.eatToken == Token(kind: tkColon, line: 3, column: 11)
    assert t.eatToken == Token(kind: tkNull, line: 3, column: 13)
    assert t.eatToken == Token(kind: tkComma, line: 3, column: 17)
    assert t.eatToken == Token(kind: tkNewline, line: 3, column: 18)

    assert t.eatToken == Token(kind: tkString, str: "t", line: 4, column: 3)
    assert t.eatToken == Token(kind: tkEquals, line: 4, column: 5)
    assert t.eatToken == Token(kind: tkTrue, line: 4, column: 7)
    assert t.eatToken == Token(kind: tkNewline, line: 4, column: 11)

    assert t.eatToken == Token(kind: tkString, str: "f", line: 5, column: 3)
    assert t.eatToken == Token(kind: tkEquals, line: 5, column: 5)
    assert t.eatToken == Token(kind: tkFalse, line: 5, column: 7)
    assert t.eatToken == Token(kind: tkNewline, line: 5, column: 12)
    assert t.eatToken == Token(kind: tkNewline, line: 6, column: 1)

    assert t.eatToken == Token(kind: tkString, str: "concat", line: 7, column: 3)
    assert t.eatToken == Token(kind: tkColon, line: 7, column: 11)
    assert t.eatToken == Token(kind: tkString, str: "falseSTRING", line: 7, column: 12)
    assert t.eatToken == Token(kind: tkNewline, line: 7, column: 23)

    assert t.eatToken == Token(kind: tkRightBrace, line: 8, column: 1)

  test "tokeniser test - numbers":
    let testString = """
0 01 1 -1
1. 1.0123 .4
1e5 00e5 1e-5 1e04 -1.e-005
1.e-5 1.234e-5
"""
    var t = initTokeniser(newStringStream(testString))

    assert t.eatToken == Token(kind: tkNumber, num: "0", line: 1, column: 1)
    assert t.eatToken == Token(kind: tkNumber, num: "01", line: 1, column: 3)
    assert t.eatToken == Token(kind: tkNumber, num: "1", line: 1, column: 6)
    assert t.eatToken == Token(kind: tkNumber, num: "-1", line: 1, column: 8)
    assert t.eatToken == Token(kind: tkNewline, line: 1, column: 10)

    assert t.eatToken == Token(kind: tkNumber, num: "1.", line: 2, column: 1)
    assert t.eatToken == Token(kind: tkNumber, num: "1.0123", line: 2, column: 4)
    assert t.eatToken == Token(kind: tkNumber, num: ".4", line: 2, column: 11)
    assert t.eatToken == Token(kind: tkNewline, line: 2, column: 13)

    assert t.eatToken == Token(kind: tkNumber, num: "1e5", line: 3, column: 1)
    assert t.eatToken == Token(kind: tkNumber, num: "00e5", line: 3, column: 5)
    assert t.eatToken == Token(kind: tkNumber, num: "1e-5", line: 3, column: 10)
    assert t.eatToken == Token(kind: tkNumber, num: "1e04", line: 3, column: 15)
    assert t.eatToken == Token(kind: tkNumber, num: "-1.e-005", line: 3, column: 20)
    assert t.eatToken == Token(kind: tkNewline, line: 3, column: 28)

    assert t.eatToken == Token(kind: tkNumber, num: "1.e-5", line: 4, column: 1)
    assert t.eatToken == Token(kind: tkNumber, num: "1.234e-5", line: 4, column: 7)
    assert t.eatToken == Token(kind: tkNewline, line: 4, column: 15)

  test "equality test":
    let n1 = HoconNode(kind: hnkBool, bool: true)
    assert n1 == n1.deepCopy

    let n2 = HoconNode(kind: hnkString, str: "foo")
    assert n2 == n2.deepCopy

    let n3 = HoconNode(kind: hnkNull)
    assert n3 == n3.deepCopy

    let n4 = HoconNode(kind: hnkNumber, num: 123.456)
    assert n4 == n4.deepCopy

    var arr = newHoconArray()
    arr.elems.add(n1)
    arr.elems.add(n2)
    arr.elems.add(n3)
    assert arr == arr.deepCopy

    var obj = newHoconObject()
    obj.set("a", true)
    obj.set("b", 42)
    obj.set("c", "foo")
    assert obj == obj.deepCopy

    var obj2 = newHoconObject()
    obj.set("o2", obj.deepCopy)
    obj.set("a", arr.deepCopy)
    assert obj2 == obj2.deepCopy

  test "parser test":
    let testString = """
{
  a {
    b = "c"
    aa {
      foo = false
    }
    d = 5
    e = [1,2,3]
  }
  b = 123
}
"""

    var p = initHoconParser(newStringStream(testString))
    let root = p.parse
#    printTree(root)

    block:
      let ab  = root.get("a.b")
      assert ab == HoconNode(kind: hnkString, str: "c")

      let foo = root.get("a.aa.foo")
      assert foo == HoconNode(kind: hnkBool, bool: false)

      let d   = root.get("a.d")
      assert d == HoconNode(kind: hnkNumber, num: 5.0)

      let e0  = root.get("a.e.0")
      assert e0 == HoconNode(kind: hnkNumber, num: 1.0)

      let e1  = root.get("a.e.1")
      assert e1 == HoconNode(kind: hnkNumber, num: 2.0)

      let e2  = root.get("a.e.2")
      assert e2 == HoconNode(kind: hnkNumber, num: 3.0)

      let b   = root.get("b")
      assert b == HoconNode(kind: hnkNumber, num: 123.0)

    block:
      let ab  = root.getString("a.b")
      assert ab == "c"

      let foo = root.getBool("a.aa.foo")
      assert foo == false

      let d   = root.getNatural("a.d")
      assert d == 5

      let e0  = root.getFloat("a.e.0")
      assert e0 == 1.0

      let e1  = root.getInt("a.e.1")
      assert e1 == 2

      let e2  = root.getFloat("a.e.2")
      assert e2 == 3.0

      let b   = root.getString("b")
      assert b == "123.0"

  block:
    let testString = """

objA { # comment }=;./23!@#//##{
  foo = "fooval"//blah
  # line comment
  // line comment
  obj2
  {
    arr = [//
      1, 2#
      3#
    ]#
    //}
    obj3{a:"b"}
    key1 = true, key2 = null
    obj4{c:"d"}}
  bar
    =1234.5
    obj5 {"x"=y }
}
objB { b: false }
c = "d"
"""
    var p = initHoconParser(newStringStream(testString))
    let root = p.parse

#    echo '-'.repeat(40)
#    printTree(root)

    var st = newStringStream()
#    echo '-'.repeat(40)
    root.write(st)
#    echo st.data

  test "setter test":
    var obj = newHoconObject()
    obj.set("a.b.c1.d1", true)
    obj.set("a.b.c1.d2", 42)
    obj.set("a.b.c2.0", "x")
    obj.set("a.b.c2.2", "z")
    obj.set("a.b.c2.1", "y")
    obj.set("a.b.c2.5.2.foo.1", "bar")

    assert obj.getBool("a.b.c1.d1") == true
    assert obj.getInt("a.b.c1.d2") == 42
    assert obj.getString("a.b.c2.0") == "x"
    assert obj.getString("a.b.c2.2") == "z"
    assert obj.getString("a.b.c2.1") == "y"
    assert obj.getString("a.b.c2.5.2.foo.1") == "bar"

    var st = newStringStream()
#    echo '-'.repeat(40)
    obj.write(st)
#    echo st.data

  test "merge test":
    let srcObj = """
{
  a = {
    b = {
      c = 5
    }
    d = "foo"
    e = [1,2,3]
  }
  f = [
    {
      g = 11
      h = 12
    },
    42
  ]
  i = "end"
  j = false
}
"""
    var p = initHoconParser(newStringStream(srcObj))
    let src = p.parse

    block:
      var st = newStringStream()
#      echo '-'.repeat(40)
      src.write(st)
#      echo st.data

    let destObj = """
{
  a = {
    b = {
      x1 = 5
    }
    x2 = true
  }
  f = ["A", "B"]
  x = "X"
  y = "Y"
  j = [true, false]
}
"""
    p = initHoconParser(newStringStream(destObj))
    let dest = p.parse

    dest.merge(src)

    block:
      var st = newStringStream()
#      echo '-'.repeat(40)
      dest.write(st)
#      echo st.data


