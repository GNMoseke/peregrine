import ArgumentParser

func print(_ str: String, _ color: TextColor) {
    print(color.rawValue + str + "\u{001B}[0m")
}

enum TextColor: String {
    case GreenBold = "\u{001B}[0;32;1m"
    case RedBold = "\u{001B}[0;31;1m"
    case CyanBold = "\u{001B}[0;36;1m"
}

enum NerdFontIcons: String {
    case ErlenmeyerFlask = "󰂓"
    case Build = "󱌣"
    case Failure = ""
    case Success = ""
    case RightArrow = "󱞩"
    // not technically nerd font icons but putting here
    case FilledBlock = "█"
    case LightlyShadedBlock = "░"
}

enum LongTestOutputFormat: String, ExpressibleByArgument {
    case stdout
    case csv
}
