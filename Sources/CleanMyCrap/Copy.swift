import Foundation

/// All the jokes live here, so they're easy to keep (or regret).
enum Copy {
    static let scanning = [
        "Sniffing around ~/Library…",
        "Lifting the couch cushions…",
        "Going deep into node_modules. Pray for us.",
        "Asking Docker what it's been hoarding…",
        "Counting Xcode's leftovers. This could take a while.",
        "Judging your Downloads folder, silently…",
        "Holding our nose and opening ~/.cache…",
        "Finding logs nobody has ever read…",
        "Checking behind the fridge…",
        "Weighing your crap. Professionally.",
    ]

    static let flushing = [
        "Flushing…",
        "Jiggling the handle…",
        "Sending it to a better place…",
        "Plunging the stubborn bits…",
        "Goodbye, sweet cache…",
        "Making some room in here…",
    ]

    static func headline(for bytes: Int64) -> String {
        switch bytes {
        case ..<(1 << 30): "Honestly? Pretty clean in here."
        case ..<(10 << 30): "A respectable amount of crap."
        case ..<(50 << 30): "Okay, that's a lot of crap."
        default: "Wow. Your Mac is mostly crap."
        }
    }

    static func doneLine(for bytes: Int64) -> String {
        switch bytes {
        case ..<(1 << 30): "Small flush, big heart."
        case ..<(10 << 30): "Your Mac feels lighter already."
        case ..<(50 << 30): "That was a big one. Your Mac thanks you."
        default: "Legendary flush. Tell your friends. Or don't."
        }
    }
}
