import std/options

import koi
import nanovg

import appcontext
import common
import domain/all
import ui/all
import utils/all
import view


using a: var AppContext

# {{{ renderIndexedNote()
proc renderIndexedNote(x, y: float; size: float; bgColor, fgColor: Color;
                       shape: NoteBackgroundShape; index: Natural; a) =
  alias(vg, a.vg)

  vg.fillColor(bgColor)
  vg.beginPath

  case shape
  of nbsCircle:
    vg.circle(x + size*0.5, y + size*0.5, size*0.38)
  of nbsRectangle:
    let pad = 4.0
    vg.rect(x+pad, y+pad, size-pad*2, size-pad*2)

  vg.fill

  var fontSizeFactor = if   index <  10: 0.4
                       elif index < 100: 0.37
                       else:             0.32

  vg.setFont(size*fontSizeFactor, "sans-bold")
  vg.fillColor(fgColor)
  vg.textAlign(haCenter, vaMiddle)

  discard vg.text(x + size*0.51, y + size*0.54, $index)

# }}}
# {{{ renderNoteMarker*()
proc renderNoteMarker*(x, y, w, h: float, note: Annotation, textColor: Color,
                      indexedNoteSize: float = 36.0; a) =
  alias(vg, a.vg)

  let s = a.theme.currentNotePaneTheme

  vg.save

  case note.kind
  of akIndexed:
    renderIndexedNote(x, y-2, size=indexedNoteSize,
                      bgColor=s.indexBackgroundColor[note.indexColor],
                      fgColor=s.indexColor,
                      a.theme.levelTheme.notebackgroundShape,
                      note.index, a)

  of akCustomId:
    vg.fillColor(textColor)
    vg.setFont(18, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+18, y+8, note.customId)

  of akIcon:
    vg.fillColor(textColor)
    vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+20, y+7, NoteIcons[note.icon])

  of akComment:
    vg.fillColor(textColor)
    vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+20, y+8, IconComment)

  of akLabel: discard

  vg.restore

# }}}
# {{{ renderCurrentNotePane*()
proc renderCurrentNotePane*(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let
    l = currLevel(a)
    cur = a.ui.cursor
    note = l.getNote(cur.row, cur.col)

  if note.isSome and not (a.ui.editMode in {emPastePreview, emNudgePreview}):
    let note = note.get
    if note.text == "" or note.kind == akLabel: return

    renderNoteMarker(x, y, w, h, note,
                     textColor=a.theme.currentNotePaneTheme.textColor, a=a)

    var text = note.text
    const TextIndent = 44
    koi.textArea(x+TextIndent, y-1, w-TextIndent, h, text, disabled=true,
                 style=a.theme.noteTextAreaStyle)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
