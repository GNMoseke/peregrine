// Output.swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ArgumentParser

func print(_ str: String, terminator: String = "\n", _ color: TextColor) {
    print(color.rawValue + str + "\u{001B}[0m", terminator: terminator)
}

enum TextColor: String {
    case greenBold = "\u{001B}[0;32;1m"
    case redBold = "\u{001B}[0;31;1m"
    case cyanBold = "\u{001B}[0;36;1m"
    case cyan = "\u{001B}[0;36m"
}

struct SymbolOutput {
    let plaintext: Bool
    func getSymbol(_ icon: NerdFontIcons) -> String {
        return plaintext ? icon.plain : icon.rawValue
    }
}

enum NerdFontIcons: String {
    case erlenmeyerFlask = "󰂓"
    case failedTestFlask = "󱉄"
    case timer = "󰔛"
    case build = "󱌣"
    case failure = ""
    case success = ""
    case rightArrow = "󱞩"
    // not technically nerd font icons but putting here
    case filledBlock = "█"
    case lightlyShadedBlock = "░"

    var plain: String {
        switch self {
            case .erlenmeyerFlask: "*"
            case .failedTestFlask, .failure: "!"
            case .timer: "@"
            case .build: "%"
            case .success: ""
            case .rightArrow: ">"
            case .filledBlock, .lightlyShadedBlock: rawValue
        }
    }
}

enum LongTestOutputFormat: String, ExpressibleByArgument {
    case stdout
    case csv
}
