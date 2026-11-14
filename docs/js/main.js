import { initCryptoChart } from './chart.js';
import { currencyGroups } from './data.js';
import { initConverter, updateSidebarRates } from './converter.js';
// 1. Добавляем addUpdateCallback в импорты
import { setLocale, initI18n, addUpdateCallback, getCurrentLocale } from './i18n.js';
import { 
    getGroupTitle,
    renderAllCurrencies, 
    renderCrypto, 
    renderStocks,
    renderMoex
} from './render.js';

document.addEventListener('DOMContentLoaded', () => {
    // 0. Запуск локализации
    initI18n(); 

    // 1. ПОДПИСЫВАЕМ ФУНКЦИИ НА ОБНОВЛЕНИЕ
    // Теперь они будут вызываться автоматически при смене языка
    addUpdateCallback(renderAllCurrencies);
    addUpdateCallback(renderCrypto);
    addUpdateCallback(renderStocks);
    addUpdateCallback(renderMoex);
    addUpdateCallback(initConverter);
    addUpdateCallback(updateSidebarRates);
    addUpdateCallback(initHeatmap);

    // 2. Первичная отрисовка (при загрузке сайта)
    renderAllCurrencies();
    renderCrypto();
    renderStocks();
    renderMoex();
    
    // 3. Остальная инициализация
    try {
        initConverter();
        initCryptoChart(); 
        initHeatmap();
        initMiniCharts();
        handleMoexWeekend(); 
        initMobileAccordions(); 
        initMobileConverter();  
        initMobileInfoAccordion(); 
        initUICustomization(); 
        initDragAndDrop(); 
        initSidebarSettings(); 
    } catch (error) {
        console.error(`❌ Ошибка загрузки:`, error);
    }
});


// ==================== ЛОГИКА МЕНЮ ЯЗЫКОВ ====================
const langToggle = document.getElementById('langToggle');
const langDropdown = document.getElementById('langDropdown');

if (langToggle && langDropdown) {
    langToggle.addEventListener('click', (e) => {
        e.stopPropagation();
        langDropdown.classList.toggle('show');
    });

    document.addEventListener('click', () => {
        langDropdown.classList.remove('show');
    });

    document.querySelectorAll('.lang-option').forEach(option => {
        option.addEventListener('click', () => {
            const lang = option.dataset.lang;
            setLocale(lang); 
            langDropdown.classList.remove('show');
        });
    });
}

const footerLangBtns = document.querySelectorAll('.footer-lang-btn');
footerLangBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
        e.preventDefault();
        const lang = btn.dataset.lang;
        setLocale(lang); 
        window.scrollTo({ top: 0, behavior: 'smooth' }); 
    });
});


// ==================== МОБИЛЬНЫЙ ИНТЕРФЕЙС ====================
function initMobileAccordions() {
    const headers = document.querySelectorAll('.sidebar-content h4');
    headers.forEach(header => {
        const content = header.nextElementSibling;
        if (content && !content.classList.contains('paragr')) {
            header.classList.add('accordion-header');
            header.addEventListener('click', () => {
                if (window.innerWidth <= 768) {
                    header.classList.toggle('active');
                    content.classList.toggle('show');
                }
            });
        }
    });
}

function initMobileConverter() {
    const headers = document.querySelectorAll('.exchange-card .currency-header');
    const fromDropdown = document.querySelector('.currency-selector.left');
    const toDropdown = document.querySelector('.currency-selector.right');

    if (headers.length < 2 || !fromDropdown || !toDropdown) return;

    headers[0].addEventListener('click', (e) => {
        if (window.innerWidth <= 768) {
            e.stopPropagation();
            fromDropdown.classList.add('show-modal');
            toDropdown.classList.remove('show-modal');
            document.body.classList.add('modal-open');
        }
    });

    headers[1].addEventListener('click', (e) => {
        if (window.innerWidth <= 768) {
            e.stopPropagation();
            toDropdown.classList.add('show-modal');
            fromDropdown.classList.remove('show-modal');
            document.body.classList.add('modal-open');
        }
    });

    document.querySelectorAll('.currency-item').forEach(item => {
        item.addEventListener('click', () => {
            if (window.innerWidth <= 768) {
                fromDropdown.classList.remove('show-modal');
                toDropdown.classList.remove('show-modal');
                document.body.classList.remove('modal-open');
            }
        });
    });

    document.addEventListener('click', (e) => {
        if (window.innerWidth <= 768 && document.body.classList.contains('modal-open')) {
            if (!e.target.closest('.currency-selector')) {
                fromDropdown.classList.remove('show-modal');
                toDropdown.classList.remove('show-modal');
                document.body.classList.remove('modal-open');
            }
        }
    });
}

function initMobileInfoAccordion() {
    const infoHeader = document.querySelector('#info-currency-name');
    const infoText = document.querySelector('#info-description');

    if (infoHeader && infoText) {
        infoHeader.addEventListener('click', () => {
            if (window.innerWidth <= 768) {
                infoHeader.classList.toggle('active');
                infoText.classList.toggle('show');
            }
        });
    }
}

// ==================== ЛОГИКА ДАННЫХ И ВИДЖЕТОВ ====================
function handleMoexWeekend() {
    const moscowTimeStr = new Date().toLocaleString("en-US", { timeZone: "Europe/Moscow" });
    const moscowDate = new Date(moscowTimeStr);
    const day = moscowDate.getDay(); 

    if (day === 0 || day === 6) {
        const lastFriday = new Date(moscowDate);
        lastFriday.setDate(moscowDate.getDate() - (day === 0 ? 2 : 1)); 
        
        const nextMonday = new Date(moscowDate);
        nextMonday.setDate(moscowDate.getDate() + (day === 0 ? 1 : 2)); 

        const options = { day: '2-digit', month: '2-digit' };
        const fridayStr = lastFriday.toLocaleDateString('ru-RU', options);
        const mondayStr = nextMonday.toLocaleDateString('ru-RU', options);

        const noteContainer = document.getElementById('moex-status-note');
        if (noteContainer) {
            noteContainer.innerHTML = `Торги на MOEX закрыты.<br>Курс за <b>${fridayStr}</b>, обновление <b>${mondayStr}</b>`;
            noteContainer.classList.add('show');
        }

        const moexList = document.getElementById('moex-list');
        if (moexList) {
            const observer = new MutationObserver(() => {
                const pricesAndChanges = moexList.querySelectorAll('.moex-price, .change-container');
                pricesAndChanges.forEach(el => el.classList.add('market-closed-opacity'));
            });
            observer.observe(moexList, { childList: true, subtree: true });
        }
    }
}


function getTradingViewLocale() {
  const map = {
    ru: "ru",
    en: "en",
    de: "de",
    fr: "fr",
    zh: "zh_CN",
    jp: "ja",
    kr: "ko",
    pl: "pl",
    fi: "fi",
    hu: "hu",
    sk: "sk",
    sl: "sl",
    sr: "sr",
    uc: "uk"
  };
  return map[getCurrentLocale()] || "en";
}



// Виджеты TradingView живут на их CDN: если он заблокирован, честно говорим об этом,
// вместо пустого прямоугольника на месте графика.
function widgetFallback(container, symbolLabel) {
  if (!container) return;
  window.setTimeout(() => {
    if (!container.isConnected) return;
    if (container.querySelector('iframe')) return;
    const link = symbolLabel
      ? `https://www.tradingview.com/symbols/${encodeURIComponent(symbolLabel)}/`
      : 'https://www.tradingview.com/markets/';
    container.classList.add('is-unavailable');
    container.innerHTML =
      `<p class="widget-fallback">Виджет TradingView не загрузился.<br>` +
      `<a href="${link}" target="_blank" rel="noopener noreferrer">Открыть график на tradingview.com</a></p>`;
  }, 5000);
}

function initHeatmap() {
  const container = document.querySelector('#tv-heatmap-container .tradingview-widget-container__widget');
  if (!container) return;

  container.innerHTML = ""; // чтобы пересоздавать при смене языка

  const script = document.createElement('script');
  script.type = 'text/javascript';
  script.src = 'https://s3.tradingview.com/external-embedding/embed-widget-stock-heatmap.js';
  script.async = true;

  script.innerHTML = JSON.stringify({
    exchanges: [],
    isTransparent: true,
    dataSource: "SPX500",
    grouping: "sector",
    blockSize: "market_cap_basic",
    blockColor: "change",
    locale: getTradingViewLocale(),
    symbolUrl: "",
    colorTheme: "dark",
    hasTopBar: false,
    isDataSetEnabled: false,
    isZoomEnabled: true,
    hasSymbolTooltip: true,
    width: "100%",
    height: "100%"
  });

  container.appendChild(script);
  widgetFallback(container, null);
}

function initMiniCharts() {
    const symbols = ["BINANCE:BTCUSDT", "BINANCE:ETHUSDT", "BINANCE:SOLUSDT", "BINANCE:BNBUSDT", "BINANCE:DOGEUSDT"];

    symbols.forEach((symbol, index) => {
        const container = document.getElementById(`mini-chart-${index + 1}`);
        if (!container) return;

        const script = document.createElement('script');
        script.type = 'text/javascript';
        script.src = 'https://s3.tradingview.com/external-embedding/embed-widget-mini-symbol-overview.js';
        script.async = true;
        
        script.innerHTML = JSON.stringify({
            "symbol": symbol,
            "width": "100%",
            "height": "100%",
            "locale": "ru",
            "dateRange": "1M",
            "colorTheme": "dark",
            "isTransparent": true, 
            "autosize": true,
            "largeChartUrl": ""
        });
        container.appendChild(script);
        widgetFallback(container, symbol.replace('BINANCE:', ''));
    });
}

// ==================== НАСТРОЙКИ ИНТЕРФЕЙСА (UI / UX) ====================
function initUICustomization() {
    const fullscreenBtn = document.getElementById('chart-fullscreen-btn');
    const blockChart = document.getElementById('block-chart'); 
    
    if (fullscreenBtn && blockChart) {
        fullscreenBtn.addEventListener('click', () => {
            blockChart.classList.toggle('fullscreen');
            if (blockChart.classList.contains('fullscreen')) {
                document.body.style.overflow = 'hidden';
                fullscreenBtn.textContent = '✖'; 
            } else {
                document.body.style.overflow = '';
                fullscreenBtn.textContent = '⛶'; 
            }
        });
    }

    const btnRight = document.getElementById('btn-toggle-right');
    const sidebarRight = document.getElementById('right-sidebar');
    if (btnRight && sidebarRight) {
        btnRight.addEventListener('click', () => {
            sidebarRight.classList.toggle('collapsed');
            btnRight.textContent = sidebarRight.classList.contains('collapsed') ? '◀' : '▶';
        });
    }

    const btnLeft = document.getElementById('btn-toggle-left');
    const sidebarLeft = document.getElementById('left-sidebar');
    if (btnLeft && sidebarLeft) {
        btnLeft.addEventListener('click', () => {
            sidebarLeft.classList.toggle('collapsed');
            btnLeft.textContent = sidebarLeft.classList.contains('collapsed') ? '▶' : '◀';
        });
    }
}

function initDragAndDrop() {
    const centralLayout = document.getElementById('central-layout');
    if (centralLayout && typeof Sortable !== 'undefined') {
        Sortable.create(centralLayout, {
            animation: 300,
            handle: '.drag-handle',
            ghostClass: 'sortable-ghost',
            forceFallback: true,   
            scroll: true,          
            scrollSensitivity: 80, 
            scrollSpeed: 20,       
            group: "central-layout-blocks",
            store: {
                get: function (sortable) {
                    const order = localStorage.getItem(sortable.options.group.name);
                    return order ? order.split('|') : [];
                },
                set: function (sortable) {
                    const order = sortable.toArray();
                    localStorage.setItem(sortable.options.group.name, order.join('|'));
                }
            }
        });
    }
}

function showSettingsHint(message) {
    const list = document.getElementById('settings-options-list');
    if (!list) return;
    let hint = list.parentElement.querySelector('.settings-hint');
    if (!hint) {
        hint = document.createElement('p');
        hint.className = 'settings-hint';
        hint.setAttribute('role', 'alert');
        list.after(hint);
    }
    hint.textContent = message;
}

function openSettingsModal(modal) {
    modal.classList.add('is-open');
    modal.removeAttribute('aria-hidden');
    document.body.classList.add('modal-open');
    const first = modal.querySelector('.sidebar-checkbox');
    if (first) first.focus();
}

function closeSettingsModal(modal) {
    modal.classList.remove('is-open');
    modal.setAttribute('aria-hidden', 'true');
    document.body.classList.remove('modal-open');
}

function initSidebarSettings() {
    const leftSidebarContainer = document.getElementById('left-sidebar-sortable');
    if (leftSidebarContainer && typeof Sortable !== 'undefined') {
        Sortable.create(leftSidebarContainer, {
            animation: 200,
            handle: '.sidebar-drag-handle',
            onEnd: function () {
                const newOrder = Array.from(leftSidebarContainer.children).map(el => el.dataset.group);
                localStorage.setItem('sidebarActiveGroups', JSON.stringify(newOrder));
            }
        });
    }

    const settingsBtn = document.getElementById('settings-sidebar-btn');
    const modal = document.getElementById('sidebar-settings-modal');
    const optionsList = document.getElementById('settings-options-list');
    const saveBtn = document.getElementById('save-sidebar-btn');

    if (!settingsBtn || !modal) return;

    settingsBtn.addEventListener('click', () => {
        settingsBtn.style.transform = 'rotate(180deg)';
        setTimeout(() => settingsBtn.style.transform = 'none', 300);

        let activeGroups = JSON.parse(localStorage.getItem('sidebarActiveGroups')) || ['major', 'other', 'cis'];
        
        optionsList.innerHTML = '';
        
        // ТЕПЕРЬ МЫ БЕРЕМ КЛЮЧИ ИЗ БАЗЫ И ПЕРЕВОДИМ ИХ ЧЕРЕЗ getGroupTitle!
        Object.keys(currencyGroups).forEach(key => {
            const isChecked = activeGroups.includes(key);
            
            const div = document.createElement('div');
            div.className = 'settings-option';
            div.innerHTML = `
                <input type="checkbox" id="check-${key}" value="${key}" class="sidebar-checkbox" ${isChecked ? 'checked' : ''}>
                <label for="check-${key}">${getGroupTitle(key)}</label>
            `;
            optionsList.appendChild(div);
        });

        const checkboxes = document.querySelectorAll('.sidebar-checkbox');
        checkboxes.forEach(box => {
            box.addEventListener('change', () => {
                const checkedCount = document.querySelectorAll('.sidebar-checkbox:checked').length;
                if (checkedCount > 3) {
                    box.checked = false;
                    showSettingsHint('Можно выбрать максимум 3 региона.');
                }
            });
        });

        openSettingsModal(modal);
    });

    saveBtn.addEventListener('click', () => {
        const checkedBoxes = Array.from(document.querySelectorAll('.sidebar-checkbox:checked'));
        const selectedGroups = checkedBoxes.map(box => box.value);
        
        if (selectedGroups.length === 0) {
            showSettingsHint('Выберите хотя бы один регион.');
            return;
        }

        localStorage.setItem('sidebarActiveGroups', JSON.stringify(selectedGroups));
        closeSettingsModal(modal);
        
        renderAllCurrencies(); 
        updateSidebarRates(); 
    });

    modal.addEventListener('click', (e) => {
        if (e.target === modal) closeSettingsModal(modal);
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && modal.classList.contains('is-open')) {
            closeSettingsModal(modal);
            settingsBtn.focus();
        }
    });
}