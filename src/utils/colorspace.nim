import glm

import nanovg

type
  ColorSpace* = enum
    csSrgb, csDciP3, csAdobe, csRec2020

var
  g_colorSpace* = csDciP3

# {{{ Transform matrices
let profile0 = mat3(
  vec3(0.412391,  0.212639,  0.019331),
  vec3(0.357584,  0.715169,  0.119195),
  vec3(0.180481,  0.072192,  0.950532)
)

let toSrgb = mat3(
  vec3( 3.240970, -0.969244,  0.055630),
  vec3(-1.537383,  1.875968, -0.203977),
  vec3(-0.498611,  0.041555,  1.056972)
);

let toDciP3 = mat3(
  vec3( 2.725394, -0.795168,  0.041242),
  vec3(-1.018003,  1.689732, -0.087639),
  vec3(-0.440163,  0.022647,  1.100929)
)

# Source:
# https://github.com/sass/dart-sass/blob/8f1c24a25f2c3b7198492554ec34db05dfd0ef30/lib/src/value/color/conversions.dart#L37
#
# Ref:
# https://gist.github.com/nex3/3d7ecfef467b22e02e7a666db1b8a316
# https://sass-lang.com/blog/wide-gamut-colors-in-sass/
# https://tech.metail.com/introduction-colour-spaces-dci-p3/
# https://github.com/endavid/VidEngine/blob/master/VidTests/VidTestsTests/ColorTests.swift
# https://endavid.com/index.php?entry=79 
# https://stackoverflow.com/questions/45295689/mtkview-displaying-wide-gamut-p3-colorspace/49578887#49578887

# The transformation matrix for converting linear-light srgb colors to
# linear-light display-p3.

let linearSrgbToLinearDisplayP3 = mat3(
  vec3(0.82246196871436230, 0.17753803128563775, 0.00000000000000000),
  vec3(0.03319419885096161, 0.96680580114903840, 0.00000000000000000),
  vec3(0.01708263072112003, 0.07239744066396346, 0.91051992861491650),
)

let toAdobe = mat3(
  vec3( 2.041588, -0.969244,  0.013444),
  vec3(-0.565007,  1.875968, -0.118360),
  vec3(-0.344731,  0.041555,  1.015175)
)

let toRec2020 = mat3(
  vec3( 1.716651, -0.666684,  0.017640),
  vec3(-0.355671,  1.616481, -0.042771),
  vec3(-0.253366,  0.015769,  0.942103)
)
# }}}

# {{{ gammaDecode()
func gammaDecode(color: Color, gamma: float): Vec3[float] =
  vec3(
    pow(color.r, gamma),
    pow(color.g, gamma),
    pow(color.b, gamma)
  )

# }}}
# {{{ gammaEncode()
func gammaEncode(color: Vec3[float], gamma: float): Color =
  rgb(
    pow(color[0], 1.0/gamma),
    pow(color[1], 1.0/gamma),
    pow(color[2], 1.0/gamma)
  )

# }}}

# {{{ transformSrgbColor*()
proc transformSrgbColor*(c: Color, destColorSpace: ColorSpace): Color =

  proc transform(m: Mat3[float], gamma: float): Color =
    var d = c.gammaDecode(2.2)
    d = m * d
    d.gammaEncode(gamma).withAlpha(c.a)

  case destColorSpace
  of csSrgb:    transform(toSrgb,    2.4)
  of csDciP3:   transform(linearSrgbToLinearDisplayP3, 2.6)
  of csAdobe:   transform(toAdobe,   2.2)
  of csRec2020: transform(toRec2020, 2.4)
# }}}

# { p = 2.4; m_out =  ToSRGB; } else
# { p = 2.6; m_out =  ToDCI;  } else
# { p = 2.2; m_out =  ToAdobe;} else
# { p = 2.4; m_out =  ToREC;  }

#	c = pow(c, vec3(p));

#	mat3 m_in = Profile0;

#	c = m_in * c;
#	c = m_out * c;

#	c = pow(c, vec3(1.0/p));

# vim: et:ts=2:sw=2:fdm=marker
