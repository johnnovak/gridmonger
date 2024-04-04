import std/algorithm
import std/options
import std/sugar
import std/tables

import common
import utils/rect


using a: Annotations

# {{{ newAnnotations*()
proc newAnnotations*(rows, cols: Natural): Annotations =
  var a = new Annotations
  a.rows = rows
  a.cols = cols
  a.annotations = initOrderedTable[Natural, Annotation]()

  # Start with dirty until cleared
  a.dirty = true

  result = a

# }}}

# {{{ coordsToKey()
template coordsToKey(a; r,c: Natural): Natural =
  assert r < a.rows
  assert c < a.cols

  (r * a.cols) + c

# }}}
# {{{ keyToCoords()
template keyToCoords(a; k: Natural): tuple[row, col: Natural] =
  let
    w = a.cols
    r = (k div w).Natural
    c = (k mod w).Natural

  assert r < a.rows
  assert c < a.cols

  (r,c)

# }}}

# {{{ `[]*`()
proc `[]`*(a; r,c: Natural): Option[Annotation] =
  let key = a.coordsToKey(r,c)
  if a.annotations.hasKey(key):
    result = a.annotations[key].some

# }}}
# {{{ `[]=*`()
proc `[]=`*(a; r,c: Natural, annot: Annotation) =
  let key = a.coordsToKey(r,c)
  a.annotations[key] = annot
  a.dirty = true

# }}}
# {{{ delAnnotation*()
proc delAnnotation*(a; r,c: Natural) =
  let key = a.coordsToKey(r,c)
  if a.annotations.hasKey(key):
    a.annotations.del(key)
  a.dirty = true

# }}}

# {{{ numAnnotations*()
proc numAnnotations*(a): Natural =
  a.annotations.len

# }}}
# {{{ allAnnotations*()
iterator allAnnotations*(a): tuple[row, col: Natural, annotation: Annotation] =
  for k, annot in a.annotations:
    let (r,c) = a.keyToCoords(k)
    yield (r,c, annot)

# }}}
# {{{ delAnnotations*()
proc delAnnotations*(a; rect: Rect[Natural]) =
  let toDel = collect:
    for r,c, _ in a.allAnnotations:
      if rect.contains(r,c): (r,c)

  for (r,c) in toDel:
    a.delAnnotation(r,c)

# }}}

# {{{ hasNote*()
proc hasNote*(a; r,c: Natural): bool =
  let a = a[r,c]
  result = a.isSome and a.get.isNote

# }}}
# {{{ getNote*()
proc getNote*(a; r,c: Natural): Option[Annotation] =
  let a = a[r,c]
  if a.isSome:
    if a.get.isNote: result = a

# }}}
# {{{ notes*()
iterator notes*(a): tuple[row, col: Natural, annotation: Annotation] =
  for k, annot in a.annotations:
    if annot.isNote:
      let (r,c) = a.keyToCoords(k)
      yield (r,c, annot)
    else:
      continue

# }}}
# {{{ reindexNotes*()
proc reindexNotes*(a) =
  var keys = collect:
    for k, n in a.annotations:
      if n.kind == akIndexed: k

  sort(keys)
  for i, k in keys:
    a.annotations[k].index = i+1

  a.dirty = true

# }}}

# {{{ hasLabel*()
proc hasLabel*(a; r,c: Natural): bool =
  let a = a[r,c]
  result = a.isSome and a.get.isLabel

# }}}
# {{{ getLabel*()
proc getLabel*(a; r,c: Natural): Option[Annotation] =
  let a = a[r,c]
  if a.isSome:
    if a.get.isLabel: result = a

# }}}
# {{{ allLabels*()
iterator allLabels*(a): tuple[row, col: Natural, annotation: Annotation] =
  for k, annot in a.annotations:
    if annot.isLabel:
      let (r,c) = a.keyToCoords(k)
      yield (r,c, annot)
    else:
      continue

# }}}

# {{{ convertNoteToComment*()
proc convertNoteToComment*(a; r,c: Natural) =
  let note = a[r,c]
  if note.isSome:
    let note = note.get
    if note.kind == akLabel:
      return

    if note.kind != akComment:
      a.delAnnotation(r,c)

    if note.kind != akLabel:
      if note.text == "":
        a.delAnnotation(r,c)
      else:
        let comment = Annotation(kind: akComment, text: note.text)
        a[r,c] = comment

# }}}

# vim: et:ts=2:sw=2:fdm=marker
