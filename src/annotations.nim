import std/algorithm
import std/options
import std/tables

import common
import rect


using a: Annotations

# {{{ newAnnotations*()
proc newAnnotations*(rows, cols: Natural): Annotations =
  var a = new Annotations
  a.rows = rows
  a.cols = cols
  a.annotations = initOrderedTable[Natural, Annotation]()
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
  (r,c)

# }}}

# {{{ isLabel()
func isLabel(a: Annotation): bool = a.kind == akLabel

# }}}
# {{{ isNote()
func isNote(a: Annotation): bool = not a.isLabel

# }}}

# {{{ hasAnnotation*()
proc hasAnnotation*(a; r,c: Natural): bool {.inline.} =
  let key = a.coordsToKey(r,c)
  a.annotations.hasKey(key)

# }}}
# {{{ getAnnotation*()
proc getAnnotation*(a; r,c: Natural): Option[Annotation] =
  let key = a.coordsToKey(r,c)
  if a.annotations.hasKey(key):
    result = a.annotations[key].some

# }}}
# {{{ setAnnotation*()
proc setAnnotation*(a; r,c: Natural, annot: Annotation) =
  let key = a.coordsToKey(r,c)
  a.annotations[key] = annot

# }}}
# {{{ delAnnotation*()
proc delAnnotation*(a; r,c: Natural) =
  let key = a.coordsToKey(r,c)
  if a.annotations.hasKey(key):
    a.annotations.del(key)

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
  var toDel: seq[(Natural, Natural)]

  for r,c, _ in a.allAnnotations:
    if rect.contains(r,c):
      toDel.add((r,c))

  for (r,c) in toDel: a.delAnnotation(r,c)

# }}}

# {{{ hasNote*()
proc hasNote*(a; r,c: Natural): bool =
  let a = a.getAnnotation(r,c)
  result = a.isSome and a.get.isNote

# }}}
# {{{ getNote*()
proc getNote*(a; r,c: Natural): Option[Annotation] =
  let a = a.getAnnotation(r,c)
  if a.isSome:
    if a.get.isNote: result = a

# }}}
# {{{ allNotes*()
iterator allNotes*(a): tuple[row, col: Natural, annotation: Annotation] =
  for k, annot in a.annotations:
    if annot.isNote:
      let (r,c) = a.keyToCoords(k)
      yield (r,c, annot)
    else:
      continue

# }}}
# {{{ reindexNotes*()
proc reindexNotes*(a) =
  var keys: seq[int] = @[]
  for k, n in a.annotations:
    if n.kind == akIndexed:
      keys.add(k)

  sort(keys)
  for i, k in keys:
    a.annotations[k].index = i+1

# }}}

# {{{ hasLabel*()
proc hasLabel*(a; r,c: Natural): bool =
  let a = a.getAnnotation(r,c)
  result = a.isSome and a.get.isLabel

# }}}
# {{{ getLabel*()
proc getLabel*(a; r,c: Natural): Option[Annotation] =
  let a = a.getAnnotation(r,c)
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
  let annot = a.getAnnotation(r,c)
  if annot.isSome:
    let note = annot.get
    if note.kind == akLabel:
      return

    if note.kind != akComment:
      a.delAnnotation(r,c)

    if note.kind != akLabel:
      if note.text == "":
        a.delAnnotation(r,c)
      else:
        let comment = Annotation(kind: akComment, text: note.text)
        a.setAnnotation(r,c, comment)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
