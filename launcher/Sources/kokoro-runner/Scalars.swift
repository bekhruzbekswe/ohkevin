import Foundation

// Python's str works on code points; so does the port. Scalars is a Python str.
typealias Scalars = [Unicode.Scalar]

func scalars(_ s: String) -> Scalars { Array(s.unicodeScalars) }
func string(_ u: Scalars) -> String { var v = String.UnicodeScalarView(); v.append(contentsOf: u); return String(v) }

/// What Python's str.isspace() (and re's \s on str) calls whitespace.
func isPySpace(_ c: Unicode.Scalar) -> Bool {
    switch c.value {
    case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: return true
    default: return false
    }
}

/// str.strip() without arguments.
func pyStrip(_ u: Scalars) -> Scalars {
    var a = u[...]
    while let f = a.first, isPySpace(f) { a = a.dropFirst() }
    while let l = a.last, isPySpace(l) { a = a.dropLast() }
    return Array(a)
}

/// str.replace(old, new): left to right, not overlapping.
func pyReplace(_ u: Scalars, _ old: Scalars, _ new: Scalars) -> Scalars {
    var out = Scalars(), i = 0
    while i < u.count {
        if i + old.count <= u.count, Array(u[i..<i + old.count]) == old { out += new; i += old.count } else { out.append(u[i]); i += 1 }
    }
    return out
}

/// str.split(sep) for a one-character separator: empty pieces are kept.
func pySplit(_ u: Scalars, _ sep: Unicode.Scalar) -> [Scalars] {
    var parts = [Scalars()]
    for c in u { if c == sep { parts.append([]) } else { parts[parts.count - 1].append(c) } }
    return parts
}

func hasSuffix(_ u: Scalars, _ s: Scalars) -> Bool { u.count >= s.count && Array(u.suffix(s.count)) == s }
