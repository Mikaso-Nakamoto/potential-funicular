// js/demoData.js
// Синтетические данные на случай недоступности внешних API.
// Формы объектов повторяют реальные ответы:
//   ЦБ РФ (cbr-xml-daily), open.er-api.com, Binance, Alternative.me,
//   CoinGecko и MOEX ISS. Никакой логики — только правдоподобные числа.

// Детерминированный генератор: данные не «прыгают» между перезагрузками.
function makeRandom(seed) {
    let s = seed >>> 0;
    return () => {
        s = (s * 1664525 + 1013904223) >>> 0;
        return s / 4294967296;
    };
}

const rand = makeRandom(20261114);
const jitter = (base, spread = 0.012) => base * (1 + (rand() * 2 - 1) * spread);
const round = (n, d = 4) => Number(n.toFixed(d));

// Курс рубля к доллару «на сегодня»
const USD_RUB = 82.4;

// ---------------------------------------------------------------- ЦБ РФ
const CBR_BASE = {
    USD: 82.4, EUR: 89.6, GBP: 104.8, JPY: 0.53, CNY: 11.4, CHF: 95.2,
    CAD: 58.9, AUD: 53.6, NZD: 49.1, SEK: 7.6, NOK: 7.4, DKK: 12.0,
    PLN: 20.6, CZK: 3.55, HUF: 0.21, HKD: 10.6, SGD: 61.2, KRW: 0.058,
    INR: 0.98, TRY: 2.31, BRL: 15.1, ZAR: 4.42, MXN: 3.98, THB: 2.34,
    MYR: 18.6, IDR: 0.0051, PHP: 1.42, AED: 22.4, SAR: 22.0, QAR: 22.6,
    KWD: 268.1, BHD: 218.5, OMR: 214.0, JOD: 116.2, ILS: 22.3,
    EGP: 1.62, BYN: 25.1, KZT: 0.168, UAH: 1.94, AMD: 0.21, GEL: 30.4,
    AZN: 48.5, TJS: 7.55, UZS: 0.0065,
};

const NOMINAL = { JPY: 100, KRW: 1000, IDR: 10000, UZS: 10000, AMD: 100, HUF: 100 };

function buildValute(map, offset) {
    const out = {};
    Object.entries(map).forEach(([code, value]) => {
        const nominal = NOMINAL[code] || 1;
        const raw = value * nominal;
        const previous = raw * (1 + offset(code));
        out[code] = {
            ID: `R0${code}`,
            NumCode: '000',
            CharCode: code,
            Nominal: nominal,
            Name: code,
            Value: round(raw, 4),
            Previous: round(previous, 4),
        };
    });
    return out;
}

const drift = (code) => {
    const seed = code.charCodeAt(0) + code.charCodeAt(1);
    return ((seed % 11) - 5) / 900;
};

export function cbr() {
    return {
        Date: new Date().toISOString(),
        PreviousDate: new Date(Date.now() - 864e5).toISOString(),
        Valute: buildValute(
            Object.fromEntries(Object.entries(CBR_BASE).map(([c, v]) => [c, jitter(v)])),
            drift
        ),
    };
}

export function cbrPrevious() {
    return {
        Date: new Date(Date.now() - 864e5).toISOString(),
        PreviousDate: new Date(Date.now() - 1728e5).toISOString(),
        Valute: buildValute(CBR_BASE, drift),
    };
}

// ------------------------------------------------- open.er-api.com
export function erRates() {
    const rates = { USD: 1, RUB: USD_RUB, EUR: 0.92, GBP: 0.786, JPY: 155.2, CNY: 7.24 };
    return {
        result: 'success',
        base_code: 'USD',
        time_last_update_unix: Math.floor(Date.now() / 1000),
        rates,
    };
}

// ------------------------------------------------- Binance
const BINANCE_BASE = {
    BTC: 68420, ETH: 3310, BNB: 582, SOL: 152.4, XRP: 0.548, ADA: 0.412,
    DOGE: 0.128, TON: 5.12, TRX: 0.152, LTC: 82.4, LINK: 14.6, AVAX: 27.8,
    DOT: 5.42, MATIC: 0.412, NEAR: 4.12, ATOM: 6.28, UNI: 7.42, PEPE: 0.0000082,
    SHIB: 0.0000178, USDT: 1, USDC: 1, USDE: 1,
};

export function binance24() {
    return Object.entries(BINANCE_BASE).map(([symbol, price]) => {
        const percent = ((symbol.charCodeAt(0) % 13) - 6) / 1.4;
        return {
            symbol: `${symbol}USDT`,
            lastPrice: String(round(jitter(price, 0.004), 8)),
            priceChangePercent: String(round(percent, 3)),
            highPrice: String(round(price * 1.03, 6)),
            lowPrice: String(round(price * 0.97, 6)),
            quoteVolume: String(Math.round(price * 1e4)),
        };
    });
}

export function tickerPrice(symbol = 'BTCUSDT') {
    const base = BINANCE_BASE[symbol.replace('USDT', '')] ?? 100;
    return { symbol, price: String(round(jitter(base, 0.002), 8)) };
}

// 60 месячных свечей (символ → правдоподобный тренд)
export function klines(symbol = 'BTCUSDT') {
    const code = symbol.replace('USDT', '');
    const base = BINANCE_BASE[code] ?? 100;
    const r = makeRandom(code.split('').reduce((a, c) => a + c.charCodeAt(0), 7));
    const candles = [];
    let price = base * 0.35;
    const now = Date.now();
    for (let i = 59; i >= 0; i--) {
        const open = price;
        const drift = (r() - 0.42) * 0.22;
        const close = open * (1 + drift);
        const high = Math.max(open, close) * (1 + r() * 0.07);
        const low = Math.min(open, close) * (1 - r() * 0.07);
        price = close;
        const t = now - i * 30 * 864e5;
        candles.push([
            t, String(round(open, 6)), String(round(high, 6)),
            String(round(low, 6)), String(round(close, 6)), String(Math.round(r() * 9e4)),
            t + 30 * 864e5 - 1, '0', 0, '0', '0', '0',
        ]);
    }
    // последняя точка — на текущей цене актива
    candles[candles.length - 1][4] = String(round(base, 6));
    return candles;
}

// ------------------------------------------------- Alternative.me
export function fng() {
    return { data: [{ value: '54', value_classification: 'Neutral', timestamp: String(Math.floor(Date.now() / 1000)) }] };
}

// ------------------------------------------------- CoinGecko
const CG_TOP = [
    ['bitcoin', 'btc', 14.2], ['ethereum', 'eth', 9.1], ['binancecoin', 'bnb', 6.4],
    ['solana', 'sol', 21.8], ['ripple', 'xrp', -3.2], ['cardano', 'ada', -8.4],
    ['dogecoin', 'doge', 18.6], ['the-open-network', 'ton', 4.2], ['tron', 'trx', 2.1],
    ['chainlink', 'link', 11.4], ['avalanche-2', 'avax', -1.8], ['polkadot', 'dot', -6.2],
    ['near', 'near', 7.8], ['cosmos', 'atom', -4.5], ['uniswap', 'uni', 3.1],
    ['litecoin', 'ltc', -2.4], ['pepe', 'pepe', 42.6], ['shiba-inu', 'shib', 12.2],
];

export function coingeckoMarkets() {
    const rows = CG_TOP.map(([id, symbol, pct]) => ({
        id,
        symbol,
        name: id,
        current_price: 0,
        price_change_percentage_30d_in_currency: pct,
    }));
    // добираем до 70 записей «шумом», как в реальном ответе
    let i = 0;
    while (rows.length < 70) {
        const pct = ((i * 37) % 60) - 25;
        rows.push({
            id: `asset-${i}`,
            symbol: `a${i}`,
            name: `Asset ${i}`,
            current_price: 0,
            price_change_percentage_30d_in_currency: pct,
        });
        i++;
    }
    return rows;
}

// ------------------------------------------------- MOEX ISS
const MOEX = [
    ['SBER', 318.4, 1.24], ['GAZP', 132.6, -0.86], ['LKOH', 7120, 0.42],
    ['GMKN', 142.8, -1.12], ['ROSN', 574.2, 0.68], ['NVTK', 1216, 1.42],
    ['TATN', 648.8, -0.34], ['MTSS', 289.6, 0.24], ['MGNT', 5210, -2.14],
    ['AFLT', 68.4, 2.86], ['VTBR', 0.0241, -0.62], ['MOEX', 214.8, 0.94],
];

export function moex() {
    const columns = ['SECID', 'LAST', 'LASTTOPREVPRICE'];
    const secColumns = ['SECID', 'PREVPRICE'];
    return {
        marketdata: {
            columns,
            data: MOEX.map(([secid, last, pct]) => [secid, jitter(last, 0.004), pct]),
        },
        securities: {
            columns: secColumns,
            data: MOEX.map(([secid, last, pct]) => [secid, last / (1 + pct / 100)]),
        },
    };
}
