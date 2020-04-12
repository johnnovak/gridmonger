import hashes
import tables

const DefaultInitialSize = 64

type BiTable*[A, B] = object
  keyToVal: Table[A, B]
  valToKey: Table[B, A]

proc initBiTable*[A, B](
    initialSize: Natural = DefaultInitialSize): BiTable[A, B] =
  result.keyToVal = initTable[A, B](initialSize)
  result.valToKey = initTable[B, A](initialSize)

proc len*[A, B](t: BiTable[A, B]): Natural =
  t.keyToVal.len

proc hasKey*[A, B](t: BiTable[A, B], key: A): bool =
  t.keyToVal.hasKey(key)

proc hasVal*[A, B](t: BiTable[A, B], val: B): bool=
  t.valToKey.hasKey(val)

proc getValByKey*[A, B](t: BiTable[A, B], key: A): B =
  t.keyToVal[key]

proc getKeyByVal*[A, B](t: BiTable[A, B], val: B): A =
  t.valToKey[val]

proc `[]`*[A, B](t: var BiTable[A, B], key: A): B =
  t.getValByKey(key)

proc `[]=`*[A, B](t: var BiTable[A, B], key: A, val: B) =
  t.keyToVal[key] = val
  t.valToKey[val] = key

proc delByKey*[A, B](t: var BiTable[A, B], key: A) =
  if key in t.keyToVal:
    let val = t.keyToVal[key]
    t.keyToVal.del(key)
    t.valToKey.del(val)

proc delByVal*[A, B](t: var BiTable[A, B], val: B) =
  if val in t.valToKey:
    let key = t.valToKey[val]
    t.valToKey.del(val)
    t.keyToVal.del(key)


when isMainModule:
  var t = initBiTable[int, string]()
  assert t.len == 0
  assert t.hasKey(1) == false

  t[1] = "cat"
  assert t.hasKey(1) == true
  assert t.len == 1
  assert t[1] == "cat"
  assert t.getValByKey(1) == "cat"
  assert t.getKeyByVal("cat") == 1

  t[2] = "dog"
  assert t.len == 2
  assert t[2] == "dog"
  assert t.getValByKey(2) == "dog"
  assert t.getKeyByVal("dog") == 2

  try:
    discard t[42]
    assert false
  except KeyError as e:
    assert true

  try:
    discard t.getValByKey(42)
    assert false
  except KeyError as e:
    assert true

  try:
    discard t.getKeyByVal("lion")
    assert false
  except KeyError as e:
    assert true

  t.delByKey(42)
  assert t.len == 2

  t.delByKey(2)
  assert t.len == 1
  assert t.hasKey(2) == false
  assert t.hasVal("dog") == false

  t.delByVal("lion")
  assert t.len == 1

  t.delByVal("cat")
  assert t.len == 0
  assert t.hasKey(1) == false
  assert t.hasVal("cat") == false

