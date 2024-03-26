import std/options

# TODO
# - use groupStart/groupEnd undo state markers instead of groupWithPrev flag
# - store group name in groupStart
# - unit tests

type
  UndoManager*[S, R] = ref object
    states:        seq[UndoState[S, R]]
    currState:     int
    lastSaveState: int

  ActionProc*[S, R] = proc (s: var S): R

  UndoState[S, R] = object
    action:        ActionProc[S, R]
    undoAction:    ActionProc[S, R]
    groupWithPrev: bool

# {{{ initUndoManager*()
proc initUndoManager*[S, R](m: var UndoManager[S, R]) =
  m.states        = @[]
  m.currState     = 0
  m.lastSaveState = 0

# }}}
# {{{ newUndoManager*()
proc newUndoManager*[S, R](): UndoManager[S, R] =
  result = new UndoManager[S, R]
  initUndoManager(result)

# }}}

# {{{ truncateUndoState*()
proc truncateUndoState*[S, R](m: var UndoManager[S, R]) =
  if m.currState < m.states.high:
    m.states.setLen(m.currState+1)

# }}}
# {{{ storeUndoState*()
proc storeUndoState*[S, R](m: var UndoManager[S, R],
                           action, undoAction: ActionProc[S, R],
                           groupWithPrev = false) =
  if m.states.len == 0:
    m.states.add(UndoState[S, R]())
    m.currState = 0
  else:
    # Discard later states if we're not at the last one
    m.truncateUndoState()

  m.states[m.currState].action = action
  m.states.add(UndoState[S, R](action: nil, undoAction: undoAction,
                               groupWithPrev: groupWithPrev))
  inc(m.currState)

# }}}

# {{{ canUndo*()
proc canUndo*[S, R](m: UndoManager[S, R]): bool =
  m.currState > 0

# }}}
# {{{ undo*()
proc undo*[S, R](m: var UndoManager[S, R], s: var S): R =
  if m.canUndo():
    result = m.states[m.currState].undoAction(s)
    let undoNextState = m.states[m.currState].groupWithPrev
    dec(m.currState)
    if undoNextState:
      discard m.undo(s)

# }}}

# {{{ canRedo*()
proc canRedo*[S, R](m: UndoManager[S, R]): bool =
  m.currState < m.states.high

# }}}
# {{{ redo*()
proc redo*[S, R](m: var UndoManager[S, R], s: var S): R =
  if m.canRedo():
    result = m.states[m.currState].action(s)
    inc(m.currState)
    let redoNextState = m.currState+1 <= m.states.high and
                        m.states[m.currState+1].groupWithPrev
    if redoNextState:
      result = m.redo(s)

# }}}

# {{{ setLastSaveState*()
proc setLastSaveState*[S, R](m: var UndoManager[S, R]) =
  m.lastSaveState = m.currState

# }}}
# {{{ isModified*()
proc isModified*[S, R](m: UndoManager[S, R]): bool =
  m.currState != m.lastSaveState

# }}}

# vim: et:ts=2:sw=2:fdm=marker
