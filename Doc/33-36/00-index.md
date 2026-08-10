# TypeScript + React — оглавление курса

## Как пользоваться

Каждый урок устроен одинаково:

1. **Теория** — тезисно, с примерами кода
2. **Проработка** — задачи с полным разбором, читаешь и повторяешь
3. **Домашка** — решаешь сам, скидываешь мне на проверку

`cheatsheet.md` — сводка всех уроков без разбора, для быстрого поиска.

Ответы на домашку кидай кодом. Разбираю подробно: что верно, что неверно, что верно но не так, как принято.

---

## Блок 0. JS-специфика

| # | Урок | Статус |
|---|---|---|
| 01 | [Event loop и асинхронность](01-event-loop.md) | сдан |
| 02 | [Замыкания и устройство хуков](02-closures.md) | текущий |
| 03 | [Модули, `this`, прототипы](03-modules-this.md) | готов |
| 04 | [Деструктуризация, spread, синтаксис](04-syntax.md) | готов |

## Блок 1. TypeScript как система типов

| # | Урок | Статус |
|---|---|---|
| 05 | [Структурная типизация, вывод типов](05-structural-typing.md) | готов |
| 06 | [Union, intersection, literal types](06-unions.md) | готов |
| 07 | [Narrowing и type guards](07-narrowing.md) | готов |
| 08 | [**Discriminated unions**](08-discriminated-unions.md) | готов |
| 09 | [Generics, `extends`, вывод](09-generics.md) | готов |
| 10 | [Utility types](10-utility-types.md) | готов |
| 11 | [Conditional types, `infer`, mapped](11-conditional-mapped.md) | готов |
| 12 | [`as const`, `satisfies`, tsconfig](12-as-const-satisfies.md) | готов |
| 13 | [Практикум: type-challenges](13-type-challenges.md) | готов |

## Блок 2. React — модель рендеринга

| # | Урок | Статус |
|---|---|---|
| 14 | [Компонент как чистая функция, JSX](14-components-jsx.md) | готов |
| 15 | [`useState`, рендер, реконсиляция](15-usestate-rendering.md) | готов |
| 16 | [Списки и `key`](16-lists-keys.md) | готов |
| 17 | [Подъём состояния, поток данных](17-lifting-state.md) | готов |
| 18 | [Композиция через `children`](18-composition.md) | готов |
| 19 | [`useEffect` — синхронизация](19-useeffect.md) | готов |
| 20 | [`useRef`, `useMemo`, `useCallback`](20-refs-memo.md) | готов |
| 21 | [Правила хуков, кастомные хуки](21-hooks-rules.md) | готов |

## Блок 3. TS + React вместе

| # | Урок | Статус |
|---|---|---|
| 22 | [Типизация props и `children`](22-typing-props.md) | готов |
| 23 | [Дженерик-компоненты](23-generic-components.md) | готов |
| 24 | [Типы событий и refs](24-events-refs.md) | готов |
| 25 | [`useReducer` + discriminated union](25-usereducer.md) | готов |

## Блок 4. Экосистема

| # | Урок | Статус |
|---|---|---|
| 26 | [Vite, структура проекта](26-vite-structure.md) | готов |
| 27 | [Роутинг](27-routing.md) | готов |
| 28 | [TanStack Query — серверные данные](28-tanstack-query.md) | готов |
| 29 | [Zustand — клиентское состояние](29-zustand.md) | готов |
| 30 | [Формы: React Hook Form + Zod](30-forms-zod.md) | готов |
| 31 | [Стили: Tailwind или CSS Modules](31-styling.md) | готов |
| 32 | [Тесты: Vitest + Testing Library](32-testing.md) | готов |

## Блок 5. Проект

| # | Урок | Статус |
|---|---|---|
| 33 | [Веб-морда для DSP: архитектура](33-project-architecture.md) | готов |
| 34 | [Canvas и `Float32Array`](34-canvas-typed-arrays.md) | готов |
| 35 | [WebSocket-поток в React](35-websocket-stream.md) | готов |
| 36 | [Производительность рендеринга](36-performance.md) | готов |

---

## Быстрый поиск по темам

**Асинхронность** → 01
**Почему `setTimeout(fn,0)` не мгновенный** → 01
**`Promise.all` vs цикл с `await`** → 01
**`var` vs `let` в цикле** → 02
**Почему хуки нельзя в `if`** → 02
**Stale closure** → 02, 20
**Структурная vs номинативная типизация** → 05
**Моделирование состояний типами** → 08, 25
**Когда `useEffect` не нужен** → 19
**Почему компонент перерендерился** → 15, 20
