import SwiftUI

/// The house with its lights on: the header of every kitchen page.
struct HouseHero: View {
    var sign: String

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Lamp.raise))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.82, y: h * 0.12, width: 24, height: 24)), with: .color(Lamp.star.opacity(0.7)))

            let houseW = min(w * 0.52, 220), left = (w - houseW) / 2, wallTop = h * 0.47
            var roof = Path()
            roof.move(to: CGPoint(x: left - 14, y: wallTop + 2))
            roof.addLine(to: CGPoint(x: w / 2, y: h * 0.16))
            roof.addLine(to: CGPoint(x: left + houseW + 14, y: wallTop + 2))
            roof.closeSubpath()
            ctx.fill(roof, with: .color(Lamp.ink.opacity(0.82)))
            ctx.fill(Path(CGRect(x: left, y: wallTop, width: houseW, height: h - wallTop)), with: .color(Lamp.surface))

            let lit = Color(hex: 0xFFD27A)
            let winW = houseW * 0.2, winH = h * 0.17, winY = wallTop + h * 0.15
            for x in [left + houseW * 0.1, left + houseW * 0.7] {
                let r = CGRect(x: x, y: winY, width: winW, height: winH)
                ctx.fill(Path(roundedRect: r.insetBy(dx: -6, dy: -6), cornerRadius: 6), with: .color(lit.opacity(0.18)))
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(lit))
            }
            let doorW = houseW * 0.22
            ctx.fill(Path(roundedRect: CGRect(x: w / 2 - doorW / 2, y: h * 0.66, width: doorW, height: h * 0.34), cornerRadius: 2), with: .color(Genre.food.color))

            // Awning, striped.
            let awnY = wallTop + 6, awnH = h * 0.07
            let stripes = 8
            for i in 0..<stripes {
                let sw = (houseW - 12) / CGFloat(stripes)
                let r = CGRect(x: left + 6 + CGFloat(i) * sw, y: awnY, width: sw, height: awnH)
                ctx.fill(Path(r), with: .color(i.isMultiple(of: 2) ? Lamp.accent : Lamp.surface))
            }

            // String lights across the top.
            var wire = Path()
            wire.move(to: CGPoint(x: 0, y: h * 0.28))
            wire.addQuadCurve(to: CGPoint(x: w, y: h * 0.3), control: CGPoint(x: w / 2, y: h * 0.52))
            ctx.stroke(wire, with: .color(Lamp.ink.opacity(0.4)), lineWidth: 1)
            for i in 0...10 {
                let t = CGFloat(i) / 10
                let x = (1 - t) * (1 - t) * 0 + 2 * (1 - t) * t * (w / 2) + t * t * w
                let y = (1 - t) * (1 - t) * (h * 0.28) + 2 * (1 - t) * t * (h * 0.52) + t * t * (h * 0.3)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 7, y: y - 5, width: 14, height: 14)), with: .color(lit.opacity(0.22)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.6, y: y + 0.4, width: 5.2, height: 5.2)), with: .color(lit))
            }

            // Chalkboard sign by the door.
            let signRect = CGRect(x: left + houseW + 18, y: h * 0.66, width: 58, height: 40)
            ctx.fill(Path(roundedRect: signRect, cornerRadius: 4), with: .color(Color(hex: 0x2B2B2B)))
            ctx.draw(
                Text(sign.uppercased()).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white),
                in: signRect.insetBy(dx: 4, dy: 6)
            )
            ctx.fill(Path(CGRect(x: 0, y: h - 3, width: w, height: 3)), with: .color(Lamp.ink.opacity(0.15)))
        }
        .frame(height: 210)
        .accessibilityHidden(true)
    }
}
