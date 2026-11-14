//locateconfig.js/

export const localeConfig = {
    ru: { code: "ru", name: "Русский", flag: "ru", newsSources: [{ name: "РБК", url: "https://rbc.ru" }, { name: "Коммерсантъ", url: "https://kommersant.ru" }] },
    en: { code: "en", name: "English", flag: "gb", newsSources: [{ name: "Bloomberg", url: "https://bloomberg.com" }, { name: "Reuters", url: "https://reuters.com" }] },
    de: { code: "de", name: "Deutsch", flag: "de", newsSources: [{ name: "Handelsblatt", url: "https://handelsblatt.com" }, { name: "FAZ", url: "https://faz.net" }] },
    fr: { code: "fr", name: "Français", flag: "fr", newsSources: [{ name: "Les Echos", url: "https://www.lesechos.fr/" }, { name: "Le Figaro", url: "https://www.lefigaro.fr/" }] },
    zh: { code: "zh", name: "中文", flag: "cn", newsSources: [{ name: "Caixin", url: "https://www.caixin.com" }, { name: "Sina Finance", url: "https://finance.sina.com.cn/" }] },
    jp: { code: "jp", name: "日本語", flag: "jp", newsSources: [{ name: "Nikkei", url: "https://www.nikkei.com/" }, { name: "Yahoo Finance JP", url: "https://finance.yahoo.co.jp/" }] },
    kr: { code: "kr", name: "한국어", flag: "kr", newsSources: [{ name: "Maeil Business", url: "https://www.mk.co.kr/" }, { name: "Hankyung", url: "https://www.hankyung.com/" }] },
    kz: { code: "kz", name: "Қазақша", flag: "kz", newsSources: [{ name: "Kursiv", url: "https://kursiv.media/kz/" }, { name: "Forbes KZ", url: "https://forbes.kz/" }] },
    by: { code: "by", name: "Беларуская", flag: "by", newsSources: [{ name: "Myfin BY", url: "https://myfin.by/" }, { name: "Onliner", url: "https://money.onliner.by/" }] },
    uc: { code: "uc", name: "Українська", flag: "ua", newsSources: [{ name: "Minfin", url: "https://minfin.com.ua/" }, { name: "Ekonomichna Pravda", url: "https://www.epravda.com.ua/" }] },
    pl: { code: "pl", name: "Polski", flag: "pl", newsSources: [{ name: "Bankier", url: "https://www.bankier.pl/" }, { name: "Money PL", url: "https://www.money.pl/" }] },
    fi: { code: "fi", name: "Suomi", flag: "fi", newsSources: [{ name: "Kauppalehti", url: "https://www.kauppalehti.fi/" }, { name: "Taloussanomat", url: "https://www.is.fi/taloussanomat/" }] },
    sl: { code: "sl", name: "Slovenščina", flag: "si", newsSources: [{ name: "Finance SI", url: "https://www.finance.si/" }] },
    sk: { code: "sk", name: "Slovenčina", flag: "sk", newsSources: [{ name: "Hospodárske noviny", url: "https://hnonline.sk/" }] },
    sr: { code: "sr", name: "Српски", flag: "rs", newsSources: [{ name: "NIN", url: "https://www.nin.rs/" }, { name: "Blic Biznis", url: "https://www.blic.rs/biznis" }] },
    hu: { code: "hu", name: "Magyar", flag: "hu", newsSources: [{ name: "Portfolio HU", url: "https://www.portfolio.hu/" }, { name: "Világgazdaság", url: "https://hvg.hu/gazdasag" }] },
    am: { code: "am", name: "հայերեն", flag: "am", newsSources: [{ name: "Banks AM", url: "https://banks.am/" }, { name: "B24", url: "https://b24.am/" }] }
};





export const defaultLocale = 'ru'; // Ставим русский по умолчанию