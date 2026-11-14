//chart.js/ 

import { t } from './i18n.js'; // Подключаем перевод
import { fetchJSON, DEMO } from './net.js';

let myChart = null;
let currentChartCoin = 'BTC'; 

const cryptoFacts = {
  BTC: { color: '#f7931a', facts: {
    "2017-12": "btc_fact_2017_12",
    "2018-12": "btc_fact_2018_12",
    "2020-05": "btc_fact_2020_05",
    "2021-11": "btc_fact_2021_11",
    "2022-11": "btc_fact_2022_11",
    "2024-01": "btc_fact_2024_01",
    "2024-03": "btc_fact_2024_03",
  }},
  ETH: { color: '#627eea', facts: {
    "2017-12": "eth_fact_2017_12",
    "2018-12": "eth_fact_2018_12",
    "2020-08": "eth_fact_2020_08",
    "2021-11": "eth_fact_2021_11",
    "2022-09": "eth_fact_2022_09",
    "2024-05": "eth_fact_2024_05",
  }},
  SOL: { color: '#00ffa3', facts: {
    "2020-03": "sol_fact_2020_03",
    "2021-11": "sol_fact_2021_11",
    "2022-11": "sol_fact_2022_11",
    "2023-12": "sol_fact_2023_12",
    "2024-03": "sol_fact_2024_03",
  }},
  BNB: { color: '#f3ba2f', facts: {
    "2017-07": "bnb_fact_2017_07",
    "2020-09": "bnb_fact_2020_09",
    "2021-05": "bnb_fact_2021_05",
    "2023-11": "bnb_fact_2023_11",
    "2024-06": "bnb_fact_2024_06",
  }},
  XRP: { color: '#00aae4', facts: {
    "2018-01": "xrp_fact_2018_01",
    "2020-12": "xrp_fact_2020_12",
    "2021-04": "xrp_fact_2021_04",
    "2023-07": "xrp_fact_2023_07",
    "2024-08": "xrp_fact_2024_08",
  }}
};

async function fetchBinanceData(coin) {
    const symbol = coin + 'USDT';
    try {
        const [klines, livePrice] = await Promise.all([
            fetchJSON(`https://api.binance.com/api/v3/klines?symbol=${symbol}&interval=1M&limit=1000`, () => DEMO.klines(symbol), { validate: d => Array.isArray(d) && d.length > 0 }),
            fetchJSON(`https://api.binance.com/api/v3/ticker/price?symbol=${symbol}`, () => DEMO.tickerPrice(symbol))
        ]);
        return { klines, exactCurrentPrice: parseFloat(livePrice.price) };
    } catch (error) { return null; }
}

const verticalLinePlugin = {
    id: 'verticalLine',
    afterDraw: chart => {
        if (chart.tooltip?._active?.length) {
            const ctx = chart.ctx; const x = chart.tooltip._active[0].element.x;
            ctx.save(); ctx.beginPath(); ctx.moveTo(x, chart.scales.y.top); ctx.lineTo(x, chart.scales.y.bottom);
            ctx.lineWidth = 1; ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)'; ctx.setLineDash([5, 5]); ctx.stroke(); ctx.restore();
        }
    }
};

export async function initCryptoChart() {
    const ctx = document.getElementById('cryptoChart');
    if (!ctx) return;

    async function renderChart(coin) {
        const titleEl = document.querySelector('.chart-title');
        if (typeof Chart === 'undefined') {
            if (titleEl) titleEl.textContent = t('chartError');
            return;
        }
        if (titleEl && !isTvMode) titleEl.textContent = t('chartLoading');

        const rawData = await fetchBinanceData(coin);
        if (!rawData || rawData.klines.length === 0) {
            if (titleEl) titleEl.textContent = t('chartError');
            return;
        }

        const coinColor = cryptoFacts[coin].color;
        const factData = cryptoFacts[coin].facts;
        const labels = [], prices = [], pointRadiuses = [], pointColors = [], factsArray = []; 
        const factKeys = [];   

        rawData.klines.forEach((kline, index) => {
            const dateObj = new Date(kline[0]);
            const ym = `${dateObj.getFullYear()}-${String(dateObj.getMonth() + 1).padStart(2, '0')}`;
            labels.push(`${String(dateObj.getMonth() + 1).padStart(2, '0')}.${dateObj.getFullYear()}`);
            prices.push(index === rawData.klines.length - 1 ? rawData.exactCurrentPrice : parseFloat(kline[4]));
            const k = factData[ym] || null;
factKeys.push(k);
pointRadiuses.push(k ? 5 : 0);
pointColors.push(k ? '#fff' : 'transparent');
        });

        if (myChart) myChart.destroy();
        myChart = new Chart(ctx, {
            type: 'line',
            data: { labels, datasets: [{ label: coin, data: prices, borderColor: coinColor, backgroundColor: 'transparent', borderWidth: 2, tension: 0.15, pointRadius: pointRadiuses, pointBackgroundColor: pointColors, pointBorderColor: coinColor, pointBorderWidth: 2, pointHoverRadius: 6, pointHoverBackgroundColor: 'rgba(112, 77, 0, 0.14)', pointHoverBorderColor: coinColor, pointHoverBorderWidth: 3 }] },
            plugins: [verticalLinePlugin],
            options: {
                responsive: true, maintainAspectRatio: false, interaction: { mode: 'index', intersect: false },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: 'rgba(0, 0, 0, 0.95)', titleColor: '#aaa', bodyColor: '#fff', titleFont: { size: 12, weight: 'normal' }, bodyFont: { size: 14, weight: 'bold' }, padding: 12, cornerRadius: 8, displayColors: false, borderWidth: 1, borderColor: 'rgba(255, 255, 255, 0.1)',
                        callbacks: {
                            title: function(context) { return `${t('date')}: ${context[0].label}`; },
                            label: function(context) { return `${t('price')}: $${context.raw.toLocaleString('en-US', { maximumFractionDigits: 2 })}`; }
                        }
                    }
                },
                scales: { x: { grid: { display: false }, ticks: { color: '#777', maxTicksLimit: 8 } }, y: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#777' }, position: 'right' } },
                onHover: (event, elements) => {
                    const tooltip = document.getElementById('history-tooltip');
                    if (!tooltip) return;
                    if (elements.length > 0 && factKeys[elements[0].index]) {
  const factText = t(factKeys[elements[0].index]); // <-- перевод на текущем языке
  tooltip.innerHTML = `<h5 style="margin:0 0 5px 0; font-size: 13px;">${labels[elements[0].index]}</h5>${factText}`;
                        tooltip.style.borderColor = coinColor; tooltip.querySelector('h5').style.color = coinColor;
                        tooltip.style.left = event.x + 'px'; tooltip.style.top = (event.y + 40) + 'px';
                        tooltip.classList.add('show');
                        return;
                    }
                    tooltip.classList.remove('show');
                }
            }
        });
        if (titleEl && !isTvMode) titleEl.textContent = t('chartHist');
    }

    let isTvMode = false;
    const tvToggleBtn = document.getElementById('tv-toggle-btn');
    const histContainer = document.getElementById('hist-advanced-chart'); 
    const tvContainer = document.getElementById('tv-advanced-chart');     
    const titleEl = document.querySelector('.chart-title');

    function renderTvChart(coin) {
        if (!tvContainer) return;
        tvContainer.innerHTML = ''; 
        const script = document.createElement('script'); script.type = 'text/javascript'; script.src = 'https://s3.tradingview.com/tv.js';
        script.onload = () => { new TradingView.widget({ "autosize": true, "symbol": "BINANCE:" + coin + "USDT", "interval": "D", "theme": "dark", "style": "1", "locale": document.documentElement.lang || "ru", "enable_publishing": false, "backgroundColor": "rgba(20, 20, 20, 0.95)", "gridColor": "rgba(255, 255, 255, 0.05)", "hide_top_toolbar": false, "save_image": false, "container_id": "tv-advanced-chart" }); };
        document.head.appendChild(script);
        window.setTimeout(() => {
            if (tvContainer && !tvContainer.querySelector('iframe')) {
                tvContainer.innerHTML = '<p class="widget-fallback">Виджет TradingView не загрузился.<br><a href="https://www.tradingview.com/chart/" target="_blank" rel="noopener noreferrer">Открыть график на tradingview.com</a></p>';
            }
        }, 5000);
    }

    if (tvToggleBtn) {
        tvToggleBtn.addEventListener('click', () => {
            isTvMode = !isTvMode;
            if (isTvMode) {
                tvToggleBtn.classList.add('is-active');
                tvToggleBtn.setAttribute('aria-pressed', 'true');
                if(titleEl) titleEl.textContent = t('chartPro');
                if(histContainer) histContainer.style.display = 'none'; if(tvContainer) tvContainer.style.display = 'block';
                renderTvChart(currentChartCoin);
            } else {
                tvToggleBtn.classList.remove('is-active');
                tvToggleBtn.setAttribute('aria-pressed', 'false');
                if(titleEl) titleEl.textContent = t('chartHist');
                if(tvContainer) tvContainer.style.display = 'none'; if(histContainer) histContainer.style.display = 'block';
                renderChart(currentChartCoin);
            }
        });
    }

    const allTabs = document.querySelectorAll('.chart-tab');
    allTabs.forEach(tab => {
        tab.addEventListener('click', (e) => {
            allTabs.forEach(t => { t.classList.remove('active'); t.setAttribute('aria-selected', 'false'); });
            e.target.classList.add('active');
            e.target.setAttribute('aria-selected', 'true');
            currentChartCoin = e.target.id.split('-')[1];
            if (isTvMode) {
                isTvMode = false;
                if (tvToggleBtn) { tvToggleBtn.classList.remove('is-active'); tvToggleBtn.setAttribute('aria-pressed', 'false'); }
                if(titleEl) titleEl.textContent = t('chartHist');
                if(tvContainer) tvContainer.style.display = 'none'; if(histContainer) histContainer.style.display = 'block';
            }
            renderChart(currentChartCoin);
        });
    });
    renderChart('BTC');
}

export function updateChartLivePrice(coin, newPrice) {
    if (myChart && currentChartCoin === coin) {
        const prices = myChart.data.datasets[0].data;
        prices[prices.length - 1] = parseFloat(newPrice);
        myChart.update('none');
    }
}