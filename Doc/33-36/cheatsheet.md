# Шпаргалка

Быстрый справочник. Открывать, когда забыл деталь. Разбор — в файлах уроков.

---

## Event loop (урок 01)

**Модель:** один поток, один стек. Параллельности нет, есть чередование.

**Порядок выполнения:**
1. Весь синхронный код до конца
2. Микрозадачи — **все**, до дна очереди
3. Одна макрозадача
4. Снова все микрозадачи → шаг 3

| Микрозадачи | Макрозадачи |
|---|---|
| `.then()`, `await` | `setTimeout`, `setInterval` |
| `queueMicrotask()` | события DOM |
| `MutationObserver` | I/O, сеть |

**Правила на память:**
- `setTimeout(fn, 0)` = «в следующем витке», не «немедленно»
- Функция выполняется атомарно до конца — гонок внутри неё не бывает
- `await` разрезает функцию: всё после него — микрозадача
- Микрозадачи, созданные во время разгребания очереди, попадают в **тот же** проход
- Блокирующий цикл вешает всё: таймеры, промисы, отрисовку

**Промисы энергичные (eager).** Работа стартует при создании промиса, не при `await`.

```js
const p = fake(300);   // таймер УЖЕ тикает
await p;               // просто ждём результат
```

**Последовательно vs параллельно:**
```js
// 1000 мс
for (const u of urls) await f(u);

// 500 мс — все стартовали сразу, Promise.all только ждёт
await Promise.all(urls.map(u => f(u)));
```

**Ждалка:**
```js
const delay = ms => new Promise(r => setTimeout(r, ms));
```

**Ловушки:**
- `arr.map(async x => ...)` возвращает массив промисов, не значений
- `Promise.all` падает на первой ошибке → `Promise.allSettled` когда нужны все
- Тяжёлые вычисления в главном потоке = зависший UI → Web Worker

---

## Замыкания (урок 02)

**Замыкание** — функция + окружение, в котором она создана.

Фрейм не умирает, пока на него кто-то ссылается. Это `[&]`-захват C++, который никогда не протухает.

**Захватывается переменная, а не значение.**

```js
function makeCounter() {
  let count = 0;                  // приватная, снаружи не достать
  return { inc: () => ++count, get: () => count };
}
```

**`var` vs `let` в цикле:**
```js
for (var i = 0; i < 3; i++) setTimeout(() => console.log(i));  // 3 3 3
for (let i = 0; i < 3; i++) setTimeout(() => console.log(i));  // 0 1 2
```
`var` — одна переменная на весь цикл. `let` — новая привязка на каждой итерации.

Вывод: `var` не использовать никогда. `const` по умолчанию, `let` при перезаписи.

**Как устроен `useState`** — массив + курсор:
```js
const hooks = [];
let cursor = 0;

function useState(initial) {
  const i = cursor++;                    // индекс в замыкании
  if (hooks[i] === undefined) hooks[i] = initial;
  return [hooks[i], v => { hooks[i] = v; render(); }];
}
```

Отсюда правила хуков:
- **Нельзя в условиях/циклах** — индексы разъедутся
- **Только на верхнем уровне компонента** — курсор сбрасывается перед рендером

**Stale closure.** Каждый рендер создаёт свой набор замыканий со снимком состояния. Значение внутри коллбэка — то, что было на момент **его** рендера, а не текущее.

**Паттерны:**
```js
const once = fn => { let done = false, res; 
  return (...a) => done ? res : (done = true, res = fn(...a)); };

const memoize = fn => { const c = new Map();
  return (...a) => { const k = JSON.stringify(a);
    if (!c.has(k)) c.set(k, fn(...a)); return c.get(k); }; };
```

---

## Общие правила стиля

- Бэктики только со вставками `${}`, иначе обычные кавычки
- `const` по умолчанию, `let` по необходимости, `var` никогда
- `===` всегда, `==` никогда (кроме `x == null` для проверки на null+undefined)
- `.mjs` или `"type": "module"` в package.json — для ES-модулей в Node

---

## Модули, `this`, прототипы (урок 03)

**ESM статический** → tree-shaking работает. CommonJS динамический → нет.
Динамический импорт: `const m = await import('./x.js')` — основа code splitting.

**`this` определяется вызовом, а не объявлением:**
```js
f()          // undefined (strict)
obj.f()      // obj
new F()      // новый объект
f.call(x)    // x
```
Оторвал метод от объекта — потерял `this`.

**Стрелка не имеет своего `this`** — берёт лексически, из места создания.
- метод объекта → обычная функция
- коллбэк внутри метода → стрелка

**Прототипы:** поиск свойства идёт по цепочке. `class` — сахар над этим. В React с хуками `this` не встречается вообще.

---

## Синтаксис (урок 04)

```js
const { a, b: alias, c = 1, ...rest } = obj;
const [x, , z] = arr;
function C({ label, on = false }) {}        // так пишут React-компоненты
```
Значение по умолчанию только на `undefined`, не на `null`/`0`.

**Spread поверхностный:**
```js
{ ...state, fft: { ...state.fft, size: 2048 } }   // распаковка на каждом уровне
```

**`??` vs `||`:**
```js
0 || 100   // 100 ❌
0 ?? 100   // 0  ✅
```
Для чисел и строк всегда `??`.

**Мутирующие методы** (`sort`, `reverse`, `push`, `splice`) — перед ними копия или `toSorted`/`toReversed`.

---

## TypeScript: основы (урок 05)

- Типы **стираются полностью** — в рантайме их нет
- Система **тьюринг-полная** — вычисления на типах
- Система **намеренно неполноценна** — есть дыры ради практичности

**Структурная типизация:** совпадение по форме, не по имени. `implements` почти не нужен.
Лишние поля допустимы у переменной, но не у прямого литерала.

**Номинативность через бренд:** `type Id = string & { __brand: 'Id' }`

| Тип | Смысл |
|---|---|
| `any` | выключенный компилятор — не использовать |
| `unknown` | безопасный верх — для внешних данных |
| `never` | пустое множество — маркер недостижимости |

**Вывод:** аннотируй границы, не внутренности. `const x = 5` → тип `5`, `let x = 5` → `number`.

**`type` по умолчанию**, `interface` — когда нужно слияние объявлений.

tsconfig обязательно: `strict: true`, `noUncheckedIndexedAccess: true`.

---

## Union / intersection (урок 06)

**Тип = множество значений.** `never` ⊂ всё ⊂ `unknown`.

**Union `|`** — доступны только операции, общие для всех членов.
**Intersection `&`** — для объектов слияние полей, для примитивов обычно `never`.

```ts
type A = ('a'|'b') & ('b'|'c');    // 'b'
type C = { x: number } & { x: string };  // x: never
```

`?` vs `| undefined`: с `?` поле можно не указывать, с `| undefined` — обязано присутствовать.
Проверка на оба: `if (x != null)`.

**`keyof` / `typeof`:**
```ts
type K = keyof T;              // union ключей
type T = typeof value;         // тип значения
type V = T[K];                 // indexed access
```

---

## Narrowing (урок 07)

Сужатели: `typeof`, `===` с литералом, `in`, `instanceof`, `Array.isArray`, проверка на истинность, дискриминант.

**Сужение теряется в замыканиях** — скопируй в `const`.

**Свой предикат:**
```ts
function isX(v: unknown): v is X { ... }
items.filter((x): x is string => x !== null);   // без аннотации не сузит
```

**Утверждение:**
```ts
function assertDefined<T>(x: T | null): asserts x is T { ... }
```

**Проверка исчерпанности:**
```ts
function assertNever(x: never): never { throw new Error(); }
default: return assertNever(state);
```

`as` и `!` ничего не проверяют — это заявления, не доказательства.

---

## Discriminated unions (урок 08)

**Главный приём TypeScript.** Union объектов с общим полем-тегом литерального типа.

```ts
type State =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };
```

Недопустимое состояние **невыразимо** → не возникнет в рантайме.

Разбор — `switch` по тегу + `assertNever` в `default`. Добавил вариант → компилятор показал все места.

```ts
type Circle = Extract<Shape, { kind: 'circle' }>;
type Kinds = Shape['kind'];
```

Где встретится: `useReducer` actions, состояние запроса, props с вариантами.

---

## Generics (урок 09)

Шаблоны C++, но без инстанцирования — типы стираются, функция одна.

```ts
function get<T, K extends keyof T>(obj: T, key: K): T[K] { return obj[key]; }
```

Тело проверяется **сразу** по ограничению (как concepts / trait bounds), не при использовании.

**Правило: параметр типа должен появляться минимум дважды.** Один раз — это замаскированный `as`.

```ts
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };
```

В `.tsx` стрелка требует запятой: `<T,>(x: T) => x`

Массивы ковариантны намеренно небезопасно — сознательная дыра.

---

## Utility types (урок 10)

```ts
Partial<T> Required<T> Readonly<T>        // модификаторы, ПОВЕРХНОСТНЫЕ
Pick<T,K> Omit<T,K>                       // поля объекта
Exclude<T,U> Extract<T,U> NonNullable<T>  // члены union
Record<K,V>                               // словарь
Parameters<F> ReturnType<F> Awaited<T>    // из функций
Uppercase Capitalize ...                  // строки
```

`Pick` проверяет ключи, **`Omit` — нет**: `Omit<T,'опечатка'>` компилируется молча.

`Record<UnionKey, V>` требует все ключи — таблица, синхронизированная с типом.

`Omit` убирает поля объекта, `Exclude` — члены union. Не путать.

---

## Conditional / mapped (урок 11)

```ts
T extends U ? X : Y                       // условный тип
```

**Распределение по union** — если T голый параметр, применяется к каждому члену:
```ts
type Exclude<T,U> = T extends U ? never : T;
```
Отключить: `[T] extends [U]`.

**`infer` — захват типа** (аналог частичной специализации C++):
```ts
type El<T> = T extends (infer E)[] ? E : never;
type Ret<T> = T extends (...a:any[]) => infer R ? R : never;
```

**Mapped types:**
```ts
{ [K in keyof T]?: T[K] }                 // Partial
{ [K in keyof T]-?: T[K] }                // Required
{ -readonly [K in keyof T]: T[K] }        // Mutable
{ [K in keyof T as `get${Capitalize<K & string>}`]: () => T[K] }   // переименование
{ [K in keyof T as T[K] extends string ? K : never]: T[K] }        // фильтр
```

**Template literals:** `` `on${Capitalize<E>}` ``, разбор строк через `infer`.

Глубина рекурсии ~50, хвостовой — ~1000.

---

## `as const` / `satisfies` (урок 12)

```ts
const A = ['x','y'] as const;
type T = typeof A[number];          // 'x' | 'y' — один источник истины
```

```ts
const t = { a: {...}, b: {...} } satisfies Record<string, Info>;
type K = keyof typeof t;            // 'a' | 'b' — точный union
```

| Нужно | Инструмент |
|---|---|
| проверить, забыть детали | `: Type` |
| проверить, сохранить детали | `satisfies Type` |
| зафиксировать литералы | `as const` |
| соврать компилятору | `as Type` — избегать |

tsconfig: `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noEmit`, `verbatimModuleSyntax`, `skipLibCheck`.

**Vite типы не проверяет** — гоняй `tsc --noEmit` отдельно.

---

## Практикум типов (урок 13)

```ts
type Prettify<T> = { [K in keyof T]: T[K] } & {};    // развернуть пересечение
type IsNever<T> = [T] extends [never] ? true : false;
type IsAny<T> = 0 extends 1 & T ? true : false;
type Len<T extends any[]> = T['length'];             // счётчик через кортеж
```

Хвостовая рекурсия — накапливай в `Acc`, не собирай на возврате.

---

## React: компоненты и JSX (урок 14)

Компонент = чистая функция `props → описание UI`. Имя с большой буквы.

**JSX это вызовы функций**, результат — объект-описание, не DOM.

```jsx
{cond ? <A/> : <B/>}          // условие выражением
{n > 0 && <List/>}            // ОСТОРОЖНО: {n && ...} при 0 отрендерит "0"
className htmlFor onChange    // не class/for
style={{ marginTop: 8 }}      // объект, camelCase
```

Props иммутабельны. Данные вниз, события вверх.

**Фазы:** trigger → render (может повториться/отмениться) → commit (однократно).
StrictMode вызывает компоненты дважды — чтобы нечистота вылезла сразу.

---

## `useState` и реконсиляция (урок 15)

**Состояние — снимок.** `count` константа внутри рендера.

```tsx
setCount(count + 1); setCount(count + 1);   // +1!
setCount(c => c + 1); setCount(c => c + 1); // +2 ✅
```
Зависит от старого значения → функциональная форма.

**Пакетирование:** несколько `setState` в одном событии → один рендер. `count` после `setCount` ещё старый.

**Сравнение через `Object.is`** — мутация не заметна, нужен новый объект.

**Реконсиляция:**
- разный тип элемента → поддерево пересоздаётся
- позиция определяет тождество → состояние сохраняется
- `key` управляет тождеством: смена `key` = сброс состояния

Индекс как `key` ломается при сортировке/вставке/удалении.

**Структура состояния:**
1. Не хранить производное — считать при рендере
2. Группировать меняющееся вместе
3. Размеченное объединение вместо флагов
4. Не копировать props в состояние (сброс через `key`)
5. Уплощать вложенность

```tsx
useState<User | null>(null)          // аннотация обязательна
useState<Item[]>([])                 // иначе never[]
useState(() => expensive())          // ленивая инициализация
```

---

## Списки и `key` (урок 16)

`key` — идентификатор **экземпляра компонента**, не данных. К нему привязано состояние и DOM-узел.

Индекс как `key` привязывает состояние к позиции: удалил первую строку — состояние переехало к соседу.

Источник ключа: id из данных → естественный уникальный → составной → сгенерированный при создании.
Никогда: `Math.random()`, `JSON.stringify(item)`, индекс в изменяемом списке.

`props.key` изнутри не читается — передавай id отдельно.

**`key` вне списков** — сброс состояния: `<Editor key={selectedId} />`.

Копия перед сортировкой: `[...items].sort()` или `items.toSorted()`.

---

## Подъём состояния (урок 17)

**Данные вниз через props, события вверх через коллбэки.** Обратной связи нет.

Состояние живёт в **ближайшем общем предке** всех, кому нужно.

Управляемый компонент — значение и обработчик снаружи. Неуправляемый — своё состояние. По умолчанию неуправляемый, поднимай при необходимости.

**Не должно быть состоянием:** вычислимое из props/состояния, не влияющее на отрисовку (→ ref), серверное (→ Query), живущее в URL (→ роутер), константы (→ модуль).

Prop drilling лечится по порядку: композиция → Context → стор.

`onSomething` для props, `handleSomething` для реализаций.

---

## Композиция (урок 18)

**Props для поведения и данных, слоты для содержимого.**

```tsx
<Panel header={<Icon/>} footer={<Button/>}>{children}</Panel>
```

Флаги (`showHeader`, `bordered`, `variant`) → замени на слоты.

Составные компоненты: `Panel.Header`, `Panel.Body` — для обмена данными нужен Context.

**Композиция против проброса:**
```tsx
<Layout sidebar={<Panel config={c}/>}/>   // Layout не знает про config
```
Бонус: переданный элемент не пересоздаётся при рендере обёртки.

`React.ComponentProps<'button'>` — все нативные атрибуты.
**`React.FC` не использовать** — устарел.

---

## `useEffect` (урок 19)

**Не «после рендера», а синхронизация с внешним миром:** подписки, таймеры, императивные API, canvas, сокеты.

```
setup после монтирования и при изменении deps
cleanup перед следующим setup и при размонтировании
порядок: cleanup старого → setup нового
```

StrictMode вызывает setup→cleanup→setup — эффект обязан переживать повтор.

**Эффект НЕ нужен для:** производных данных, сброса состояния при смене props (→ `key`), обработки событий (→ обработчик), цепочек setState, инициализации приложения.

Критерий: логика от **действия** → обработчик; логика от **того, что компонент отображается** → эффект.

**Гонки при фетче:**
```tsx
let active = true; ...; return () => { active = false; };
const ac = new AbortController(); ...; return () => ac.abort();
```

Массив deps — «от чего зависит», не «когда запускать». Не глушить линтер.
Нестабильные deps: перенести объект внутрь → зависеть от примитивов → `useMemo`.

`useEffect(async () => ...)` — ошибка, вернёт промис.

---

## `useRef` / `useMemo` / `useCallback` (урок 20)

**`useRef`** — ячейка вне рендера: не вызывает рендер, обновляется немедленно.
DOM-узлы, таймеры, сокеты, предыдущее значение, обход stale closure.
Читать/писать во время рендера нельзя.

```tsx
useRef<HTMLCanvasElement>(null)     // RefObject — для ref={}
useRef<number | null>(null)          // MutableRefObject — своё значение
```

**`useMemo`** — только для реально дорогого (>1 мс) или для стабильной ссылки в deps.
**`useCallback`** — только стабильная ссылка. Без `React.memo` на ребёнке бесполезен.

`memo` + `useMemo` + `useCallback` работают **вместе или никак**.

**Порядок оптимизации:** убрать лишнее состояние → опустить состояние вниз → композиция через children → профайлер → и только потом мемоизация.

**Высокочастотные данные** (60 Гц): в ref, отрисовка через `requestAnimationFrame`, в состояние — агрегаты по таймеру.

React Compiler (19+) расставляет мемоизацию сам — проверь, включён ли.

---

## Правила и кастомные хуки (урок 21)

1. Только на верхнем уровне — не в условиях, циклах, после раннего `return`
2. Только из компонентов и хуков

Условие **внутри** хука — можно. Переменное число хуков — нельзя.

**Кастомный хук** — функция на `use*`, вызывающая хуки. Переиспользуется логика, не состояние.

```tsx
return [value, setValue] as const;      // кортеж — as const обязателен
return { data, error, isLoading };      // объект при >2 значениях
```

Возвращаемые функции — в `useCallback`, иначе цикл у потребителя.

Асинхронный хук возвращает размеченное объединение, а не `{data, loading, error}`.

Если внутри нет хуков — это обычная функция, не хук.

Тесты: `renderHook` + `act` из `@testing-library/react`.

---

## Типизация props (урок 22)

```tsx
type Props = { label: string; unit?: string; onChange: (v: number) => void };
function Field({ label, unit = '', onChange }: Props) {}
```
Дефолт в деструктуризации сужает тип внутри. `defaultProps` удалён в React 19.

| Тип | Что |
|---|---|
| `ReactNode` | всё рендеримое — по умолчанию |
| `ReactElement` | результат JSX, без строк |
| `ComponentType<P>` | сам компонент как значение |

**Нативные атрибуты:**
```tsx
React.ComponentPropsWithoutRef<'button'>
React.ComponentProps<typeof MyComponent>
Omit<ComponentProps<'input'>, 'onChange'> & { onChange: (v: number) => void }
```
Конфликт имён без `Omit` даёт `never`.

**Взаимоисключающие props** — union + `field?: never`. Деструктурировать union в параметрах нельзя — сужай внутри.

Обработчик отдаёт **значение**, а не событие: `onChange: (value: string) => void`.
`items: readonly T[]`, не `Item[]`.

---

## Дженерик-компоненты (урок 23)

```tsx
function List<T>({ items, renderItem }: Props<T>) {}   // function, не const
const f = <T,>(x: T) => x;                              // в .tsx нужна запятая
```

**Колонки, знающие тип своего поля:**
```tsx
type Column<T, K extends keyof T = keyof T> = { key: K; render?: (v: T[K]) => ReactNode };
type AnyColumn<T> = { [K in keyof T]: Column<T, K> }[keyof T];
```

`React.memo(List) as typeof List` — memo теряет дженерик.
React 19: `ref` обычный props, `forwardRef` не нужен.

Дженерик не нужен, если тип фиксирован или `T` встречается один раз.

---

## События и refs (урок 24)

**`currentTarget` типизирован, `target` — нет** (`EventTarget`). Используй первый.

```tsx
React.MouseEvent<HTMLButtonElement>
React.ChangeEvent<HTMLInputElement>       // e.target.value
React.FormEvent<HTMLFormElement>          // e.preventDefault()!
React.KeyboardEvent<HTMLInputElement>     // e.key
React.PointerEvent<T>                     // лучше mouse: мышь+тач+стилус
```
В инлайн-обработчиках аннотация не нужна.

**В эффектах события НАТИВНЫЕ** — `KeyboardEvent`, не `React.KeyboardEvent`.
`WindowEventMap[K]` — типобезопасный `useEventListener`.

```tsx
useRef<HTMLInputElement>(null)     // | null обязателен, обращение через ?.
<canvas ref={setNode} />           // callback ref → состояние → эффекты по [node]
```

`tabIndex={0}` — иначе элемент не получит фокус и `onKeyDown` не сработает.
`<button>` в форме по умолчанию `type="submit"`.
`useImperativeHandle` — редко: фокус, прокрутка, экспорт canvas.

---

## `useReducer` (урок 25)

```tsx
const [state, dispatch] = useReducer(reducer, initial);
```
`dispatch` **стабилен** — можно в deps без `useCallback`.

Брать вместо `useState`, когда: поля меняются вместе, сложная зависимость от предыдущего, >3 состояний, есть недопустимые комбинации, логику надо тестировать.

**Действия — размеченное объединение** + `assertNever` в `default`.

**Автомат:** состояние тоже union, редьюсер проверяет текущее состояние перед переходом:
```tsx
case 'run/progress':
  if (state.status !== 'running') return state;   // событие не вовремя — игнор
```

Редьюсер **чистый**. Эффекты: в обработчике (следствие действия) или в эффекте по состоянию (следствие того, что система в состоянии X).

`React.Dispatch<Action>` — тип для props. Лучше передавать конкретные коллбэки, чем сам `dispatch`.

Тестируется вызовом функции, без React.

---

## Vite и структура (урок 26)

Dev — нативный ESM без бандла (esbuild). Prod — Rollup. Могут расходиться: проверяй `build && preview`.

```ts
resolve.alias: { '@': path.resolve(__dirname, './src') }   // + paths в tsconfig
server.proxy: { '/api': {...}, '/ws': { ws: true } }
```

`import.meta.env.VITE_*` — только с префиксом попадает в бандл. **Всё в бандле публично.**

**Структура по фичам:**
```
app/ features/<name>/{components,hooks,state,index.ts} ui/ lib/
```
Зависимости внутрь: `app → features → ui/lib`. Фичи общаются через `index.ts`.
`ui/` не знает домена, `lib/` не знает React.

```tsx
const View = lazy(() => import('./View'));    // нужен default-экспорт
```

**Web Worker:**
```ts
new Worker(new URL('./x.worker.ts', import.meta.url), { type: 'module' })
postMessage({ bins }, [bins.buffer])          // transferable — без копирования
```

`"build": "tsc --noEmit && vite build"` — Vite типы не проверяет.

---

## Роутинг (урок 27)

**URL — это состояние.** В него: страница, выбранная сущность, фильтры, сортировка, поиск, вкладка. Не в него: черновики форм, анимации, данные с сервера.

```tsx
createBrowserRouter([{ path: '/', element: <Layout/>, children: [...] }])
<Outlet />                    // место для вложенного маршрута
<Link to="/x" /> <NavLink />  // не <a> — перезагрузит страницу
useNavigate() useParams() useSearchParams() useRouteError()
```

`useParams` даёт `string | undefined` — валидируй. Полная типобезопасность — у TanStack Router.

**Query-параметры:**
```tsx
setParams(prev => { prev.set('sort', v); return prev; }, { replace: true });
```
`replace: true` для фильтров — иначе история засоряется.
Дефолты в URL не писать — держи ссылку чистой.
URL приходит извне → валидируй как внешние данные.

`errorElement` ловит ошибки **рендера**, не обработчиков и не асинхронного кода.

---

## TanStack Query (урок 28)

**Серверные данные — не состояние, а кеш.** Настоящее значение на сервере, у тебя копия.

```tsx
const q = useQuery({ queryKey: ['runs', filters], queryFn: ({signal}) => fetch(...) });
```

`queryKey` — всё, от чего зависит запрос. `queryFn` **должна бросать** (fetch не бросает на 404/500).

**Два измерения:** `status` (есть ли данные) и `fetchStatus` (идёт ли запрос).
```tsx
if (q.isPending) return <Spinner/>;        // данных нет
if (q.isError) return <Error/>;
{q.isFetching && <Refreshing/>}            // фоновое обновление поверх данных
```

**Мутации:**
```tsx
useMutation({ mutationFn, onSuccess: () => qc.invalidateQueries({queryKey}) })
```
Оптимистично: `onMutate` (cancelQueries → снимок → setQueryData) → `onError` откат → `onSettled` инвалидация.

Фабрика ключей с иерархией: `all → lists() → list(filters)`, частичная инвалидация.

`enabled: !!id` — зависимые запросы. `keepPreviousData` — пагинация без мигания.
`retry` с проверкой статуса — не повторять 404.

`res.json()` даёт `any` → валидируй схемой.

---

## Zustand (урок 29)

Нужен, когда состояние требуется в несвязанных местах. Context перерисовывает **всех** потребителей; Zustand — только подписчиков среза.

```ts
export const useStore = create<State>()((set, get) => ({ ... }));   // двойные скобки!
```

**Всегда селектор:**
```tsx
useStore()                          // ❌ рендер на любое изменение
useStore(s => s.theme)              // ✅
useStore(useShallow(s => ({a,b})))  // объект — иначе новая ссылка всегда
```
Действия стабильны — берутся без опасений.

`set` сливает поверхностно; вложенное — распаковкой или `immer`.

`persist` + `partialize` (иначе сохранятся функции) + `version`/`migrate`.

Вне React: `useStore.getState()`, `.setState()`, `.subscribe()`.

Производное — в селекторе, не в состоянии. Копия `Set`/массива обязательна.

---

## Формы + Zod (урок 30)

**Схема первична, тип выводится:**
```ts
const S = z.object({ label: z.string().min(1), size: z.coerce.number() });
type T = z.infer<typeof S>;
S.safeParse(raw)   // { success: true, data } | { success: false, error }
```
`.omit() .partial() .extend() .refine({path})` — как утилиты типов, но на значениях.

**React Hook Form** — поля неуправляемые, ввод не вызывает рендер.
```tsx
const { register, handleSubmit, control, formState: { errors } } =
  useForm<T>({ resolver: zodResolver(S), defaultValues });

<input {...register('config.size')} />       // путь типизирован
errors.config?.size?.message
<Controller name="x" control={control} render={({field}) => <Select {...field}/>} />
```
`formState` — прокси: подписка только на читаемые поля.
`setError('root')` — ошибка не привязанная к полю.
`z.input` ≠ `z.infer` при `coerce`.

**Валидация на границе:** сеть, форма, URL, файл, сообщение воркера. Внутри — типы.

---

## Стили (урок 31)

Выбери одно: **CSS Modules** (обычный CSS, изоляция, два файла) или **Tailwind** (всё в разметке, единая шкала, мёртвых стилей не бывает). Не смешивать.

```ts
export const cn = (...i: ClassValue[]) => twMerge(clsx(i));
```
`twMerge` разрешает конфликты — без него внешний `className` не перекроет внутренний. `className` последним.

```tsx
const variants = {...} satisfies Record<Variant, string>;
```

Темы — CSS-переменные + атрибут на `<html>`. Переключение без рендера React.

`focus-visible`, не `focus`. `disabled:` от нативного атрибута, не от класса.
`tabular-nums` для числовых колонок.
Canvas: атрибуты `width/height` — буфер, CSS — отображение; синхронизируй с `devicePixelRatio`.

---

## Тесты (урок 32)

Vitest использует конфиг Vite — алиасы и TS уже работают. `environment: 'jsdom'`.

**Приоритет отдачи:** чистые функции → редьюсеры → компоненты с поведением → сценарии.

**Тестируй как пользователь:**
```tsx
getByRole('button', { name: 'Сохранить' })   // лучший селектор
getByLabelText / getByText / getByTestId     // по убыванию
getBy* бросает | queryBy* → null | findBy* → промис
await user.click(...)                         // userEvent, не fireEvent, всегда await
```

Query в тестах: `retry: false`, новый `QueryClient` на тест.
MSW: `onUnhandledRequest: 'error'`, `server.use()` для переопределения.
Фейковые таймеры: `vi.useFakeTimers()` + `act(() => vi.advanceTimersByTime(n))`.

**jsdom не умеет:** canvas-отрисовку, размеры (`getBoundingClientRect` → нули), воркеры, `ResizeObserver`. Выноси логику в чистые функции вместо моков.

**Плохой тест:** проверяет внутренности, повторяет формулу реализации, цепляется за классы и структуру DOM.

---

## Архитектура проекта (урок 33)

**Карта состояния — главное решение:**

| Что | Где |
|---|---|
| параметры анализа | URL |
| настройки, тема, выделение | Zustand |
| ход текущей операции | `useReducer` |
| серверные данные | Query |
| высокочастотные данные | `useRef` |
| черновик формы | RHF |

Одно значение — одно место. Дублей быть не должно.

**Слои, зависимости только вниз:** UI → хуки → домен (`lib/`) → инфраструктура.
Проверка: можно ли взять `lib/` в Node-скрипт?

**Три контура по частоте:**
1. пользовательский ввод — обычный React
2. статус и метрики — состояние, агрегированное по таймеру (1 Гц)
3. данные для отрисовки — ref + `rAF`, React не участвует

**Границы:** URL, API, файл, сокет, воркер — на каждой валидация. Бинарные данные: проверяй структуру (длину, заголовок), не содержимое.

Веди список того, чего в проекте сознательно НЕТ.

---

## Canvas и типизированные массивы (урок 34)

```ts
new Float32Array(buf, offset, len)   // ПРЕДСТАВЛЕНИЕ, offset кратен 4
floats.slice()      // копия
floats.subarray()   // представление
DataView.getUint32(0, true)          // little-endian явно — для протоколов
```

**Один путь вместо тысячи `stroke()`.**

**Min/max прореживание** при плотности >1 точки на пиксель: O(ширины) вместо O(точек), пики не теряются. `x + 0.5` для чёткой линии.

**Слои по частоте:** сетка (при ресайзе) / данные (60 Гц) / курсор (движение мыши) — отдельные canvas.

**dpr:** `canvas.width = css * dpr` + `ctx.scale(dpr, dpr)`. Изменение `width` сбрасывает состояние контекста.

**Водопад:** `drawImage(canvas, 0, 1)` — сдвиг, потом `putImageData` одной строки.
Цветовая карта — viridis/magma, не радуга.

**Данные не через props:** `getBins: () => Float32Array | null` + `useCallback`.

canvas 2D хватает до ~100k точек при 60 Гц. Дальше — WebGL. `OffscreenCanvas` — отрисовка из воркера.

---

## WebSocket-поток (урок 35)

Соединение переживает навигацию → живёт в сторе, не в компоненте. Сам сокет — модульная переменная, не в состоянии.

```ts
socket.binaryType = 'arraybuffer';   // 'blob' по умолчанию — медленнее
```

**Переподключение:** экспоненциальная задержка + джиттер ±50%. Не переподключаться при коде 1000, намеренном отключении, исчерпании попыток.

**Горячий путь без React:**
```ts
case 'packet': latestRef.current = e.data;   // ни setState, ни dispatch
```

**Три частоты:** приём (сколько шлют) → ref; отрисовка (60 Гц) → `rAF`; метрики (1 Гц) → `setState`.

Обратное давление: отбрасывать (реальное время) или кольцевой буфер (нужна история).

Heartbeat раз в 20 сек — прокси рвут тихие соединения.
`sequence` в пакете — обнаружение потерь.
StrictMode покажет неправильную очистку сразу.

---

## Производительность (урок 36)

**Не оптимизируй по догадке.** Profiler → flame graph → «что рендерится зря».
Бюджет кадра 16.6 мс, на JS ~8-10.

**Порядок:** убрать лишнее состояние → опустить вниз → композиция → данные из React в ref → профилировать → мемоизация → виртуализация → воркер.

**Три диагноза:**
- много рендеров → состояние выше нужного, подписка на весь стор
- один долгий рендер → тяжёлое вычисление, огромный список
- тормозит браузер (Layout/Paint >> Scripting) → много DOM-узлов, дорогие свойства

**Дёшево:** `transform`, `opacity` (GPU).
**Дорого:** размеры, отступы, `box-shadow`; чтение `offsetWidth` после записи стиля (forced reflow).

Виртуализация — от тысяч строк. `transform: translateY`, не `top`.

`SharedArrayBuffer` + `Atomics` — общая память и настоящая отмена расчёта (нужны COOP/COEP).
WASM даёт 1.5-3x над оптимизированным JS, не десятки. Сначала воркер, потом алгоритм, потом WASM.

Начальный JS: до 200 КБ сжатого — хорошо, за 500 — разбираться.
