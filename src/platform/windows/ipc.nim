import std/options
import std/strformat

import winim/lean

# Adapted from
# https://peter.bloomfield.online/introduction-to-win32-named-pipes-cpp/

const
  MaxPathLen = 32768

var
  g_pipe: Handle
  g_overlapped = Overlapped()
  g_buffer: array[MaxPathLen+3, byte]

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
    echo fmt"CreateEvent failed, error code: {GetLastError()}"
    discard
  else:
    result = true

# }}}

# {{{ initClient*()
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
    echo fmt"Cannot open named pipe, error code: {GetLastError()}"
    discard
  else:
    result = true

# }}}
# {{{ sendFocusMessage*()
proc sendFocusMessage*() =
  g_buffer[0] = aeFocus.byte
  sendMessage(numBytes=1)

# }}}
# {{{ sendOpenFileMessage*()
proc sendOpenFileMessage*(path: string) =
  var path = path.substr(0, MaxPathLen-1)
  g_buffer[0] = aeOpenFile.byte
  cast[ptr int16](g_buffer[1].addr)[] = path.len.int16
  copyMem(g_buffer[3].addr, path[0].addr, path.len)

  sendMessage(numBytes=path.len.int32 + 3)

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
    echo fmt"Cannot create named pipe, error code: {GetLastError()}"
    discard
  else:
    result = true

# }}}
# {{{ tryReceiveMessage*()
proc tryReceiveMessage*(): Option[AppEvent] =
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
      echo fmt"Cannot connect to named pipe, error code: {GetLastError()}"
      discard

  # Because the last `wait` arg is set to false, this will only succeed
  # when the message has been fully read into the buffer
  var numBytesTransferred: int32
  if GetOverlappedResult(g_pipe, g_overlapped.addr,
                         numBytesTransferred.addr, false) == 0:

    echo fmt"Error getting overlapped result, error code: {GetLastError()}"
    discard
  else:
    let eventKind = cast[AppEventKind](g_buffer[0])
    var event = AppEvent(kind: eventKind)

    case event.kind
    of aeFocus: discard
    of aeOpenFile:
      let length = cast[ptr int16](g_buffer[1].addr)[]
      event.path = newString(length)
      copyMem(event.path[0].addr, g_buffer[3].addr, length)

    result = event.some

# }}}

# {{{ shutdown*()
proc shutdown*() =
  discard CloseHandle(g_pipe)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
