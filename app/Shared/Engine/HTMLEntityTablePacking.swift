// HTMLEntityTablePacking — the reader for the format
// tools/gen-html-entities.rb writes.
//
// Split out of HTMLEntityCodec.swift because that file crossed
// `.swiftlint.yml`'s 400-line `file_length` budget, which `--strict` makes an
// error. The same choice plan 06-05 made when the generated table crossed
// `type_body_length`: SPLIT, rather than add an `excluded:` entry that would
// make the lint config dishonest for every other file in order to spare one
// declaration. Nothing in `.swiftlint.yml` or `.swiftformat` was touched by
// this plan; `git diff --stat` on both is empty.
//
// It is also the right seam. This is a FORMAT reader — it knows about U+0001,
// U+0002 and nothing else. The codec knows about entities and nothing about
// how they are stored.
//
// THE FORMAT, AND THE DEFECT IT EXISTS TO AVOID
//
//     NAME <U+0002> TARGET-SCALARS <U+0001>
//
// The obvious pack, "NAME=TARGET;NAME=TARGET;...", silently loses records
// while compiling at exit 0 with no diagnostic. Measured on this tree by
// re-packing the real 2125 records and reading them back with a Character
// split: 2125 in, 2117 out. EIGHT lost, by two different mechanisms.
//
//   equals U+003D, semi U+003B          the target IS a delimiter
//   DotDot U+20DC, TripleDot U+20DB,    the target ABSORBS the delimiter:
//   tdot U+20DB, DownBreve U+0311,      each is a combining or format scalar
//   zwj U+200D, zwnj U+200C             with Grapheme_Cluster_Break=Extend,
//                                       so "=" followed by it is ONE
//                                       Character and the split does not
//                                       break there
//
// And `bne` U+003D U+20E5 comes through the broken format CORRECTLY, for the
// same grapheme-cluster reason — so spot-checking `bne` would report a broken
// table healthy. That is why the count is asserted and why all three
// delimiter-shaped entities are named individually in HTMLEntityTests.
//
// U+0001 and U+0002 are immune to both mechanisms: the minimum target scalar
// in the whole table is U+0009, and a control character always breaks a
// grapheme cluster, so nothing can absorb them. The reader below splits on
// SCALARS regardless, because that is immune by construction rather than by
// argument.

import Foundation

/// Reads the packed chunks the generator emits into `name -> text`.
///
/// A caseless enum: there is no state and nothing to construct.
enum HTMLEntityTablePacking {
    /// The record delimiter, U+0001.
    ///
    /// Stated as a scalar VALUE and compared as one, so no `Character`
    /// comparison can absorb it into a grapheme cluster. `REC_SCALAR` in
    /// `tools/gen-html-entities.rb` is the emitting half of this pair.
    static let recordDelimiter: UInt32 = 0x0001

    /// The field delimiter, U+0002. `FLD_SCALAR` in the generator.
    static let fieldDelimiter: UInt32 = 0x0002

    /// Split every chunk into records and every record into its two fields.
    ///
    /// State is carried ACROSS chunk boundaries, so a future generator that
    /// split one record over two chunks would still parse correctly. The
    /// generator does not currently do that — each chunk ends on a record
    /// delimiter — and the count assertion in HTMLEntityTests is what would
    /// catch it if either side changed.
    ///
    /// - Note: Total. There is no subscript, no force-unwrap and no failable
    ///   initializer; a malformed chunk yields fewer records rather than a
    ///   trap, and fewer records is exactly what the count assertion sees.
    /// - Parameter chunks: Packed chunks, in order, from one or more tables.
    /// - Returns: Entity name (no `&`, no `;`) to the text it stands for.
    static func parse(_ chunks: [String]) -> [String: String] {
        var out = [String: String]()
        out.reserveCapacity(2200)
        var name = ""
        var text = ""
        var inTarget = false

        for chunk in chunks {
            for scalar in chunk.unicodeScalars {
                switch scalar.value {
                case recordDelimiter:
                    if !name.isEmpty {
                        out[name] = text
                    }
                    name = ""
                    text = ""
                    inTarget = false
                case fieldDelimiter:
                    inTarget = true
                default:
                    if inTarget {
                        text.unicodeScalars.append(scalar)
                    } else {
                        name.unicodeScalars.append(scalar)
                    }
                }
            }
        }
        return out
    }
}
