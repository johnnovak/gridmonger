template alias*(newName: untyped, call: untyped) =
  template newName(): untyped = call

