// js/net.js
// Сетевой слой с честной деградацией.
//
// Правило из agent-skills/design-logic/numerique-responsable:
// у каждого сценария должно быть предусмотрено состояние ошибки,
// а не «пустой экран». Если внешние API недоступны (офлайн, CORS,
// блокировка провайдера), подставляем синтетические демо-данные
// и явно сообщаем об этом пользователю плашкой.

import * as demo from './demoData.js';

const state = { demo: false, reason: '' };

export function isDemo() {
    return state.demo;
}

function showDemoBadge(reason) {
    let badge = document.getElementById('demo-badge');
    if (!badge) {
        badge = document.createElement('div');
        badge.id = 'demo-badge';
        badge.className = 'demo-badge';
        badge.setAttribute('role', 'status');
        badge.setAttribute('aria-live', 'polite');
        document.body.appendChild(badge);
    }
    badge.textContent = 'Демо-данные: внешние API недоступны';
    badge.title = reason || 'Запросы к внешним источникам не удались';
    badge.classList.add('show');
}

/**
 * fetch с таймаутом и резервным набором данных.
 * @param {string} url
 * @param {() => any} fallback — фабрика демо-данных
 * @param {{timeout?: number, validate?: (d: any) => boolean}} [opts]
 */
export async function fetchJSON(url, fallback, opts = {}) {
    const { timeout = 7000, validate } = opts;
    try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeout);
        const res = await fetch(url, { signal: controller.signal });
        clearTimeout(timer);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (validate && !validate(data)) throw new Error('Некорректный ответ API');
        return data;
    } catch (error) {
        state.demo = true;
        state.reason = `${url} → ${error.name === 'AbortError' ? 'таймаут' : error.message}`;
        showDemoBadge(state.reason);
        console.info('[Victoria Falls] демо-режим для', url, '—', state.reason);
        return typeof fallback === 'function' ? fallback() : fallback;
    }
}

export const DEMO = demo;
