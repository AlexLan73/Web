# Урок 12. `as const`, `satisfies`, настройка компилятора

Практический урок. Три инструмента, которые ежедневно решают проблему «TS вывел не тот тип».

---

# Часть 1. Теория

## 12.1 Проблема расширения типов

TS расширяет (widening) литеральные типы там, где значение может измениться:

```ts
const a = 'hann';                 // тип 'hann' — const не переприсвоить
let b = 'hann';                   // тип string

const obj = { window: 'hann' };   // { window: string } — поле изменяемо!
const arr = [1, 2, 3];            // number[] — не кортеж
```

Логика: `const obj` защищает саму переменную, но не её поля. `obj.window = 'rect'` допустимо, значит тип должен быть `string`.

Проблема возникает постоянно:
```ts
function setWindow(w: WindowFn) {}
const config = { window: 'hann' };
setWindow(config.window);        // ❌ string не подходит под WindowFn
```

## 12.2 `as const`

Заявляет: значение полностью неизменяемо. Компилятор перестаёт расширять.

```ts
const obj = { window: 'hann', size: 1024 } as const;
// { readonly window: 'hann'; readonly size: 1024 }

const arr = [1, 2, 3] as const;
// readonly [1, 2, 3] — кортеж, не массив
```

Действует **рекурсивно**, на всю глубину. Все поля становятся `readonly`, все литералы сохраняют точный тип, массивы становятся кортежами.

**Главное применение — вывод union из данных:**
```ts
const WINDOWS = ['hann', 'hamming', 'blackman', 'rect'] as const;

type WindowFn = typeof WINDOWS[number];
// 'hann' | 'hamming' | 'blackman' | 'rect'
```

Разбор: `typeof WINDOWS` — тип кортежа. `[number]` — indexed access по всем числовым индексам, то есть union всех элементов.

Ценность: **один источник истины**. Массив есть в рантайме (для рендера списка), тип выведен из него. Добавил элемент — union обновился сам. Без `as const` пришлось бы держать массив и union отдельно и следить, чтобы не разъехались.

То же для объектов:
```ts
const CODES = { ok: 200, notFound: 404 } as const;

type Code = keyof typeof CODES;              // 'ok' | 'notFound'
type Status = typeof CODES[Code];            // 200 | 404
```

**Минусы `as const`:**
- Всё становится `readonly` — не передать туда, где ждут изменяемый массив
- Иногда слишком узко: `size: 1024` вместо `size: number`

Второе лечится частично:
```ts
const cfg = { window: 'hann' as const, size: 1024 };
// { window: 'hann'; size: number }
```

## 12.3 `satisfies`

Появился в TS 4.9 и закрыл давнюю дилемму.

**Проблема.** Есть два способа связать значение с типом, оба плохи:

```ts
// Вариант 1: аннотация — проверяет, но стирает конкретику
const windows: Record<string, WindowInfo> = {
  hann: { label: 'Ханна', alpha: 0.5 },
  rect: { label: 'Прямоуг.', alpha: 1 },
};
windows.nope;              // ❌ не поймано — ключ любой string
type K = keyof typeof windows;    // string — конкретика потеряна

// Вариант 2: без аннотации — конкретика есть, проверки нет
const windows2 = {
  hann: { label: 'Ханна', alpa: 0.5 },     // опечатка не поймана!
};
```

**`satisfies` даёт и то, и другое:**
```ts
const windows = {
  hann:     { label: 'Ханна',    alpha: 0.5  },
  hamming:  { label: 'Хэмминга', alpha: 0.54 },
} satisfies Record<string, WindowInfo>;

type K = keyof typeof windows;      // 'hann' | 'hamming' — точный union!
windows.hann.alpha;                  // number
windows.nope;                        // ❌ ошибка
```

Формула: **`satisfies` проверяет соответствие, но не меняет выведенный тип.** Аннотация делает наоборот — навязывает тип и теряет детали.

**Проверка полноты покрытия:**
```ts
const handlers = {
  idle: () => 'Ожидание',
  loading: () => 'Загрузка',
  success: () => 'Готово',
} satisfies Record<Analysis['status'], () => string>;
// ❌ отсутствует 'failed'
```
Компилятор требует все варианты — и при этом каждый обработчик сохраняет свой точный тип возврата.

**Комбинация с `as const`:**
```ts
const CONFIG = {
  defaults: { size: 1024, window: 'hann' },
  limits: { minSize: 64, maxSize: 65536 },
} as const satisfies AppConfig;
```
Порядок важен: сначала `as const` фиксирует литералы, потом `satisfies` проверяет.

**Когда что:**

| Нужно | Инструмент |
|---|---|
| Проверить и забыть детали | `: Type` |
| Проверить и сохранить детали | `satisfies Type` |
| Зафиксировать литералы | `as const` |
| Соврать компилятору | `as Type` — избегать |

## 12.4 tsconfig: что реально важно

```json
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "jsx": "react-jsx",

    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "exactOptionalPropertyTypes": true,

    "noEmit": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true
  }
}
```

**`strict: true`** — включает восемь проверок разом. Главные:
- `strictNullChecks` — `null` и `undefined` отслеживаются как отдельные типы. Без него вся система бессмысленна
- `noImplicitAny` — параметр без типа это ошибка
- `strictFunctionTypes` — корректная проверка вариантности параметров

**`noUncheckedIndexedAccess`** — `arr[i]` даёт `T | undefined`. Формально правильно: индекс может выйти за границы. Раздражает поначалу, ловит реальные баги.
```ts
const first = arr[0];        // number | undefined
if (first !== undefined) { }
```

**`exactOptionalPropertyTypes`** — различает «поля нет» и «поле равно undefined»:
```ts
type T = { x?: number };
const a: T = {};                  // OK
const b: T = { x: undefined };    // ❌ при этой опции
```
Важно, когда используешь `in` для проверки наличия.

**`noEmit: true`** — компилировать будет Vite (через esbuild или SWC), `tsc` нужен только для проверки типов. Стандартная схема современного проекта.

**`verbatimModuleSyntax`** — требует `import type` для импортов, используемых только как типы:
```ts
import type { Config } from './types';
import { compute, type Options } from './api';
```
Убирает неоднозначность при трансляции и ускоряет сборку — бандлеру не надо анализировать, что можно выкинуть.

**`skipLibCheck: true`** — не проверять `.d.ts` зависимостей. Экономит секунды на каждой сборке; типы библиотек всё равно не твоя ответственность.

## 12.5 Проверка типов в CI

`tsc --noEmit` — единственный способ убедиться, что типы сходятся. Vite при сборке типы **не проверяет**: esbuild их просто вырезает, не анализируя.

В `package.json`:
```json
"scripts": {
  "typecheck": "tsc --noEmit",
  "typecheck:watch": "tsc --noEmit --watch"
}
```

WebStorm показывает ошибки на лету, но у него свой языковой сервер, и он иногда расходится с `tsc` — особенно на сложных типах. Перед коммитом гоняй `tsc`.

---

# Часть 2. Проработка

## Задача. Конфигурация без дублирования

Собираем всё вместе: одно объявление данных → типы, списки для UI, проверки.

```ts
// windows.ts
export const WINDOWS = {
  hann:     { label: 'Ханна',      alpha: 0.5,  sidelobe: -31 },
  hamming:  { label: 'Хэмминга',   alpha: 0.54, sidelobe: -42 },
  blackman: { label: 'Блэкмана',   alpha: 0.42, sidelobe: -58 },
  rect:     { label: 'Прямоугол.', alpha: 1,    sidelobe: -13 },
} as const satisfies Record<string, {
  label: string;
  alpha: number;
  sidelobe: number;
}>;

export type WindowFn = keyof typeof WINDOWS;
// 'hann' | 'hamming' | 'blackman' | 'rect'

export type WindowInfo = typeof WINDOWS[WindowFn];

export const WINDOW_LIST = Object.entries(WINDOWS).map(
  ([key, info]) => ({ value: key as WindowFn, ...info })
);
```

Что мы получили из одного объявления:
- union `WindowFn` для типизации
- объект для доступа по ключу в рантайме
- массив для рендера выпадающего списка
- проверку, что у каждого окна есть все три поля

Добавление нового окна — одна строка. Всё остальное обновится само.

**Размеры FFT — кортеж:**
```ts
export const FFT_SIZES = [256, 512, 1024, 2048, 4096, 8192] as const;
export type FftSize = typeof FFT_SIZES[number];   // 256 | 512 | ... | 8192
```

Теперь `size: FftSize` вместо `size: number` — произвольное число не пройдёт. Для FFT это ровно то, что нужно: степени двойки в допустимом диапазоне.

**Дефолты с проверкой:**
```ts
export const DEFAULT_CONFIG = {
  size: 1024,
  window: 'hann',
  overlap: 0.5,
} as const satisfies FftConfig;
```
Если переименуешь поле в `FftConfig` — ошибка здесь же. Без `satisfies` дефолты молча разъехались бы с типом.

**Тонкость с `as const` и функциями.** Замороженный конфиг нельзя передать туда, где ждут изменяемый объект:
```ts
function apply(cfg: FftConfig) {}
apply(DEFAULT_CONFIG);        // ❌ readonly не подходит под изменяемый
```
Варианты: сделать параметр `Readonly<FftConfig>` (правильно — функция и не должна менять аргумент), либо копировать `{ ...DEFAULT_CONFIG }`.

Практическое правило: **параметры функций объявляй `Readonly<T>`**, если не собираешься мутировать. Это и документация, и совместимость с замороженными данными.

---

# Часть 3. Домашка

Папка `hw-12`.

**1.** Что за типы и почему разные?
```ts
const a = { x: 1 };
const b = { x: 1 } as const;
const c = [1, 'a'];
const d = [1, 'a'] as const;
type A = typeof a; type B = typeof b;
type C = typeof c; type D = typeof d;
```

**2.** Перепиши через `as const`, устранив дублирование:
```ts
type Level = 'debug' | 'info' | 'warn' | 'error';
const LEVELS: Level[] = ['debug', 'info', 'warn', 'error'];
const COLORS: Record<Level, string> = {
  debug: 'gray', info: 'blue', warn: 'orange', error: 'red'
};
```

**3.** Покажи на своём примере, где аннотация теряет информацию, а `satisfies` сохраняет. Три строки кода, два вывода типов.

**4.** Что произойдёт и почему? Исправь двумя способами.
```ts
const config = { size: 1024, window: 'hann' } as const;
function run(c: { size: number; window: string }) {}
run(config);
```

**5.** Настрой `tsconfig.json` под проект с Vite и React. Объясни каждую опцию из списка в 12.4 своими словами. Затем **выключи** `noUncheckedIndexedAccess` и найди в своём коде из прошлых домашек место, где это скрывает баг.

**6.** Собери таблицу переходов конечного автомата через `satisfies` так, чтобы пропуск состояния не компилировался:
```ts
type State = 'idle' | 'running' | 'done' | 'failed';
type Event = 'start' | 'finish' | 'fail' | 'reset';
// нужно: transitions[state][event] → State | undefined
```

**7.** Объясни, почему `satisfies` не заменяет аннотацию полностью — приведи случай, где нужна именно аннотация.
