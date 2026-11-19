.pragma library

// Curated library: Egypt's official public radio (Maspero / National Media Authority),
// via their public Dailymotion live pages.
// logo: "pkg:<file>" points to contents/images/logos/<file>; empty = generated glass logo.
var catalog = [
    { name: "صوت العرب", en: "Sawt El Arab",             url: "https://www.dailymotion.com/video/x8n6dqq", logo: "pkg:x8n6dqq.jpg", glyph: "ص",  color: "#1e88e5" },
    { name: "الشرق الأوسط", en: "Middle East Radio",          url: "https://www.dailymotion.com/video/x8n6drt", logo: "",                glyph: "ش",  color: "#f4511e" },
    { name: "راديو مصر", en: "Radio Masr",             url: "https://www.dailymotion.com/video/x8n6dpk", logo: "",                glyph: "م",  color: "#e53935" },
    { name: "البرنامج العام", en: "General Program",         url: "https://www.dailymotion.com/video/x8n6dt3", logo: "",                glyph: "ع",  color: "#6d4c41" },
    { name: "القرآن الكريم", en: "Holy Quran Radio",          url: "https://www.dailymotion.com/video/x84wyku", logo: "pkg:x84wyku.jpg", glyph: "ق",  color: "#2e7d32" },
    { name: "الشباب والرياضة", en: "Youth & Sports",        url: "https://www.dailymotion.com/video/x8n6dzo", logo: "pkg:x8n6dzo.jpg", glyph: "ش",  color: "#00897b" },
    { name: "الأغاني", en: "Al Aghani",               url: "https://www.dailymotion.com/video/x8n6dyz", logo: "",                glyph: "♪",  color: "#8e24aa" },
    { name: "البرنامج الثقافي", en: "Cultural Program",       url: "https://www.dailymotion.com/video/x8n6eci", logo: "pkg:x8n6eci.jpg", glyph: "ث",  color: "#f9a825" },
    { name: "القاهرة الكبرى", en: "Greater Cairo",         url: "https://www.dailymotion.com/video/x8n6ebs", logo: "",                glyph: "ق",  color: "#3949ab" },
    { name: "البرنامج الأوروبي", en: "European Program",      url: "https://www.dailymotion.com/video/x8n6e6w", logo: "",                glyph: "EU", color: "#039be5" },
    { name: "القرآن الكريم (مباشر)", en: "Holy Quran (direct)", url: "https://stream.radiojar.com/8s5u5tpdtwzuv", logo: "pkg:x84wyku.jpg", glyph: "ق",  color: "#1b5e20" }
];

var palette = ["#1e88e5", "#3949ab", "#8e24aa", "#d81b60", "#e53935", "#f4511e",
               "#fb8c00", "#f9a825", "#43a047", "#00897b", "#00acc1", "#6d4c41"];

// A readable glyph from a station name: skips filler words ("إذاعة", "راديو", "Radio", "FM")
// and the Arabic article, because a lone "ا"/"إ" looks like "!".
function glyphFor(name) {
    var skip = /^(إذاعة|اذاعة|راديو|radio|radyo|fm|إف|اف|ام|the|al|el)$/i
    var words = String(name || "").trim().split(/[\s\-_.|:]+/).filter(function (w) { return w !== "" })
    var pick = ""
    for (var i = 0; i < words.length; i++) {
        if (!skip.test(words[i])) { pick = words[i]; break }
    }
    if (pick === "") pick = words.length ? words[0] : ""
    pick = pick.replace(/^(ال|ٱل)(?=..)/, "").replace(/^[^\p{L}\p{N}]+/u, "")
    var ch = Array.from(pick)[0] || ""
    if (/^[اأإآٱ]$/.test(ch)) {
        // Alef alone reads badly; use the next letter instead
        var rest = Array.from(pick)
        ch = rest.length > 1 ? rest[1] : ch
    }
    return ch.toUpperCase()
}

function newId() {
    return "st" + Date.now().toString(36) + Math.floor(Math.random() * 1e5).toString(36);
}

function nameFor(p, lang) {
    return (lang === "en" && p.en) ? p.en : p.name
}

function make(p, lang) {
    return { id: newId(), name: nameFor(p, lang), url: p.url, logo: p.logo || "", glyph: p.glyph || "", color: p.color || palette[0] };
}

// First-run stations. Egypt gets the official Maspero stations; everyone else starts empty and is
// sent to Discover with their own country preselected.
function defaults(lang, country) {
    if (country === "EG") return [make(catalog[0], lang), make(catalog[1], lang)];
    return [];
}
