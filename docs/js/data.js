// js/data.js
export const currencyGroups = {
    major: [
        { code: "USD", flag: "us", name: "USD" },
        { code: "EUR", flag: "eu", name: "EUR" },
        { code: "GBP", flag: "gb", name: "GBP" },
        { code: "JPY", flag: "jp", name: "JPY" },
        { code: "CNY", flag: "cn", name: "CNY" },
        { code: "CHF", flag: "ch", name: "CHF" },
    ],
    other: [
        { code: "CAD", flag: "ca", name: "CAD" },
        { code: "AUD", flag: "au", name: "AUD" },
        { code: "NZD", flag: "nz", name: "NZD" },
        { code: "SEK", flag: "se", name: "SEK" },
        { code: "NOK", flag: "no", name: "NOK" },
        { code: "DKK", flag: "dk", name: "DKK" },
        { code: "PLN", flag: "pl", name: "PLN" },
        { code: "CZK", flag: "cz", name: "CZK" },
        { code: "HUF", flag: "hu", name: "HUF" }
    ],
    asia: [
        { code: "HKD", flag: "hk", name: "HKD" },
        { code: "SGD", flag: "sg", name: "SGD" },
        { code: "KRW", flag: "kr", name: "KRW" },
        { code: "INR", flag: "in", name: "INR" },
        { code: "TRY", flag: "tr", name: "TRY" },
        { code: "BRL", flag: "br", name: "BRL" },
        { code: "ZAR", flag: "za", name: "ZAR" },
        { code: "MXN", flag: "mx", name: "MXN" },
        { code: "THB", flag: "th", name: "THB" },
        { code: "MYR", flag: "my", name: "MYR" },
        { code: "IDR", flag: "id", name: "IDR" },
        { code: "PHP", flag: "ph", name: "PHP" }
    ],
    middleEast: [
        { code: "AED", flag: "ae", name: "AED" },
        { code: "SAR", flag: "sa", name: "SAR" },
        { code: "QAR", flag: "qa", name: "QAR" },
        { code: "KWD", flag: "kw", name: "KWD" },
        { code: "BHD", flag: "bh", name: "BHD" },
        { code: "OMR", flag: "om", name: "OMR" },
        { code: "JOD", flag: "jo", name: "JOD" },
        { code: "ILS", flag: "il", name: "ILS" },
        { code: "EGP", flag: "eg", name: "EGP" }
    ],
    cis: [
        { code: "RUB", flag: "ru", name: "RUB" }, 
        { code: "BYN", flag: "by", name: "BYN" },
        { code: "KZT", flag: "kz", name: "KZT" },
        { code: "UAH", flag: "ua", name: "UAH" },
        { code: "AMD", flag: "am", name: "AMD" },
        { code: "GEL", flag: "ge", name: "GEL" },
        { code: "AZN", flag: "az", name: "AZN" },
        { code: "TJS", flag: "tj", name: "TJS" },
        { code: "UZS", flag: "uz", name: "UZS" }
    ]
};

export const cryptoList = [
    { symbol: "BTC",  icon: "btc.svg",   className: "btci",    price: "0.00", unit: "USDT" },
    { symbol: "ETH",  icon: "eth.svg",   className: "ethi",    price: "0.00", unit: "USDT" },
    { symbol: "USDT", icon: "usdt.svg",  className: "usdti",   price: "1.00", unit: "USD" },
    { symbol: "USDC", icon: "usdc.svg",  className: "usdci",   price: "1.00", unit: "USD" },
    { symbol: "USDE", icon: "usde.svg",  className: "usdei",   price: "1.00", unit: "USD" },
    { symbol: "BNB",  icon: "bnb.svg",   className: "bnbi",    price: "0.00", unit: "USDT" },
    { symbol: "SOL",  icon: "sol.svg",   className: "soli",    price: "0.00", unit: "USDT" },
    { symbol: "XRP",  icon: "xrp.svg",   className: "xmpi",    price: "0.00", unit: "USDT" },
    { symbol: "LTC",  icon: "ltc.svg",   className: "ltci",    price: "0.00", unit: "USDT" },
    { symbol: "DOGE", icon: "doge.svg",  className: "dogei",   price: "0.00", unit: "USDT" },
    { symbol: "TRUMP",icon: "Trump.png", className: "trumpi",  price: "0.00", unit: "USDT" },
    { symbol: "PEPE", icon: "pepe.svg",  className: "pepei",   price: "0.00", unit: "USDT" },
    { symbol: "TON",  icon: "ton.svg",   className: "toni",    price: "0.00", unit: "USDT" },
    { symbol: "TRX",  icon: "tron.svg",  className: "trx",     price: "0.00", unit: "USDT" },
    { symbol: "ADA",  icon: "ada.svg",   className: "adai",    price: "0.00", unit: "USDT" },
    { symbol: "AVAX", icon: "avax.svg",  className: "avaxi",   price: "0.00", unit: "USDT" },
    { symbol: "LINK", icon: "link.svg",  className: "linki",   price: "0.00", unit: "USDT" },
    { symbol: "PAXG", icon: "paxg.svg",  className: "paxgi",   price: "0.00", unit: "USDT", extra: "<small>(токенизированное золото)</small>" },
    { symbol: "XAUT", icon: "xaut.svg",  className: "xauti",   price: "0.00", unit: "USDT", extra: "<small>(Tether Gold)</small>" }
];

// ... (оставь currencyGroups и cryptoList как были)

export const moexStocks = [
    { symbol: "MOEX", name: "Московская биржа", key: "moexStock" },
    { symbol: "SBER", name: "Сбербанк", key: "sber" },
    { symbol: "SBERP", name: "Сбербанк (преф.)", key: "sberP" },
    { symbol: "VTBR", name: "ВТБ", key: "vtb" },
    { symbol: "T", name: "Т-Банк", key: "tBank" },
    { symbol: "YDEX", name: "Яндекс", key: "yandex" },
    { symbol: "GAZP", name: "Газпром", key: "gazprom" },
    { symbol: "LKOH", name: "Лукойл", key: "lukoil" },
    { symbol: "ROSN", name: "Роснефть", key: "rosneft" },
    { symbol: "TATN", name: "Татнефть", key: "tatneft" },
    { symbol: "NVTK", name: "Новатэк", key: "novatek" },
    { symbol: "SNGS", name: "Сургутнефтегаз", key: "surgut" },
    { symbol: "MGNT", name: "Магнит", key: "magnit" },
    { symbol: "CHMF", name: "Мечел", key: "mechel" },
    { symbol: "ALRS", name: "Алроса", key: "alrosa" },
    { symbol: "RGSS", name: "Росгосстрах", key: "rosgos" },
    { symbol: "AFKS", name: "АФК Система", key: "afk" },
];