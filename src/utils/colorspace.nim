import glm

import nanovg

type
  ColorSpace* = enum
    csSrgb, csDciP3, csAdobe, csRec2020

var
  g_colorSpace* = csDciP3

# {{{ Transform matrices

# plain srgb to xyz without colour profile / transpose
#vec3 sRGB_to_XYZ(vec3 RGB){
#    const mat3x3 m = mat3x3(
#    0.4124564,  0.3575761,  0.1804375,
#    0.2126729,  0.7151522,  0.0721750,
#    0.0193339,  0.1191920,  0.9503041);
#    return RGB * m;
#}

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
#
let srgb_to_display_p3 = mat3(
  vec3(0.82246196871436230, 0.03319419885096161, 0.01708263072112003),
  vec3(0.17753803128563775, 0.96680580114903840, 0.07239744066396346),
  vec3(0.00000000000000000, 0.00000000000000000, 0.91051992861491650)
)

#let srgb_to_dci_p3 = mat3(
#  vec3(0.868579739716132238,  0.128919138460847215,  0.0025011218230205465),
#  vec3(0.0345404102543194492, 0.961811386361919974,  0.00364820338376057661),
#  vec3(0.0167714290414502811, 0.0710399977868858444, 0.912188573171663874)
#)
let srgb_to_dci_p3 = mat3(
  vec3(0.868579739716132238,  0.0345404102543194492,  0.0167714290414502811),
  vec3(0.128919138460847215, 0.961811386361919974,  0.0710399977868858444),
  vec3(0.0025011218230205465, 0.00364820338376057661, 0.912188573171663874)
)

let srgb_to_dci_p3_d65 = mat3(
  vec3(0.822461968714362,  0.177538031285638, 6.05294423040937e-17),
  vec3(0.0331941988509616, 0.966805801149038,  1.05823760922155e-18),
  vec3(0.01708263072112,   0.0723974406639634, 0.910519928614916),
)


let rec709_to_dci_p3 = mat3(
 vec3(0.875905, 0.122070, 0.002025),
 vec3(0.035332, 0.964542, 0.000126),
 vec3(0.016382, 0.063767, 0.919851)
)



# >>> RGB_to_RGB(sRGB, DCI_P3)
# matrix(
# [['0.868579739716132238', '0.128919138460847215', '0.0025011218230205465# '],
#  ['0.0345404102543194492', '0.961811386361919974', '0.00364820338376057661'],
#  ['0.0167714290414502811', '0.0710399977868858444', '0.912188573171663874']])
# >>> RGB_to_RGB(sRGB, DisplayP3)
# matrix(
# [['0.822461968714362252', '0.177538031285637748', '3.63192176587971491e-20'],
#  ['0.0331941988509616319', '0.966805801149038368', '1.07529618279736419e-21'],
#  ['0.0170826307211200384', '0.0723974406639634852', '0.910519928614916476']])

let dci_to_d65 = mat3(
  vec3(1.02449672775257741, 0.0151635410224164529, 0.0196885223342066751),
  vec3(0.0256121933371583221, 0.972586305624413502, 0.00471635229242730378),
  vec3(0.00638423065008767842, -0.0122680827367301992, 1.14794244517367773)
)

let dci_to_d70 = mat3(
  vec3(1.02320547096601, 0.015779962096588, 0.0383966181478784),
  vec3(0.028697633468036, 0.964469758807413, 0.0103285305959244),
  vec3(0.0108761114997121, -0.0202938541688958, 1.25977501934358)
)

let dci_to_d67 = mat3(
  vec3(1.02962699477639, 0.0187610901560866, 0.029696348056099),
  vec3(0.0322979010291991, 0.963995684247388, 0.00745066837611457),
  vec3(0.00916018243997003, -0.0174218404578008, 1.21457700391171)
)


let dci_to_d75 = mat3(
  vec3(1.00378734940401, 0.00557827701577385, 0.0481493370792468),
  vec3(0.0140917618966783, 0.973920294510654, 0.0141169056453834),
  vec3(0.0120165124311795, -0.0217070863061646, 1.29614429743282)
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
  of csDciP3:   transform(srgb_to_dci_p3, 2.6)
#  of csDciP3:   transform(srgb_to_display_p3, 2.2)
  of csAdobe:   transform(toAdobe,   2.2)
  of csRec2020: transform(toRec2020, 2.4)
# }}}

# vim: et:ts=2:sw=2:fdm=marker
