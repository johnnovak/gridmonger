import tables

const DefaultInitialSize = 64

type SeqMultiTable[A, B] = object
  uniqueValues: bool
  table:        Table[A, seq[B]]

proc initMultiTable*[A, B](
    uniqueValues: bool = false,
    initialSize: Natural = DefaultInitialSize): SeqMultiTable[A, B] =
  result.uniqueValues = uniqueValues
  result.table = initTable[A, seq[B]](initialSize)

proc hasKey*[A, B](t: SeqMultiTable[A, B], key: A): bool =
  t.table.hasKey(key)

proc contains*[A, B](t: SeqMultiTable[A, B], key: A): bool =
  hasKey(t, key)

proc len*[A, B](t: SeqMultiTable[A, B]): Natural =
  for v in t.table.values:
    inc(result, v.len)

proc `[]`[A, B](t: SeqMultiTable[A, B], key: A): seq[B] =
  t.table[key]

proc `[]=`[A, B](t: var SeqMultiTable[A, B], key: A, val: B) =
  if key in t.table:
    var s = t.table[key]
    if not t.uniqueValues or not (val in s): s.add(val)
    t.table[key] = s
  else:
    t.table[key] = @[val]

proc del*[A, B](t: var SeqMultiTable[A, B], key: A, val: B) =
  var s = t.table[key]
  let i = s.find(val)
  if i > -1:
    if s.len == 1:
      t.table.del(key)
    else:
      s.del(i)
      t.table[key] = s

proc delAll*[A, B](t: var SeqMultiTable[A, B], key: A) =
  t.table.del(key)


when isMainModule:
  block:  # non-unique values
    var t = initMultiTable[int, string]()
    assert t.len == 0

    t[1] = "bird"
    assert t[1] == @["bird"]
    t[2] = "cat"
    assert t[2] == @["cat"]
    assert t.len == 2
    assert t.hasKey(1) == true
    assert 2 in t == true

    t[2] = "dog"
    assert t[2] == @["cat", "dog"]
    assert t.len == 3

    t[2] = "dog"
    assert t[2] == @["cat", "dog", "dog"]
    assert t.len == 4
    t.del(1, "bird")
    assert 1 in t == false
    assert t.len == 3

    t.del(2, "cat")
    assert t[2] == @["dog", "dog"]
    assert t.len == 2

    t.del(2, "dog")
    assert t[2] == @["dog"]
    assert t.len == 1

    t[2] = "lion"
    assert t[2] == @["dog", "lion"]
    t.delAll(2)
    assert 2 in t == false
    assert t.len == 0

    try:
      discard t[2]
      assert false
    except KeyError as e:
      assert true

  block:  # non-unique values
    var t = initMultiTable[int, string](uniqueValues=true)
    assert t.len == 0

    t[1] = "cat"
    assert t[1] == @["cat"]
    assert t.len == 1
    assert 1 in t == true

    t[1] = "dog"
    assert t[1] == @["cat", "dog"]
    assert t.len == 2

    t[1] = "dog"
    assert t[1] == @["cat", "dog"]
    assert t.len == 2

    t.del(1, "cat")
    assert t[1] == @["dog"]
    assert t.len == 1

    t.del(1, "dog")
    assert 1 in t == false
    assert t.len == 0

    try:
      discard t[1]
      assert false
    except KeyError as e:
      assert true

