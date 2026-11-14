import { localeConfig, defaultLocale } from './localeConfig.js';
import { translations } from './translations.js';
import { factTranslations } from './factTranslations.js';

let currentLocale = defaultLocale;
const updateCallbacks = []; // Список функций, которые нужно вызвать при смене языка

export function getCurrentLocale() { return currentLocale; }

// Функция для регистрации функций, которые нужно перезапустить при смене языка
export function addUpdateCallback(fn) {
    updateCallbacks.push(fn);
}

export function t(key) {
  const langMain = translations[currentLocale] || translations.ru;
  const langFacts = factTranslations[currentLocale] || factTranslations.ru || {};

  return (
    langMain[key] ??
    langFacts[key] ??
    translations.ru[key] ??
    (factTranslations.ru ? factTranslations.ru[key] : undefined) ??
    key
  );
}

export function setLocale(localeCode) {
    if (!localeConfig[localeCode]) localeCode = defaultLocale;
    currentLocale = localeCode;
    localStorage.setItem('preferredLocale', localeCode);
    document.documentElement.lang = localeCode;

    const topFlag = document.getElementById('current-flag');
    const topLangName = document.getElementById('current-lang');
    if(topFlag) topFlag.className = `fi fi-${localeConfig[localeCode].flag}`;
    if(topLangName) topLangName.textContent = localeConfig[localeCode].name;

    applyTranslations();
    renderDynamicNews();

    // ВАЖНО: Вызываем все функции, которые «подписались» на обновление
    updateCallbacks.forEach(fn => fn());

    const ud = document.getElementById('update-date');
if (ud && ud.dataset.state === 'loading') ud.textContent = t('loading');
}

function applyTranslations() {
    const tDict = translations[currentLocale] || translations.ru;
    document.querySelectorAll('[data-key]').forEach(el => {
        const key = el.dataset.key;
        if (tDict[key]) el.textContent = tDict[key];
    });
    document.title = tDict.siteTitle || "Victoria Falls";
}

function renderDynamicNews() {
    const newsContainer = document.getElementById('dynamic-news-list');
    if (!newsContainer) return;
    newsContainer.innerHTML = ''; 
    
    const ruNews = localeConfig['ru'].newsSources;
    ruNews.forEach(source => {
        const a = document.createElement('a');
        a.href = source.url; a.target = "_blank";
        a.innerHTML = `<span class="fi fi-ru"></span> ${source.name}`;
        newsContainer.appendChild(a);
    });

    if (currentLocale !== 'ru') {
        const localNews = localeConfig[currentLocale].newsSources;
        localNews.forEach(source => {
            const a = document.createElement('a');
            a.href = source.url; a.target = "_blank";
            a.innerHTML = `<span class="fi fi-${localeConfig[currentLocale].flag}"></span> ${source.name}`;
            newsContainer.appendChild(a);
        });
    }
}

export function initI18n() {
    const saved = localStorage.getItem('preferredLocale');
    const initialLocale = saved && localeConfig[saved] ? saved : defaultLocale;
    setLocale(initialLocale);
}