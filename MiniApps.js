// Registry of Overview mini apps: small interactive panels that open over the
// workspace grid. Adding one is a QML file plus an entry here; the Overview
// loads it by `source` and the search finds it by `keywords`.
var MINI_APPS = [
    {
        id: "calculator",
        title: "Calculator",
        subtitle: "Arithmetic, history and copy",
        icon: "calculator",
        source: "CalculatorApp.qml",
        keywords: ["calc", "calculator", "calculadora", "math", "maths", "arithmetic"]
    },
    {
        id: "displays",
        title: "Displays",
        subtitle: "Arrange your monitors",
        icon: "monitor",
        source: "DisplaysApp.qml",
        keywords: ["display", "displays", "monitor", "monitors", "monitores", "pantalla", "pantallas", "screen", "screens", "layout", "arrange"]
    }
];

function byId(id) {
    const needle = String(id ?? "");
    for (var i = 0; i < MINI_APPS.length; ++i) {
        if (MINI_APPS[i].id === needle)
            return MINI_APPS[i];
    }
    return null;
}

// Mini apps whose name or keywords start with the query. Prefix matching keeps
// a two-letter query from dragging every mini app into the result list.
function search(query, limit) {
    const needle = String(query ?? "").toLowerCase().trim();
    if (needle.length === 0)
        return [];
    const out = [];
    for (var i = 0; i < MINI_APPS.length; ++i) {
        const app = MINI_APPS[i];
        const names = [app.title.toLowerCase()].concat(app.keywords);
        for (var j = 0; j < names.length; ++j) {
            if (names[j].indexOf(needle) === 0) {
                out.push(app);
                break;
            }
        }
    }
    return typeof limit === "number" ? out.slice(0, limit) : out;
}
