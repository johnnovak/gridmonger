import options


type
  UndoManager*[S] = ref object
    states:        seq[UndoState[S]]
    currState:     int
    lastSaveState: int

  ActionProc*[S] = proc (s: var S)

  UndoState[S] = object
    action:     ActionProc[S]
    actionName: string
    undoAction: ActionProc[S]


proc initUndoManager*[S](m: var UndoManager[S]) =
  m.states = @[]

proc newUndoManager*[S](): UndoManager[S] =
  result = new UndoManager[S]
  initUndoManager(result)


proc storeUndoState*[S](m: var UndoManager[S],
                        actionName: string,
                        action, undoAction: ActionProc[S]) =

  if m.states.len == 0:
    m.states.add(UndoState[S]())
    m.currState = 0

  # Discard later states if we're not at the last one
  elif m.currState < m.states.high:
    m.states.setLen(m.currState+1)
    m.lastSaveState = -1

  m.states[m.currState].action = action
  m.states[m.currState].actionName = actionName
  m.states.add(UndoState[S](action: nil, undoAction: undoAction))
  inc(m.currState)


proc canUndo*[S](m: UndoManager[S]): bool =
  m.currState > 0

proc undo*[S](m: var UndoManager[S], s: var S): string =
  if m.canUndo():
    m.states[m.currState].undoAction(s)
    dec(m.currState)
    result = m.states[m.currState].actionName

proc canRedo*[S](m: UndoManager[S]): bool =
  m.currState < m.states.high

proc redo*[S](m: var UndoManager[S], s: var S): string =
  if m.canRedo():
    m.states[m.currState].action(s)
    result = m.states[m.currState].actionName
    inc(m.currState)

proc setLastSaveState*[S](m: var UndoManager[S]) =
  m.lastSaveState = m.currState

proc isModified*[S](m: UndoManager[S]): bool =
  m.currState != m.lastSaveState

# vim: et:ts=2:sw=2:fdm=marker
