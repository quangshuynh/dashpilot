"""Generates DashPilot's onboarding illustrations as plain SVG, light and dark.

Original artwork, drawn here as code so it can be changed and reviewed like
code. Flat shapes only (paths, circles, rects, ellipses, dashed strokes): no
text, no filters, no gradients and no embedded images, so the asset catalog's
vector renderer draws them exactly. Digits on the stop markers are strokes.

    python3 tools/onboarding_art.py /tmp/art
    # then copy onboarding-<name>-{light,dark}.svg into
    # DashPilot/Assets.xcassets/Onboarding/onboarding-<name>.imageset/
"""
import sys, os

LIGHT = dict(
    bg="#FFF3E4", sun="#FBDDB8", ground="#F3DCC0", road="#E9CFAF",
    teal="#0F766E", tealSoft="#9BD3CB", coral="#E07A5F", coralDark="#C4614A",
    cream="#FFFFFF", ink="#2E2A27", inkSoft="#6B625B", glass="#CFE9E5",
    skinA="#C98B63", skinB="#F1C7A3", skinC="#8D5A3B", hairA="#2E2A27", hairB="#5A3A28", hairC="#1E1B19",
    shirtA="#0F766E", shirtB="#F2A65A", shirtC="#5B7DB1", bag="#E07A5F", bagDark="#B95842",
    phone="#2E2A27", screen="#FFFFFF", tire="#2E2A27", hub="#D9CFC6", marker="#FFFFFF",
)
DARK = dict(
    bg="#2A231E", sun="#4A3A2C", ground="#3A3029", road="#4A3E35",
    teal="#2BB3A1", tealSoft="#1E6E66", coral="#E58A70", coralDark="#C46B53",
    cream="#F6EEE6", ink="#141110", inkSoft="#A69A90", glass="#2E4C49",
    skinA="#C98B63", skinB="#E8BC97", skinC="#8D5A3B", hairA="#151210", hairB="#4A3020", hairC="#0E0C0B",
    shirtA="#2BB3A1", shirtB="#E8A05A", shirtC="#6F8FC4", bag="#E58A70", bagDark="#B95842",
    phone="#0E0C0B", screen="#F6EEE6", tire="#0E0C0B", hub="#8C7F74", marker="#F6EEE6",
)

W, H = 320, 220

def svg(body, p):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'<rect width="{W}" height="{H}" rx="20" fill="{p["bg"]}"/>' + body + '</svg>')

# Digits as strokes, centred on (x, y), about 10 pt tall.
DIGITS = {
    1: "M-1.5 -4 L1 -5.5 L1 5.5",
    2: "M-3.5 -2.5 C-3.5 -6 3.5 -6 3.5 -2.5 C3.5 0 -3.5 2.5 -3.5 5.5 L3.8 5.5",
    3: "M-3.5 -4.2 C-2 -6.5 3.8 -6 3.4 -2.4 C3.1 -0.4 0.5 -0.3 -0.6 -0.3 C1.5 -0.3 4 0.4 3.8 2.8 C3.5 6.5 -2.6 6.4 -3.8 3.8",
}

def marker(x, y, n, p, done=True, r=11):
    fill = p["teal"] if done else p["marker"]
    num = p["marker"] if done else p["teal"]
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{p["teal"]}" stroke-width="3"/>'
            f'<path d="{DIGITS[n]}" transform="translate({x} {y})" fill="none" stroke="{num}" '
            f'stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>')

def route(d_done, d_next, p):
    return (f'<path d="{d_done}" fill="none" stroke="{p["teal"]}" stroke-width="5" stroke-linecap="round"/>'
            f'<path d="{d_next}" fill="none" stroke="{p["teal"]}" stroke-width="4" stroke-linecap="round" '
            f'stroke-dasharray="2 9"/>')

def person_head(cx, cy, skin, hair, p, style=0, smile=True):
    """A friendly head: face, ears, hair, two eyes and a small smile."""
    out = f'<circle cx="{cx-24}" cy="{cy+3}" r="6" fill="{skin}"/><circle cx="{cx+24}" cy="{cy+3}" r="6" fill="{skin}"/>'
    out += f'<ellipse cx="{cx}" cy="{cy}" rx="24" ry="26" fill="{skin}"/>'
    if style == 0:   # short hair with a side sweep
        out += (f'<path d="M{cx-25} {cy-2} C{cx-28} {cy-30} {cx+20} {cy-38} {cx+25} {cy-6} '
                f'C{cx+14} {cy-16} {cx-4} {cy-20} {cx-14} {cy-14} C{cx-18} {cy-10} {cx-22} {cy-6} {cx-25} {cy-2} Z" fill="{hair}"/>')
    elif style == 1: # bun and fringe
        out += (f'<circle cx="{cx+4}" cy="{cy-32}" r="10" fill="{hair}"/>'
                f'<path d="M{cx-26} {cy+2} C{cx-30} {cy-34} {cx+30} {cy-34} {cx+26} {cy+2} '
                f'C{cx+20} {cy-14} {cx-6} {cy-20} {cx-26} {cy+2} Z" fill="{hair}"/>')
    else:            # cap with a teal brim
        out += (f'<path d="M{cx-25} {cy-4} C{cx-24} {cy-34} {cx+24} {cy-34} {cx+25} {cy-4} Z" fill="{p["teal"]}"/>'
                f'<path d="M{cx+10} {cy-6} L{cx+40} {cy-4} C{cx+42} {cy-1} {cx+30} {cy+1} {cx+16} {cy} Z" fill="{p["teal"]}"/>'
                f'<circle cx="{cx}" cy="{cy-30}" r="3" fill="{p["tealSoft"]}"/>')
    out += f'<circle cx="{cx-8}" cy="{cy+2}" r="2.6" fill="{p["ink"]}"/><circle cx="{cx+8}" cy="{cy+2}" r="2.6" fill="{p["ink"]}"/>'
    if smile:
        out += f'<path d="M{cx-7} {cy+11} C{cx-4} {cy+16} {cx+4} {cy+16} {cx+7} {cy+11}" fill="none" stroke="{p["ink"]}" stroke-width="2.4" stroke-linecap="round"/>'
    return out

def torso(cx, top, shirt, width=64, height=70):
    return (f'<path d="M{cx-width/2} {top+height} L{cx-width/2} {top+22} C{cx-width/2} {top+6} {cx-18} {top} {cx} {top} '
            f'C{cx+18} {top} {cx+width/2} {top+6} {cx+width/2} {top+22} L{cx+width/2} {top+height} Z" fill="{shirt}"/>')

def welcome(p):
    b = f'<circle cx="250" cy="62" r="40" fill="{p["sun"]}"/>'
    b += f'<rect x="0" y="168" width="{W}" height="52" fill="{p["ground"]}"/>'
    b += f'<path d="M0 186 L{W} 186" stroke="{p["road"]}" stroke-width="10"/>'
    # Route trailing behind the car, with stops.
    b += route("M22 150 C40 120 70 128 86 104", "M86 104 C100 84 128 92 140 70", p)
    b += marker(22, 150, 1, p) + marker(86, 104, 2, p) + marker(140, 70, 3, p, done=False)
    # Car body.
    b += (f'<path d="M110 176 L110 146 C110 136 116 130 126 128 L150 124 L174 98 C178 94 184 92 190 92 L236 92 '
          f'C246 92 252 96 258 104 L276 128 L292 132 C300 134 304 140 304 148 L304 176 Z" fill="{p["coral"]}"/>')
    b += f'<path d="M180 102 L236 102 C242 102 246 104 250 110 L262 128 L166 128 Z" fill="{p["glass"]}"/>'
    b += f'<rect x="208" y="102" width="6" height="26" fill="{p["coral"]}"/>'
    # Driver in the front window, waving.
    b += f'<clipPath id="win"><path d="M180 102 L208 102 L208 128 L166 128 Z"/></clipPath>'
    b += f'<g clip-path="url(#win)">{torso(190, 116, p["shirtA"], 40, 30)}</g>'
    b += f'<g transform="translate(190 106) scale(0.42) translate(-190 -106)">{person_head(190, 106, p["skinA"], p["hairA"], p, style=2)}</g>'
    b += (f'<path d="M206 126 C214 118 214 106 220 98" fill="none" stroke="{p["shirtA"]}" stroke-width="7" stroke-linecap="round"/>'
          f'<circle cx="221" cy="95" r="5" fill="{p["skinA"]}"/>')
    # Delivery bag on the back seat.
    b += f'<rect x="222" y="110" width="22" height="18" rx="3" fill="{p["bag"]}"/><path d="M228 110 C228 103 238 103 238 110" fill="none" stroke="{p["bagDark"]}" stroke-width="2.4"/>'
    # Handle, lights, wheels.
    b += f'<rect x="190" y="138" width="14" height="4" rx="2" fill="{p["coralDark"]}"/>'
    b += f'<rect x="292" y="140" width="10" height="7" rx="3" fill="{p["cream"]}"/>'
    for x in (140, 268):
        b += f'<circle cx="{x}" cy="176" r="18" fill="{p["tire"]}"/><circle cx="{x}" cy="176" r="8" fill="{p["hub"]}"/>'
    return svg(b, p)

def shift(p):
    b = f'<rect x="0" y="176" width="{W}" height="44" fill="{p["ground"]}"/>'
    # A card of figures shown as bars and lines only: no digits, nothing to mistake for data.
    b += f'<rect x="150" y="34" width="150" height="132" rx="14" fill="{p["cream"]}"/>'
    b += f'<circle cx="172" cy="58" r="10" fill="none" stroke="{p["teal"]}" stroke-width="3"/><path d="M172 52 L172 58 L176 61" stroke="{p["teal"]}" stroke-width="2.6" stroke-linecap="round" fill="none"/>'
    b += f'<rect x="190" y="52" width="70" height="7" rx="3.5" fill="{p["inkSoft"]}" opacity="0.45"/><rect x="190" y="63" width="44" height="6" rx="3" fill="{p["inkSoft"]}" opacity="0.25"/>'
    for i, h in enumerate([26, 40, 32, 52, 44]):
        b += f'<rect x="{170 + i*22}" y="{150-h}" width="14" height="{h}" rx="4" fill="{p["teal"] if i==3 else p["tealSoft"]}"/>'
    b += f'<path d="M166 152 L286 152" stroke="{p["inkSoft"]}" stroke-width="2" opacity="0.4"/>'
    # Route card corner: completed and upcoming stops.
    b += route("M18 204 C40 192 60 206 84 196", "M84 196 C104 188 120 200 140 192", p)
    b += marker(18, 204, 1, p, r=9) + marker(84, 196, 2, p, r=9) + marker(140, 192, 3, p, done=False, r=9)
    # Driver holding a phone and a bag.
    b += torso(78, 118, p["shirtB"], 70, 70)
    b += person_head(78, 96, p["skinB"], p["hairB"], p, style=1)
    b += f'<path d="M50 140 C50 160 66 164 96 158" fill="none" stroke="{p["shirtB"]}" stroke-width="12" stroke-linecap="round"/>'
    b += f'<rect x="94" y="140" width="20" height="34" rx="4" fill="{p["phone"]}"/><rect x="97" y="144" width="14" height="24" rx="2" fill="{p["screen"]}"/>'
    b += f'<path d="M100 150 L108 150 M100 155 L106 155" stroke="{p["teal"]}" stroke-width="2" stroke-linecap="round"/>'
    b += f'<circle cx="96" cy="158" r="6" fill="{p["skinB"]}"/>'
    b += f'<rect x="114" y="150" width="30" height="26" rx="4" fill="{p["bag"]}"/><path d="M121 150 C121 141 137 141 137 150" fill="none" stroke="{p["bagDark"]}" stroke-width="2.6"/>'
    return svg(b, p)

def road(p):
    b = f'<circle cx="64" cy="54" r="34" fill="{p["sun"]}"/>'
    # Dashboard and windscreen.
    b += f'<path d="M0 150 C80 128 240 128 {W} 150 L{W} {H} L0 {H} Z" fill="{p["ink"]}" opacity="0.88"/>'
    b += f'<path d="M24 118 L296 118" stroke="{p["road"]}" stroke-width="6" stroke-linecap="round"/>'
    # Parking marker beside the road ahead: a P drawn as a path, not text.
    b += f'<rect x="232" y="44" width="40" height="40" rx="10" fill="{p["teal"]}"/>'
    b += f'<path d="M245 74 L245 54 L254 54 C262 54 262 66 254 66 L245 66" fill="none" stroke="{p["marker"]}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'
    b += f'<rect x="250" y="84" width="4" height="34" fill="{p["inkSoft"]}"/>'
    # Steering wheel.
    b += f'<circle cx="92" cy="200" r="46" fill="none" stroke="{p["inkSoft"]}" stroke-width="10"/><path d="M50 196 L134 196" stroke="{p["inkSoft"]}" stroke-width="8"/>'
    # Phone in a cradle, with two large controls and a stop marker on screen.
    b += f'<rect x="168" y="120" width="12" height="40" rx="3" fill="{p["inkSoft"]}"/>'
    b += f'<rect x="150" y="96" width="92" height="64" rx="10" fill="{p["phone"]}"/><rect x="156" y="102" width="80" height="52" rx="6" fill="{p["screen"]}"/>'
    b += f'<rect x="162" y="128" width="32" height="20" rx="6" fill="{p["teal"]}"/><rect x="198" y="128" width="32" height="20" rx="6" fill="{p["tealSoft"]}"/>'
    b += f'<rect x="162" y="110" width="40" height="6" rx="3" fill="{p["inkSoft"]}" opacity="0.4"/>'
    b += marker(222, 114, 2, p, r=8)
    # A hand reaching for the larger control.
    b += f'<path d="M140 230 C146 204 156 188 166 176" fill="none" stroke="{p["shirtB"]}" stroke-width="24" stroke-linecap="round"/>'
    b += f'<path d="M166 176 C170 166 174 158 178 150" fill="none" stroke="{p["skinC"]}" stroke-width="16" stroke-linecap="round"/>'
    b += f'<ellipse cx="179" cy="145" rx="9" ry="8" fill="{p["skinC"]}"/>'
    # Lock-screen card hint: a small card with a large button.
    b += f'<rect x="20" y="22" width="0" height="0" fill="none"/>'
    return svg(b, p)

def local(p):
    b = f'<rect x="0" y="170" width="{W}" height="50" fill="{p["ground"]}"/>'
    # A simple home with a warm window.
    b += f'<path d="M188 92 L244 50 L300 92 L300 170 L188 170 Z" fill="{p["cream"]}"/><path d="M180 96 L244 46 L308 96" fill="none" stroke="{p["coral"]}" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>'
    b += f'<rect x="206" y="110" width="30" height="28" rx="4" fill="{p["sun"]}"/><rect x="254" y="122" width="28" height="48" rx="4" fill="{p["coral"]}"/>'
    # Route home, ending at the last stop.
    b += route("M20 196 C60 186 90 200 130 188", "M130 188 C150 182 168 184 182 178", p)
    b += marker(130, 188, 3, p, r=9)
    # Driver at the door with the phone held close, a shield on its screen.
    b += torso(96, 110, p["shirtC"], 66, 62)
    b += person_head(96, 88, p["skinC"], p["hairC"], p, style=0)
    b += f'<path d="M70 132 C68 150 84 156 104 146" fill="none" stroke="{p["shirtC"]}" stroke-width="12" stroke-linecap="round"/>'
    b += f'<rect x="100" y="122" width="26" height="42" rx="5" fill="{p["phone"]}"/><rect x="104" y="127" width="18" height="30" rx="3" fill="{p["screen"]}"/>'
    b += f'<path d="M113 132 L120 135 L120 141 C120 146 116 149 113 151 C110 149 106 146 106 141 L106 135 Z" fill="{p["teal"]}"/>'
    b += f'<path d="M109.5 141 L112 144 L116.5 138.5" fill="none" stroke="{p["marker"]}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
    b += f'<circle cx="104" cy="146" r="6" fill="{p["skinC"]}"/>'
    # The empty bag, set down: the day is done.
    b += f'<rect x="138" y="150" width="28" height="22" rx="4" fill="{p["bag"]}"/><path d="M144 150 C144 142 160 142 160 150" fill="none" stroke="{p["bagDark"]}" stroke-width="2.6"/>'
    return svg(b, p)

out = sys.argv[1]
for name, fn in [("welcome", welcome), ("shift", shift), ("road", road), ("local", local)]:
    for mode, pal in [("light", LIGHT), ("dark", DARK)]:
        with open(os.path.join(out, f"onboarding-{name}-{mode}.svg"), "w") as f:
            f.write(fn(pal))
print("ok")
