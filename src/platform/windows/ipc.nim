import options
#import strformat

import winim/lean


type
  MessageKind* = enum
    mkFocus, mkOpenFile

  Message* = object
    case kind*: MessageKind
    of mkFocus:    discard
    of mkOpenFile: filename*: string

const
  MaxFilenameLen = 32768


var g_pipe: Handle
var g_overlapped = Overlapped()
var g_buffer: array[MaxFilenameLen+3, byte]

# Pipe names must start with "\\.\pipe\"
const PipeName = "\\\\.\\pipe\\gridmonger"

# {{{ sendMessage()
proc sendMessage(numBytes: int32) =
  discard WriteFile(
    g_pipe,
    g_buffer[0].addr,
    numBytes,
    nil,
    g_overlapped.addr
  )
  # Wait until the message has been sent with a 2s timeout
  WaitForSingleObject(g_overlapped.hEvent, 2000)

# }}}
# {{{ commonInit()
proc commonInit(): bool =
  g_overlapped.hEvent = CreateEvent(
    nil,  # default security attribute
    true, # manual-reset event
    true, # initial state = signaled
    nil   # unnamed event object
  )
  if g_overlapped.hEvent == 0:
    #echo fmt"CreateEvent failed, error code: {GetLastError()}"
    discard
  else:
    result = true

# }}}

# {{{ isAppInstanceAlreadyRunning*()
proc isAppInstanceAlreadyRunning*(): bool =
  let res = CreateMutex(nil, true, "Global\\Gridmonger")
  result = GetLastError() == ErrorAlreadyExists

# }}}

# {{{ initClient()
proc initClient*(): bool =
  if not commonInit():
    return false

  # Use async mode (FileFlagOverlapped)
  g_pipe = CreateFile(
    PipeName,
    GenericWrite,
    0,    # disallow sharing
    nil,  # default security attribute
    OpenExisting,
    FileAttributeNormal or FileFlagOverlapped,
    0
  )
  if g_pipe == InvalidHandleValue:
    #echo fmt"Cannot open named pipe, error code: {GetLastError()}"
    discard
  else:
    result = true

# }}}
# {{{ deinitClient*()
proc deinitClient*() =
  discard CloseHandle(g_pipe)

# }}}
# {{{ sendFocusMessage*()
proc sendFocusMessage*() =
  g_buffer[0] = mkFocus.byte
  sendMessage(numBytes=1)

# }}}
# {{{ sendOpenFileMessage*()
proc sendOpenFileMessage*(filename: string) =
  var filename = filename.substr(0, MaxFilenameLen-1)
  g_buffer[0] = mkOpenFile.byte
  cast[ptr int16](g_buffer[1].addr)[] = filename.len.int16
  copyMem(g_buffer[3].addr, filename[0].addr, filename.len)

  sendMessage(numBytes=filename.len.int32 + 3)

# }}}

# {{{ initServer*()
proc initServer*(): bool =
  if not commonInit():
    return false

  # Use async mode (FileFlagOverlapped)
  g_pipe = CreateNamedPipe(
    PipeName,
    FileFlagFirstPipeInstance or FileFlagOverlapped or PipeAccessInbound,
    PipeTypeMessage,
    1,   # only allow 1 instance of this pipe
    0,   # no outbound buffer
    1,   # inbound buffer size - the kernel sets this automatically to
         # hold the largest unread data in the pipe at any given time
    1,   # 1ms wait time
    nil  # use default security attributes
  )
  if g_pipe == InvalidHandleValue:
    #echo fmt"Cannot create named pipe, error code: {GetLastError()}"
    discard
  else:
    result = true

# }}}
# {{{ tryReceiveMessage*()
proc tryReceiveMessage*(): Option[Message] =
  discard ConnectNamedPipe(g_pipe, g_overlapped.addr)

  if ReadFile(g_pipe, g_buffer[0].addr, g_buffer.len.int32, nil,
              g_overlapped.addr) == 0:
    case GetLastError()
    of ErrorBrokenPipe:
      # Client has disconnected; disconnect pipe so ConnectNamedPipe can
      # succeed in the next iteration, allowing another client to
      # connect
      discard DisconnectNamedPipe(g_pipe)
    else:
      #echo fmt"Cannot connect to named pipe, error code: {GetLastError()}"
      discard

  # Because the last `wait` arg is set to false, this will only succeed
  # when the message has been fully read into the buffer
  var numBytesTransferred: int32
  if GetOverlappedResult(g_pipe, g_overlapped.addr,
                         numBytesTransferred.addr, false) == 0:

    #echo fmt"Error getting overlapped result, error code: {GetLastError()}"
    discard
  else:
    let msgKind = cast[MessageKind](g_buffer[0])
    var msg = Message(kind: msgKind)

    case msg.kind
    of mkFocus: discard
    of mkOpenFile:
      let length = cast[ptr int16](g_buffer[1].addr)[]
      msg.filename = newString(length)
      copyMem(msg.filename[0].addr, g_buffer[3].addr, length)

    result = msg.some

# }}}


when isMainModule:
  import os

  echo "Starting..."
  if isAppInstanceAlreadyRunning():
    echo "*** CLIENT ***"
    if initClient():
      sendOpenFileMessage("quixotic")
      deinitClient()

  else:
    if initServer():
      echo "*** SERVER ***"
      while true:
        let msg = tryReceiveMessage()
        if msg.isSome:
          echo msg.get
        sleep(100)


# vim: et:ts=2:sw=2:fdm=marker
