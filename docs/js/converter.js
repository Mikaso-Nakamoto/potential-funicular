import { currencyGroups, cryptoList } from './data.js';
import { updateChartLivePrice } from './chart.js';
import { t, getCurrentLocale } from './i18n.js';
import { currencyDescriptions } from './descriptions.js';
import { fetchJSON, DEMO } from './net.js';


let fromCurrency = "USD", toCurrency = "RUB", rates = {}; 

// Ошибки не глотаем: пишем в консоль с контекстом, а UI-состояния
// (демо-плашка, «нет данных») выставляет net.js.
function reportFailure(scope, error) {
    console.warn(`[Victoria Falls] ${scope}:`, error);
}

function formatRubSmart(v) {
  if (v == null || !isFinite(v)) return "—";
  const a = Math.abs(v);

  let dec = 2;
  if (a < 1) dec = 4;
  if (a < 0.1) dec = 5;
  if (a < 0.01) dec = 6;
  if (a < 0.001) dec = 7;

  return v.toFixed(dec);
}

function formatDiffSmart(v) {
  if (v == null || !isFinite(v)) return "—";
  const a = Math.abs(v);

  let dec = 4;
  if (a < 0.1) dec = 5;
  if (a < 0.01) dec = 6;
  if (a < 0.001) dec = 7;

  return v.toFixed(dec);
}

function setUpdateDateLoading() {
  const el = document.getElementById('update-date');
  if (!el) return;
  el.dataset.state = 'loading';
  el.textContent = t('loading'); // <-- переводимая "загрузка..."
}

function setUpdateDateError() {
  const el = document.getElementById('update-date');
  if (!el) return;
  el.dataset.state = 'error';
  el.textContent = t('noData');
}

function setUpdateDateReady(dateValue) {
  const el = document.getElementById('update-date');
  if (!el) return;

  el.dataset.state = 'ready';

  // можно просто вывести как есть, но лучше форматнуть под текущий язык
  const localeMap = {
    ru: 'ru-RU', en: 'en-GB', de: 'de-DE', fr: 'fr-FR', zh: 'zh-CN',
    jp: 'ja-JP', kr: 'ko-KR', pl: 'pl-PL', fi: 'fi-FI', sl: 'sl-SI',
    sk: 'sk-SK', sr: 'sr-RS', hu: 'hu-HU', kz: 'kk-KZ', by: 'be-BY',
    uc: 'uk-UA', am: 'hy-AM'
  };
  const locale = localeMap[getCurrentLocale()] || 'en-GB';

  const d = new Date(dateValue);
  el.textContent = new Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit', year: 'numeric' }).format(d);
}

async function loadCBRRates() {
    try {
        setUpdateDateLoading();
        const cbrData = await fetchJSON('https://www.cbr-xml-daily.ru/daily_json.js', DEMO.cbr);
        setUpdateDateReady(cbrData.Date || Date.now());
        rates = {};
        Object.keys(cbrData.Valute).forEach(code => {
            const valute = cbrData.Valute[code];
            rates[code] = { current: parseFloat(valute.Value) / parseFloat(valute.Nominal), previous: parseFloat(valute.Previous) / parseFloat(valute.Nominal) };
        });
        try {
            const globalData = await fetchJSON('https://open.er-api.com/v6/latest/USD', DEMO.erRates);
            const usdToRub = rates["USD"] ? rates["USD"].current : globalData.rates["RUB"];
            Object.keys(globalData.rates).forEach(code => {
                if (!rates[code] && code !== "RUB") {
                    const price = usdToRub / globalData.rates[code];
                    rates[code] = { current: price, previous: price };
                }
            });
        } catch (error) {
            // Необязательный источник: ЦБ РФ уже дал нам базовые курсы
            reportFailure('курсы open.er-api.com', error);
        }
        updateConversion(); updateSidebarRates();
    } catch (error) {
        reportFailure('курсы ЦБ РФ', error);
        setUpdateDateError();
    }
}

async function loadCryptoRates() {
    try {
        const data = await fetchJSON('https://api.binance.com/api/v3/ticker/24hr', DEMO.binance24);
        const binanceRates = {};
        data.forEach(ticker => { binanceRates[ticker.symbol] = { price: parseFloat(ticker.lastPrice), percent: parseFloat(ticker.priceChangePercent) }; });

        const usdToRub = rates["USD"] ? rates["USD"].current : 90;

        document.querySelectorAll('#CriptoVVV li').forEach(li => {
            const symbol = li.dataset.symbol; if (!symbol) return;
            const priceEl = li.querySelector('.crypto-price');
            const changeEl = li.querySelector('.crypto-change');

            let coinPriceUsd = 0; 
            if (["USDT", "USDC", "USDE"].includes(symbol)) {
                coinPriceUsd = 1;
                if(priceEl) priceEl.textContent = "1.0000";
                if(changeEl) changeEl.innerHTML = `<span class="change-neutral">— 0.00%</span>`;
            } else {
                const coinData = binanceRates[symbol + "USDT"];
                if (coinData) {
                    coinPriceUsd = coinData.price;
                    if (priceEl && changeEl) {
                        priceEl.textContent = coinPriceUsd.toFixed(coinPriceUsd < 1 ? 6 : 2);
                        if (symbol === 'BTC' || symbol === 'ETH') updateChartLivePrice(symbol, coinPriceUsd);
                        let colorClass = "change-neutral", arrow = "—", sign = "";
                        if (coinData.percent > 0) { colorClass = "change-up"; arrow = "↑"; sign = "+"; } else if (coinData.percent < 0) { colorClass = "change-down"; arrow = "↓"; }
                        changeEl.innerHTML = `<span class="${colorClass}">${arrow} ${Math.abs(coinData.percent).toFixed(2)}%</span>`;
                    }
                } else if (priceEl) priceEl.textContent = t('noData');
            }
            if (coinPriceUsd > 0) rates[symbol] = { current: coinPriceUsd * usdToRub, previous: coinPriceUsd * usdToRub };

            const gridRateEl = document.getElementById(`grid-rate-${symbol}`);
            if (gridRateEl && coinPriceUsd > 0) gridRateEl.textContent = coinPriceUsd.toFixed(coinPriceUsd < 1 ? 6 : 2) + " $";
        });
        updateConversion();
    } catch (error) {
        reportFailure('курсы Binance', error);
    }
}

async function loadMarketAnalytics() {
    try {
        const data = await fetchJSON('https://api.alternative.me/fng/?limit=1', DEMO.fng);
        if (data && data.data && data.data[0]) {
            const value = parseInt(data.data[0].value);
            const valueEl = document.getElementById('fng-value');
            const statusEl = document.getElementById('fng-status');
            const needleEl = document.getElementById('fng-needle');

            if (valueEl && statusEl && needleEl) {
                valueEl.textContent = value;
                let tone = "neutral", statusKey = "fngNeutral";
                if (value <= 25) { tone = "extreme-fear"; statusKey = "fngExtremeFear"; }
                else if (value <= 45) { tone = "fear"; statusKey = "fngFear"; }
                else if (value <= 54) { tone = "neutral"; statusKey = "fngNeutral"; }
                else if (value <= 74) { tone = "greed"; statusKey = "fngGreed"; }
                else { tone = "extreme-greed"; statusKey = "fngExtremeGreed"; }

                valueEl.dataset.tone = tone; statusEl.dataset.tone = tone;
                statusEl.textContent = t(statusKey);
                needleEl.style.transform = `rotate(${(value / 100) * 180 - 90}deg)`;
            }
        }
    } catch (error) {
        reportFailure('индекс страха и жадности', error);
    }
}

async function loadAltcoinSeason() {
    try {
        const data = await fetchJSON('https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=70&page=1&sparkline=false&price_change_percentage=30d', DEMO.coingeckoMarkets);
        if (!Array.isArray(data)) throw new Error("");

        const ignoreList = ['tether', 'usd-coin', 'steth', 'dai', 'wrapped-bitcoin', 'first-digital-usd', 'we-eth', 'usdd'];
        const top50 = data.filter(c => !ignoreList.includes(c.id)).slice(0, 51); 
        const btc = top50.find(c => c.symbol === 'btc');
        if (!btc || btc.price_change_percentage_30d_in_currency === undefined) throw new Error("");
        
        let betterCount = 0, totalCount = 0;
        top50.forEach(coin => {
            if (coin.symbol !== 'btc' && coin.price_change_percentage_30d_in_currency != null) {
                totalCount++; if (coin.price_change_percentage_30d_in_currency > btc.price_change_percentage_30d_in_currency) betterCount++;
            }
        });

        if (totalCount === 0) throw new Error("");
        updateAltSeasonDOM(Math.round((betterCount / totalCount) * 100));
    } catch (e) { updateAltSeasonDOM(35); }
}

function updateAltSeasonDOM(value) {
    const valueEl = document.getElementById('alt-value'), statusEl = document.getElementById('alt-status'), needleEl = document.getElementById('alt-needle');
    if (valueEl && statusEl && needleEl) {
        valueEl.textContent = value;
        let color = "#dbdbdb", statusKey = "altNeutral";
        if (value <= 25) { color = "#f7931a"; statusKey = "altBtcSeason"; }
        else if (value <= 45) { color = "#ffcc00"; statusKey = "altBtcLean"; }
        else if (value <= 55) { color = "#dbdbdb"; statusKey = "altNeutral"; }
        else if (value <= 75) { color = "#99cc33"; statusKey = "altAltLean"; }
        else { color = "#00cc66"; statusKey = "altSeasonText"; }

        valueEl.style.color = color; statusEl.style.color = color;
        statusEl.textContent = t(statusKey);
        needleEl.style.transform = `rotate(${(value / 100) * 180 - 90}deg)`;
    }
}

function getRate(code) { return code === "RUB" ? 1 : (rates[code] ? rates[code].current : null); }
function calculateRate(from, to) { if (from === to) return 1; const f = getRate(from), t = getRate(to); return (!f || !t) ? null : f / t; }

function updateCurrencyDisplay(side, code) {
    const flagEl = document.getElementById(side + '-flag'), codeEl = document.getElementById(side + '-code');
    if (!flagEl || !codeEl) return;
    const data = getCurrencyData(code); if (!data) return;
    flagEl.innerHTML = data.type === 'fiat' ? `<span class="fi fi-${data.flag}"></span>` : `<img class="currency-icon currency-icon--lg" src="./iconss/${data.icon}" alt="${data.code}" loading="lazy" decoding="async">`;
    codeEl.textContent = data.code;
}

function updateConversion(event) {
    const fromInput = document.getElementById('from-amount'), toInput = document.getElementById('to-amount');
    let isReverse = false;
    if (event && (event.target.id === 'from-amount' || event.target.id === 'to-amount')) {
        let t = event.target; isReverse = t.id === 'to-amount';
        let val = t.value.replace(/,/g, '.').replace(/[^0-9.]/g, '');
        let parts = val.split('.'); if (parts.length > 2) val = parts[0] + '.' + parts.slice(1).join('');
        if (t.value !== val) t.value = val;
    }
    document.getElementById('from-currency-name').textContent = fromCurrency; document.getElementById('to-currency-name').textContent = toCurrency;
    const rate = calculateRate(fromCurrency, toCurrency);
    const format = (num) => { if (num === 0) return "0.0000"; if (Math.abs(num) < 0.0001) return num.toFixed(8); if (Math.abs(num) < 0.01) return num.toFixed(6); return num.toFixed(4); };

    if (rate !== null) {
        document.getElementById('exchange-rate').textContent = format(rate);
        if (!isReverse) { let a = parseFloat(fromInput.value); isNaN(a) || fromInput.value === '' ? toInput.value = '' : toInput.value = format(a * rate); }
        else { let a = parseFloat(toInput.value); isNaN(a) || toInput.value === '' ? fromInput.value = '' : fromInput.value = format(a / rate); }
    } else {
        (!isReverse) ? toInput.value = "—" : fromInput.value = "—"; document.getElementById('exchange-rate').textContent = "—";
    }
}

function updateInfoPanel(code) {
    const data = getCurrencyData(code);
    const nameEl = document.getElementById('info-currency-name');
    const descEl = document.getElementById('info-description');
    if (!data) return;
    
    // Берем текущий язык
    const lang = getCurrentLocale();
    
    // Берем описание для этого языка (если нет - берем русское, если нет - сообщение об ошибке)
    const descDict = currencyDescriptions[lang] || currencyDescriptions.ru;
    const description = descDict[code] || currencyDescriptions.ru[code] || t('noInfo');

    nameEl.textContent = `${code} — ${data.type === 'fiat' ? t('fiatCurrency') : t('cryptoCurrency')}`;
    descEl.textContent = description;
}

export function updateSidebarRates() {
    Object.keys(rates).forEach(code => {
        const data = rates[code]; if (!data) return;
        const gridRateEl = document.getElementById(`grid-rate-${code}`);
        const cardEl = document.querySelector(`.currency-card[data-grid-code="${code}"]`); 
        
        if (gridRateEl) {
  gridRateEl.textContent = (code === "RUB") ? "1.00 ₽" : `${formatRubSmart(data.current)} ₽`;
}        if (cardEl && code !== "RUB") {
            const diff = data.current - data.previous;
            cardEl.classList.remove('trend-up', 'trend-down');
            if (diff > 0.0001) cardEl.classList.add('trend-up'); else if (diff < -0.0001) cardEl.classList.add('trend-down');
        }

        const sidebarLi = document.querySelector(`.left-sidebar-content li[data-code="${code}"]`);
        if (sidebarLi) {
            const rateEl = sidebarLi.querySelector('.rate'), changeEl = sidebarLi.querySelector('.change');
            if (code === "RUB") { if (rateEl) rateEl.textContent = "1 ₽"; if (changeEl) changeEl.innerHTML = `<span class="change-neutral">— 0.00 (0.00%)</span>`; return; }
            if (rateEl && changeEl) {
                rateEl.textContent = `${formatRubSmart(data.current)} ₽`;

const diff = data.current - data.previous;
const percent = data.previous ? (diff / data.previous) * 100 : 0;

let colorClass = "change-neutral", arrow = "—", sign = "";
if (diff > 0.001) { colorClass = "change-up"; arrow = "↑"; sign = "+"; }
else if (diff < -0.001) { colorClass = "change-down"; arrow = "↓"; }

changeEl.innerHTML =
  `<span class="${colorClass}">${arrow} ${formatDiffSmart(diff)} (${sign}${Math.abs(percent).toFixed(2)}%)</span>`;            }
        }
    });
}

function renderList(containerId, selectedCode) {
    const container = document.getElementById(containerId); if (!container) return;
    container.innerHTML = '';
    const all = [...Object.values(currencyGroups).flat().map(i => ({...i, type: 'fiat'})), ...cryptoList.map(i => ({code: i.symbol, type: 'crypto', icon: i.icon}))];

    all.forEach(curr => {
        const div = document.createElement('div'); div.className = `currency-item ${curr.code === selectedCode ? 'active' : ''}`;
        div.innerHTML = curr.type === 'fiat' ? `<span class="fi fi-${curr.flag}"></span><span class="code">${curr.code}</span>` : `<img class="currency-icon" src="./iconss/${curr.icon}" alt="${curr.code}" loading="lazy" decoding="async"> <span class="code">${curr.code}</span>`;
        div.onclick = () => {
            if (containerId === 'from-list') fromCurrency = curr.code; else toCurrency = curr.code;
            renderList('from-list', fromCurrency); renderList('to-list', toCurrency);
            updateCurrencyDisplay('from', fromCurrency); updateCurrencyDisplay('to', toCurrency); updateConversion();
            if (containerId === 'to-list') updateInfoPanel(toCurrency);
        };
        container.appendChild(div);
    });
}

function getCurrencyData(code) {
    for (let group of Object.values(currencyGroups)) { const found = group.find(i => i.code === code); if (found) return { ...found, type: 'fiat' }; }
    const crypto = cryptoList.find(i => i.symbol === code); return crypto ? { code: crypto.symbol, type: 'crypto', icon: crypto.icon } : null;
}

async function loadMoexStocks() {
    try {
        const data = await fetchJSON('https://iss.moex.com/iss/engines/stock/markets/shares/boards/TQBR/securities.json?iss.meta=off', DEMO.moex);
        const md = data.marketdata.data, sec = data.securities.data;
        const mdI = { secid: data.marketdata.columns.indexOf('SECID'), last: data.marketdata.columns.indexOf('LAST'), pct: data.marketdata.columns.indexOf('LASTTOPREVPRICE') };
        const secI = { secid: data.securities.columns.indexOf('SECID'), prev: data.securities.columns.indexOf('PREVPRICE') };

        document.querySelectorAll('#moex-list li').forEach(li => {
            const ticker = li.dataset.symbol; if (!ticker) return;
            const mdRow = md.find(r => r[mdI.secid] === ticker), secRow = sec.find(r => r[secI.secid] === ticker);
            const priceEl = li.querySelector('.moex-price'), changeEl = li.querySelector('.market-change');

            if (mdRow && secRow && priceEl && changeEl) {
                const price = mdRow[mdI.last] !== null ? mdRow[mdI.last] : secRow[secI.prev];
                priceEl.textContent = price != null ? price.toFixed(2) : "—";
                const pct = mdRow[mdI.pct];
                if (pct !== null) {
                    let c = "change-neutral", a = "—";
                    if (pct > 0) { c = "change-up"; a = "↑"; } else if (pct < 0) { c = "change-down"; a = "↓"; }
                    changeEl.innerHTML = `<span class="${c}">${a} ${Math.abs(pct).toFixed(2)}%</span>`;
                } else changeEl.innerHTML = `<span class="change-neutral">— 0.00%</span>`;
            }
        });
    } catch (error) {
        reportFailure('акции MOEX', error);
        document.querySelectorAll('#moex-list .moex-price').forEach(el => { el.textContent = '—'; });
    }
}

export function swapCurrencies() {
    [fromCurrency, toCurrency] = [toCurrency, fromCurrency];
    renderList('from-list', fromCurrency);
    renderList('to-list', toCurrency);
    updateCurrencyDisplay('from', fromCurrency);
    updateCurrencyDisplay('to', toCurrency);
    updateInfoPanel(toCurrency);
    updateConversion();
}

export async function initConverter() {
    const swapBtn = document.getElementById('swap-btn');
    if (swapBtn && !swapBtn.dataset.bound) {
        swapBtn.dataset.bound = '1';
        swapBtn.addEventListener('click', swapCurrencies);
    }
    renderList('from-list', fromCurrency); renderList('to-list', toCurrency);
    
    // Передаем переведенные заголовки категорий!
    initAllCurrenciesGrid();

    updateCurrencyDisplay('from', fromCurrency); updateCurrencyDisplay('to', toCurrency); updateInfoPanel(toCurrency);
    await loadCBRRates(); loadCryptoRates(); loadMarketAnalytics(); loadMoexStocks(); loadAltcoinSeason();
    setInterval(loadCryptoRates, 10000); setInterval(loadMoexStocks, 15000); setInterval(loadCBRRates, 3600000); setInterval(loadMarketAnalytics, 3600000);
    document.getElementById('from-amount').addEventListener('input', updateConversion); document.getElementById('to-amount').addEventListener('input', updateConversion);
}

// Заглушка для сетки (вызывается при старте)
function initAllCurrenciesGrid() {
    const grid = document.getElementById('all-currencies-grid'), toggleBtn = document.getElementById('toggle-grid-view');
    if (!grid) return; grid.innerHTML = '';
    if (toggleBtn) toggleBtn.onclick = () => { grid.classList.toggle('list-view'); toggleBtn.textContent = grid.classList.contains('list-view') ? '▤' : '☰'; };
    const fiats = Object.values(currencyGroups).flat().map(i => ({...i, type: 'fiat'}));
    const cryptos = cryptoList.map(i => ({code: i.symbol, type: 'crypto', icon: i.icon}));

    const renderCategory = (title, items) => {
        const titleEl = document.createElement('div'); titleEl.className = 'grid-category-title'; titleEl.textContent = title; grid.appendChild(titleEl);
        items.forEach(curr => {
            if (curr.code === 'RUB') return;
            const card = document.createElement('div'); card.className = 'currency-card'; card.dataset.gridCode = curr.code;
            let iconHtml = curr.type === 'fiat' ? `<span class="fi fi-${curr.flag}"></span>` : `<img src="./iconss/${curr.icon}" alt="" aria-hidden="true" loading="lazy" decoding="async">`;
            card.innerHTML = `<div class="icon-wrapper">${iconHtml}</div><div class="card-code">${curr.code}</div><div class="card-rate" id="grid-rate-${curr.code}">${t('loading')}</div>`;
            card.addEventListener('click', () => { toCurrency = curr.code; renderList('to-list', toCurrency); updateCurrencyDisplay('to', toCurrency); updateConversion(); updateInfoPanel(toCurrency); document.querySelector('.converter-wrapper').scrollIntoView({ behavior: 'smooth' }); });
            grid.appendChild(card);
        });
    };
    renderCategory(t('fiatCategory'), fiats); renderCategory(t('cryptoCategory'), cryptos);
}

