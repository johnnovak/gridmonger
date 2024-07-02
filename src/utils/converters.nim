converter toCfloat*(x: SomeInteger): cfloat = x.cfloat
converter tcFloat*(x: SomeInteger): float = x.float

converter toInt32Tuple*(t: (Natural, Natural)): (int32, int32) =
  (t[0].int32, t[1].int32)
