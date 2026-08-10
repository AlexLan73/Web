# Урок 07. Narrowing и type guards

Union бесполезен, пока не умеешь его разбирать. Narrowing — механизм, которым компилятор сужает тип по ходу выполнения кода.

---

# Часть 1. Теория

## 7.1 Анализ потока управления

TS отслеживает тип переменной **по каждой ветке кода**. Это статический анализ достижимости, а не разовая проверка при объявлении.

```ts
function f(x: string | number) {
  // x: string | number
  if (typeof x === 'string') {
    // x: string
    return x.toUpperCase();
  }
  // x: number  — сюда попадаем только если не строка
  return x.toFixed(2);
}
```

В `else`-ветке тип сужается автоматически, вычитанием. Никаких приведений писать не надо.

Работает и с ранним возвратом:
```ts
function g(x: string | null) {
  if (x === null) return;
  x.length;              // x: string
}
```

**Важно и неочевидно:** сужение теряется после вызова функции, если переменная объявлена через `let` и захвачена замыканием — компилятор не может доказать, что её не изменили:

```ts
let value: string | null = get();
if (value !== null) {
  doSomething();
  value.length;          // ✅ обычно работает
}
```
Но внутри коллбэка сужение сбрасывается:
```ts
if (value !== null) {
  setTimeout(() => value.length, 0);   // ❌ value снова string | null
}
```
Лечится копированием в `const`:
```ts
const v = value;
if (v !== null) setTimeout(() => v.length, 0);   // ✅
```

## 7.2 Встроенные сужатели

**`typeof`** — для примитивов:
```ts
typeof x === 'string' | 'number' | 'boolean' | 'bigint'
             | 'symbol' | 'undefined' | 'object' | 'function'
```
Помни JS-ловушку: `typeof null === 'object'`. TS её учитывает, но читать код от этого не легче.

**Сравнение с литералом** — для union литералов:
```ts
if (window === 'hann') { }
```

**`in`** — по наличию поля:
```ts
type A = { foo: string };
type B = { bar: number };
function f(x: A | B) {
  if ('foo' in x) x.foo;     // x: A
  else x.bar;                 // x: B
}
```

**`instanceof`** — для классов и встроенных объектов:
```ts
if (err instanceof Error) err.message;
if (data instanceof Float32Array) data.byteLength;
```
Работает только с тем, что реально существует в рантайме. С интерфейсами — нельзя, их там нет.

**`Array.isArray`** — единственный корректный способ отличить массив.

**Проверка на истинность** — убирает `null`, `undefined` и все ложные значения:
```ts
if (x) { }      // осторожно: убирает и 0, и ''
if (x != null)  // убирает только null и undefined
```

**Проверка на дискриминант** — главный инструмент, урок 08:
```ts
if (state.status === 'success') state.data;
```

## 7.3 Пользовательские type guards

Когда встроенных не хватает — пишешь свой предикат:

```ts
function isSpectrum(x: unknown): x is Spectrum {
  return typeof x === 'object'
    && x !== null
    && 'bins' in x
    && x.bins instanceof Float32Array;
}

if (isSpectrum(data)) {
  data.bins.length;        // data: Spectrum
}
```

Синтаксис `x is T` — сигнал компилятору: «если функция вернула `true`, считай аргумент типом `T`».

**Опасность:** это обещание, которое компилятор **не проверяет**. Тело может врать:
```ts
function isString(x: unknown): x is string {
  return true;             // компилируется, ломает всё
}
```
Type guard — такая же дыра в системе типов, как `as`, только организованная. Пиши тело честно.

**Фильтрация массива** — самое частое применение:
```ts
const items: (string | null)[] = ['a', null, 'b'];

const clean = items.filter(x => x !== null);          // всё ещё (string|null)[]!
const clean2 = items.filter((x): x is string => x !== null);   // string[]
```
Обычный `filter` не сужает тип результата — компилятор не знает, что предикат отбирает. С аннотацией `x is string` знает.

В TS 5.5+ вывод предикатов стал умнее, и первый вариант часто работает сам. Но явная аннотация надёжнее.

## 7.4 Функции-утверждения

```ts
function assertDefined<T>(x: T | null | undefined, msg?: string): asserts x is T {
  if (x == null) throw new Error(msg ?? 'Значение отсутствует');
}

const el = document.querySelector('canvas');   // HTMLCanvasElement | null
assertDefined(el);
el.getContext('2d');                            // el: HTMLCanvasElement
```

`asserts x is T` — «если функция вернулась без исключения, считай `x` типом `T`». Сужает переменную на всю оставшуюся область видимости, без вложенности `if`.

Ограничение: работает только с `const`-объявленными функциями с явной аннотацией типа, либо с обычными `function`. Стрелка в `const` без типа не сработает.

## 7.5 Проверка исчерпанности через `never`

Самый ценный приём урока.

```ts
function assertNever(x: never): never {
  throw new Error(`Необработанный вариант: ${JSON.stringify(x)}`);
}

function render(state: State): string {
  switch (state.status) {
    case 'idle':    return 'Ожидание';
    case 'loading': return 'Загрузка';
    case 'success': return 'Готово';
    default:        return assertNever(state);
  }
}
```

Логика: после трёх `case` в `default` остаётся вариант `'error'` — то есть `state` там имеет тип `{status:'error', ...}`, а не `never`. Передать его в `assertNever(x: never)` нельзя → **ошибка компиляции**.

Стоит добавить в union новый вариант — и все `switch` без него сразу подсветятся красным. Это превращает рефакторинг из археологии в механическую работу: компилятор сам показывает список мест.

Аналог `-Werror=switch` в GCC, но работает для любых union, не только для enum.

## 7.6 Приведения — чего избегать

```ts
const x = data as Spectrum;             // «поверь мне»
const y = <Spectrum>data;               // устаревший синтаксис, в .tsx не работает
const z = data!;                        // non-null assertion
```

`as` не проверяет ничего в рантайме. Это заявление программиста, а не доказательство.

`!` — то же самое для `null`/`undefined`. Каждый `!` в коде — потенциальный `TypeError` в проде.

Когда `as` оправдан:
- Сужение после **своей** валидации, которую компилятор не понимает
- Работа с внешними API без типов
- `as const` — это другое, безопасное (урок 12)

Когда не оправдан: чтобы заткнуть ошибку. Ошибка компилятора — обычно правда.

**Двойное приведение `as unknown as T`** — способ обойти проверку совместимости. Явный признак, что что-то идёт не так. Иногда неизбежно в тестах и обёртках чужих библиотек.

---

# Часть 2. Проработка

## Задача. Разбор сообщений WebSocket

Пришли данные с сервера. Тип — `unknown`, потому что доверять нельзя.

```ts
type Packet =
  | { type: 'samples'; data: Float32Array; ts: number }
  | { type: 'meta'; sampleRate: number; channels: number }
  | { type: 'error'; message: string };
```

**Шаг 1. Валидация на входе — единственная граница с внешним миром.**

```ts
function isPacket(x: unknown): x is Packet {
  if (typeof x !== 'object' || x === null) return false;
  if (!('type' in x)) return false;

  switch (x.type) {
    case 'samples':
      return 'data' in x && x.data instanceof Float32Array
          && 'ts' in x && typeof x.ts === 'number';
    case 'meta':
      return 'sampleRate' in x && typeof x.sampleRate === 'number'
          && 'channels' in x && typeof x.channels === 'number';
    case 'error':
      return 'message' in x && typeof x.message === 'string';
    default:
      return false;
  }
}
```

Обрати внимание: внутри `switch` компилятор уже сузил `x` через `in`, и `x.type` доступен. Сужение работает и для `unknown`, если предварительно проверить `typeof` и `null`.

**Шаг 2. Обработка — уже в типизированном мире.**

```ts
function handle(raw: unknown): void {
  if (!isPacket(raw)) {
    console.warn('Неизвестный пакет', raw);
    return;
  }

  switch (raw.type) {
    case 'samples':
      process(raw.data, raw.ts);       // поля доступны, приведений нет
      break;
    case 'meta':
      configure(raw.sampleRate, raw.channels);
      break;
    case 'error':
      console.error(raw.message);
      break;
    default:
      assertNever(raw);
  }
}
```

**Что здесь принципиально:** валидация происходит **один раз, на границе**. Дальше весь код работает с типизированными данными и ни одного `as`. Это правильная архитектура — типы гарантируют корректность внутри системы, рантайм-проверка стоит на входе.

Писать такие валидаторы руками утомительно. В уроке 30 возьмём Zod: схема описывается один раз, тип выводится из неё автоматически, проверка бесплатна.

---

# Часть 3. Домашка

Папка `hw-07`.

**1.** Напиши `isNonEmpty<T>(arr: T[]): arr is [T, ...T[]]` — предикат непустого массива. Проверь, что после него `arr[0]` не имеет `undefined` в типе (нужен `noUncheckedIndexedAccess`).

**2.** Почему `filter` не сузил тип, и почему второй вариант сузил?
```ts
const raw: (number | undefined)[] = [1, undefined, 3];
const a = raw.filter(x => x !== undefined);
const b = raw.filter((x): x is number => x !== undefined);
```

**3.** Реализуй `assertNever` и добавь его в `switch` по `WindowFn` из урока 05. Затем добавь в union новое окно `'kaiser'` и убедись, что компилятор показал незакрытое место.

**4.** Что не так и как переписать без `!`?
```ts
function getCanvas(id: string) {
  const el = document.getElementById(id)!;
  return (el as HTMLCanvasElement).getContext('2d')!;
}
```

**5.** Сужение теряется. Объясни почему и почини:
```ts
class Loader {
  data: Float32Array | null = null;
  process() {
    if (this.data === null) return;
    setTimeout(() => console.log(this.data.length), 0);
  }
}
```

**6.** Напиши `narrow` для ошибок: функция `toError(e: unknown): Error`, которая корректно обрабатывает случаи, когда бросили не `Error` — строку, объект, `undefined`. Это реальная задача, `catch` всегда даёт `unknown`.

**7.** На понимание дыр. Объясни, почему это компилируется и что произойдёт в рантайме:
```ts
const nums = [1, 2, 3] as unknown as string[];
console.log(nums.map(s => s.toUpperCase()));
```
