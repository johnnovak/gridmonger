# gfx
#
# Stateless graphics helpers that wrap nanovg primitives: pattern creation
# from an image, post-processing of raw image data (alpha extraction, hue
# tinting). No AppContext awareness — callers pass the NVGContext and the
# raw ImageData buffer.
# Side effects: GL/nanovg state mutation via the NVGContext when calling
# createPattern.

import nanovg


# {{{ createPattern()
proc createPattern*(vg: NVGContext, img: var Image, alpha: float = 1.0,
                    xoffs: float = 0, yoffs: float = 0,
                    scale: float = 1.0): Paint =

  let (w, h) = vg.imageSize(img)
  vg.imagePattern(
    ox=xoffs, oy=yoffs, ex=w*scale, ey=h*scale, angle=0, img, alpha
  )

# }}}
# {{{ createAlpha()
proc createAlpha*(d: var ImageData) =
  for i in 0..<(d.width * d.height):
    # copy the R component to the alpha channel
    d.data[i*4+3] = d.data[i*4]

# }}}
# {{{ colorImage()
func colorImage*(d: var ImageData, color: Color) =
  for i in 0..<(d.width * d.height):
    d.data[i*4]   = (color.r * 255).byte
    d.data[i*4+1] = (color.g * 255).byte
    d.data[i*4+2] = (color.b * 255).byte

# }}}

# vim: et:ts=2:sw=2:fdm=marker
