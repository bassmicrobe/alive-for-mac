// Port of src/Scales.cs
import Foundation

/// The set's overall key: in the .als it sits as two numbers —
/// `<ScaleInformation><Root Value="0"/><Name Value="0"/></ScaleInformation>` right inside
/// LiveSet (every clip has nodes like these too, and those must not be taken).
///
/// The order of the scales comes from the LOM documentation baked into Live 12 itself ("default
/// scale names that can be saved with a set and recalled"). "The root can be a number between
/// 0 and 11, with 0 corresponding to C and 11 corresponding to B".
public enum Scales {
    private static let names = [
        "Major", "Minor", "Dorian", "Mixolydian", "Lydian", "Phrygian", "Locrian",
        "Whole Tone", "Half-whole Dim.", "Whole-half Dim.", "Minor Blues",
        "Minor Pentatonic", "Major Pentatonic", "Harmonic Minor", "Harmonic Major",
        "Dorian #4", "Phrygian Dominant", "Melodic Minor", "Lydian Augmented",
        "Lydian Dominant", "Super Locrian", "Bhairav", "Hungarian Minor",
        "8-Tone Spanish", "Hirajoshi", "In-Sen", "Iwato", "Kumoi", "Pelog Selisir",
        "Pelog Tembung", "Messiaen 3", "Messiaen 4", "Messiaen 5", "Messiaen 6",
        "Messiaen 7",
    ]

    private static let sharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flat = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// Note names offered by the filter. Both spellings at once: how a note gets written into a
    /// set depends on PreferFlatRootNote, while the note itself is one and the same.
    public static let rootChoices = [
        "C", "C# / Db", "D", "D# / Eb", "E", "F",
        "F# / Gb", "G", "G# / Ab", "A", "A# / Bb", "B",
    ]

    public static var scaleCount: Int { names.count }

    public static func rootName(_ root: Int, preferFlat: Bool) -> String {
        guard (0...11).contains(root) else { return "" }
        return preferFlat ? flat[root] : sharp[root]
    }

    public static func scaleName(_ index: Int) -> String {
        names.indices.contains(index) ? names[index] : ""
    }

    /// "C Major". Empty when the set was saved by a Live version without an overall key.
    public static func format(root: Int, scaleIndex: Int, preferFlat: Bool) -> String {
        let r = rootName(root, preferFlat: preferFlat)
        if r.isEmpty { return "" }
        let s = scaleName(scaleIndex)
        return s.isEmpty ? r : r + " " + s
    }
}
