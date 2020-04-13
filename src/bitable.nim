import sugar
import tables


const DefaultInitialSize = 64

type BiTable*[K, V] = object
  keyToVal: Table[K, V]
  valToKey: Table[V, K]

proc initBiTable*[K, V](
    initialSize: Natural = DefaultInitialSize): BiTable[K, V] =
  result.keyToVal = initTable[K, V](initialSize)
  result.valToKey = initTable[V, K](initialSize)

proc len*[K, V](t: BiTable[K, V]): Natural =
  t.keyToVal.len

proc keys*[K, V](t: BiTable[K, V]): seq[K] =
  result = collect(newSeqOfCap(t.keyToVal.len)):
    for k in t.keyToVal.keys(): k

proc values*[K, V](t: BiTable[K, V]): seq[V] =
  result = collect(newSeqOfCap(t.valToKey.len)):
    for k in t.valToKey.keys(): k

proc hasKey*[K, V](t: BiTable[K, V], key: K): bool =
  t.keyToVal.hasKey(key)

proc hasVal*[K, V](t: BiTable[K, V], val: V): bool=
  t.valToKey.hasKey(val)

proc getValByKey*[K, V](t: BiTable[K, V], key: K): V =
  t.keyToVal[key]

proc getKeyByVal*[K, V](t: BiTable[K, V], val: V): K =
  t.valToKey[val]

proc `[]`*[K, V](t: BiTable[K, V], key: K): V =
  t.getValByKey(key)

proc `[]=`*[K, V](t: var BiTable[K, V], key: K, val: V) =
  t.keyToVal[key] = val
  t.valToKey[val] = key

proc delByKey*[K, V](t: var BiTable[K, V], key: K) =
  if key in t.keyToVal:
    let val = t.keyToVal[key]
    t.keyToVal.del(key)
    t.valToKey.del(val)

proc delByVal*[K, V](t: var BiTable[K, V], val: V) =
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

