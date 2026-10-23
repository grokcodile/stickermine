/// Fill holes (spec section 6.6): closes white-on-white gaps such as toggle
/// knobs and calculator keys. Flood-fills the outside of the mask from the
/// image border through pixels with alpha below 0.5, then sets alpha to 1
/// everywhere that isn't within `edge` pixels of that outside, so the soft
/// outer edge stays as Vision drew it. Pure.
enum HoleFiller {
    /// The spec's "within 2–3 px of the outside".
    static let defaultEdge = 3
    static let threshold: Float = 0.5

    /// `alpha`: `width` × `height` values in 0–1, row by row (any row order).
    static func fill(alpha: inout [Float], width: Int, height: Int, edge: Int) {
        let count = width * height
        guard width > 0, height > 0, alpha.count == count else { return }

        // 1. The outside: every below-threshold pixel 4-connected to the border.
        var outside = [Bool](repeating: false, count: count)
        var queue: [Int] = []
        queue.reserveCapacity(count / 4)
        func seed(_ index: Int) {
            if !outside[index], alpha[index] < threshold {
                outside[index] = true
                queue.append(index)
            }
        }
        for x in 0..<width {
            seed(x)
            seed((height - 1) * width + x)
        }
        for y in 0..<height {
            seed(y * width)
            seed(y * width + width - 1)
        }
        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            let x = index % width
            let y = index / width
            if x > 0 { seed(index - 1) }
            if x < width - 1 { seed(index + 1) }
            if y > 0 { seed(index - width) }
            if y < height - 1 { seed(index + width) }
        }

        // 2. Distance from the outside (8-connected steps), up to `edge`.
        var distance = [Int32](repeating: Int32.max, count: count)
        var frontier: [Int] = []
        for index in 0..<count where outside[index] {
            distance[index] = 0
            // Seed only outside pixels with an inside 4-neighbour: every inside
            // pixel next to the outside touches one of them, so the distances are
            // the same and the rest of the outside (most of a large capture) is
            // never visited.
            let x = index % width
            let y = index / width
            if (x > 0 && !outside[index - 1]) || (x < width - 1 && !outside[index + 1])
                || (y > 0 && !outside[index - width]) || (y < height - 1 && !outside[index + width]) {
                frontier.append(index)
            }
        }
        var step: Int32 = 0
        while !frontier.isEmpty, step < Int32(edge) {
            step += 1
            var next: [Int] = []
            for index in frontier {
                let x = index % width
                let y = index / width
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -1...1 {
                        let nx = x + dx
                        guard nx >= 0, nx < width else { continue }
                        let neighbour = ny * width + nx
                        if distance[neighbour] > step {
                            distance[neighbour] = step
                            next.append(neighbour)
                        }
                    }
                }
            }
            frontier = next
        }

        // 3. Everything farther than `edge` from the outside becomes opaque.
        for index in 0..<count where distance[index] > Int32(edge) {
            alpha[index] = 1
        }
    }
}
