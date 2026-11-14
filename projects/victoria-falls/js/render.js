import { currencyGroups, cryptoList, moexStocks } from './data.js';
import { t } from './i18n.js';

export function getGroupTitle(key) {
    const map = {
        major: t('majorCurrencies'),
        other: t('otherCurrencies'),
        asia: t('asiaCurrencies'),
        middleEast: t('middleEast'),
        cis: t('cis')
    };
    return map[key] || key;
}

export function renderAllCurrencies() {
    const sortableContainer = document.getElementById('left-sidebar-sortable');
    if (!sortableContainer) return;
    sortableContainer.innerHTML = '';

    let activeGroups = JSON.parse(localStorage.getItem('sidebarActiveGroups')) || ['major', 'other', 'cis'];

    activeGroups.forEach(groupKey => {
        if (!currencyGroups[groupKey]) return;

        const block = document.createElement('div');
        block.className = 'sortable-sidebar-item';
        block.dataset.group = groupKey;

        block.innerHTML = `
            <h4 style="display: flex; align-items: center;">
                <span class="sidebar-drag-handle" style="display:flex; align-items:center; margin-right:8px; opacity:0.5;">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                        <circle cx="9" cy="5" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="9" cy="19" r="2"/>
                        <circle cx="15" cy="5" r="2"/><circle cx="15" cy="12" r="2"/><circle cx="15" cy="19" r="2"/>
                    </svg>
                </span>
                ${getGroupTitle(groupKey)}
            </h4>
            <div class="left-sidebar-content">
                <ul id="currencies-${groupKey}" class="currency-list"></ul>
            </div>
        `;
        sortableContainer.appendChild(block);
        renderCurrencyGroup(`currencies-${groupKey}`, currencyGroups[groupKey]);
    });
}

function renderCurrencyGroup(containerId, items) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = '';

    items.forEach(item => {
        const li = document.createElement('li');
        li.dataset.code = item.code;
        li.innerHTML = `
            <div class="currency-name">
                <span class="fi fi-${item.flag}"></span>
                <span>${item.name}</span>
            </div>
            <span class="rate">${t('loading')}</span>
            <div class="change-container"><span class="change"></span></div>
        `;
        container.appendChild(li);
    });
}

export function renderCrypto() {
    const container = document.getElementById('CriptoVVV');
    if (!container) return;
    container.innerHTML = '';

    cryptoList.forEach(item => {
        const li = document.createElement('li');
        li.dataset.symbol = item.symbol;
        li.innerHTML = `
            <div class="asset-row">
                <div class="asset-name">
                    <span class="crypto-icon ${item.className}"><img src="./iconss/${item.icon}" alt="" aria-hidden="true" loading="lazy" decoding="async" /></span>
                    <span>${item.symbol}</span>
                </div>
                <div class="asset-quote">
                    <span class="crypto-price">${t('loading')}</span><span class="asset-unit">${item.unit}</span>
                    <div class="change-container"><span class="crypto-change"></span></div>
                </div>
            </div>
            ${item.extra ? `<div class="asset-extra">${item.extra}</div>` : ''}
        `;
        container.appendChild(li);
    });
}

export function renderMoex() {
    const container = document.getElementById(`moex-list`);
    if (!container) return;
    container.innerHTML = '';

    moexStocks.forEach(item => {
        const li = document.createElement(`li`);
        li.dataset.symbol = item.symbol;
        // Логика перевода названия акции
        const displayName = t(item.key) !== item.key ? t(item.key) : item.name;
        
        li.innerHTML = `
            <div class="asset-row">
                <span class="asset-name">${displayName} <small class="asset-ticker">(${item.symbol})</small></span>
                <div class="asset-quote">
                    <span class="moex-price">${t('loading')}</span><span class="asset-unit">₽</span>
                </div>
            </div>
            <div class="change-container"><span class="market-change"></span></div>
        `;
        container.appendChild(li);
    });
}

export function renderMetals() {}
export function renderOilPrices() {}
export function renderGasProducers() {}
export function renderStocks() {}