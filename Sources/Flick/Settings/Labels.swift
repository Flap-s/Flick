import FlickCore

protocol Labeled: CaseIterable, Hashable {
    var label: String { get }
}

extension AppFilter: Labeled {
    var label: String {
        switch self {
        case .all: tr("Toutes les apps", "All apps")
        case .activeApp: tr("App active seulement", "Active app only")
        case .nonActiveApps: tr("Apps non actives", "Non-active apps")
        case .appUnderCursor: tr("App sous le curseur", "App under the pointer")
        }
    }
}

extension SpaceFilter: Labeled {
    var label: String {
        switch self {
        case .all: tr("Tous les Spaces", "All Spaces")
        case .visible: tr("Spaces visibles", "Visible Spaces")
        case .nonVisible: tr("Spaces non visibles", "Non-visible Spaces")
        }
    }
}

extension ScreenFilter: Labeled {
    var label: String {
        switch self {
        case .all: tr("Tous les écrans", "All screens")
        case .showingSwitcher: tr("L’écran du sélecteur", "Screen showing the switcher")
        }
    }
}

extension Visibility: Labeled {
    var label: String {
        switch self {
        case .show: tr("Afficher", "Show")
        case .showAtEnd: tr("Afficher à la fin", "Show at the end")
        case .hide: tr("Masquer", "Hide")
        }
    }
}

extension WindowOrder: Labeled {
    var label: String {
        switch self {
        case .recentlyFocused: tr("Utilisées récemment d’abord", "Recently used first")
        case .recentlyCreated: tr("Créées récemment d’abord", "Recently created first")
        case .alphabetical: tr("Ordre alphabétique", "Alphabetical")
        case .space: tr("Ordre des Spaces", "Space order")
        }
    }
}

extension ReleaseAction: Labeled {
    var label: String {
        switch self {
        case .focusSelected: tr("Activer la fenêtre sélectionnée", "Focus the selected window")
        case .doNothing: tr("Garder le sélecteur ouvert", "Keep the switcher open")
        }
    }
}

extension GestureKind: Labeled {
    var label: String {
        switch self {
        case .none: tr("Désactivé", "Off")
        case .threeFingerHorizontal: tr("Balayage horizontal à 3 doigts", "3-finger horizontal swipe")
        case .threeFingerVertical: tr("Balayage vertical à 3 doigts", "3-finger vertical swipe")
        case .fourFingerHorizontal: tr("Balayage horizontal à 4 doigts", "4-finger horizontal swipe")
        case .fourFingerVertical: tr("Balayage vertical à 4 doigts", "4-finger vertical swipe")
        }
    }
}

extension ControlAction: Labeled {
    var label: String {
        switch self {
        case .focus: tr("Activer la fenêtre sélectionnée", "Focus the selected window")
        case .cancel: tr("Annuler et fermer", "Cancel and close")
        case .closeWindow: tr("Fermer la fenêtre", "Close window")
        case .minimizeWindow: tr("Réduire / restaurer la fenêtre", "Minimize / restore window")
        case .fullscreenWindow: tr("Plein écran / quitter le plein écran", "Enter / exit full screen")
        case .quitApp: tr("Quitter l’app", "Quit app")
        case .hideApp: tr("Masquer / afficher l’app", "Hide / show app")
        case .search: tr("Rechercher", "Search")
        }
    }
}

extension Style: Labeled {
    var label: String {
        switch self {
        case .thumbnails: tr("Miniatures", "Thumbnails")
        case .appIcons: tr("Icônes d’apps", "App icons")
        case .titles: tr("Titres", "Titles")
        }
    }

    var symbol: String {
        switch self {
        case .thumbnails: "rectangle.grid.2x2"
        case .appIcons: "square.grid.3x2"
        case .titles: "list.bullet.rectangle"
        }
    }
}

extension SizeOption: Labeled {
    var label: String {
        switch self {
        case .small: tr("Petite", "Small")
        case .medium: tr("Moyenne", "Medium")
        case .large: tr("Grande", "Large")
        case .auto: tr("Automatique", "Automatic")
        }
    }
}

extension Theme: Labeled {
    var label: String {
        switch self {
        case .system: tr("Système", "System")
        case .light: tr("Clair", "Light")
        case .dark: tr("Sombre", "Dark")
        }
    }
}

extension ShowOn: Labeled {
    var label: String {
        switch self {
        case .activeScreen: tr("Écran de la fenêtre active", "Screen with the active window")
        case .mouseScreen: tr("Écran du pointeur", "Screen with the pointer")
        case .menuBarScreen: tr("Écran de la barre des menus", "Screen with the menu bar")
        }
    }
}

extension TitleSource: Labeled {
    var label: String {
        switch self {
        case .windowTitle: tr("Titre de la fenêtre", "Window title")
        case .appName: tr("Nom de l’app", "App name")
        case .appAndWindowTitle: tr("Nom de l’app — titre de la fenêtre", "App name — window title")
        }
    }
}

extension Truncation: Labeled {
    var label: String {
        switch self {
        case .start: tr("Au début", "At the start")
        case .middle: tr("Au milieu", "In the middle")
        case .end: tr("À la fin", "At the end")
        }
    }
}

extension Alignment: Labeled {
    var label: String {
        switch self {
        case .leading: tr("À gauche", "Left")
        case .center: tr("Centrées", "Centered")
        }
    }
}

extension HideRule: Labeled {
    var label: String {
        switch self {
        case .never: tr("Ne pas masquer", "Don’t hide")
        case .always: tr("Toujours", "Always")
        case .whenNoOpenWindow: tr("Sans fenêtre ouverte", "When no window is open")
        }
    }
}

extension IgnoreRule: Labeled {
    var label: String {
        switch self {
        case .never: tr("Jamais", "Never")
        case .whenFullscreen: tr("En plein écran", "In full screen")
        case .always: tr("Toujours", "Always")
        }
    }
}

extension MenuBarIcon: Labeled {
    var label: String {
        switch self {
        case .stack: tr("Pile", "Stack")
        case .windows: tr("Fenêtres", "Windows")
        case .arrows: tr("Flèches", "Arrows")
        case .hidden: tr("Masquée", "Hidden")
        }
    }
}
