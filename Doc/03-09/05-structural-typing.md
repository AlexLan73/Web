# Урок 05. Структурная типизация, примитивы, вывод типов

Начало блока TypeScript. Здесь важно правильно настроить голову: TS — не аннотации поверх JS, а отдельный язык, работающий на этапе компиляции. Ближе к шаблонной метапрограмме C++, чем к тайп-хинтам Python.

---

# Часть 1. Теория

## 5.1 Что такое TypeScript на самом деле

Три тезиса, задающих всю картину:

**1. Типы стираются полностью.** В рантайме от них не остаётся ничего — ни проверок, ни метаданных, ни RTTI. `tsc` выкидывает типы и выдаёт обычный JS. Отсюда: типом нельзя проверить данные с сервера, нельзя сделать `instanceof` по интерфейсу, нельзя диспетчеризовать по типу в рантайме.

**2. Система типов тьюринг-полная.** На типах можно вычислять: условия, рекурсия, работа со строками. Это полноценный язык, исполняемый компилятором. Прямая параллель с шаблонами C++.

**3. Система намеренно неполноценна (unsound).** TS сознательно допускает дыры ради практичности: `any`, приведения через `as`, ковариантность массивов. Он не доказывает корректность, а ловит ошибки. Это инструмент, а не верификатор.

## 5.2 Структурная типизация

Главное отличие от C++, Java, C#.

**Тип совпадает по форме, а не по имени.**

```ts
interface Point { x: number; y: number }
interface Vector { x: number; y: number }

const p: Point = { x: 1, y: 2 };
const v: Vector = p;              // OK — формы идентичны
```

В C++ это два разных типа, и присваивание требует конверсии. В TS они взаимозаменяемы, потому что описывают одну и ту же структуру.

Класс тоже сравнивается структурно:
```ts
class Dog { name = ''; }
class Cat { name = ''; }
const d: Dog = new Cat();         // OK!
```

Отсюда важное: **`implements` в TS почти не нужен**. Объект подходит под интерфейс автоматически, если имеет нужные поля. `implements` — только для самопроверки, что реализация не разъехалась.

**Совместимость — по принципу «не меньше»:**
```ts
const named = { x: 1, y: 2, label: 'p' };
const point: Point = named;       // OK — лишние поля допустимы
```

Но при **прямом литерале** срабатывает проверка на лишние свойства:
```ts
const point: Point = { x: 1, y: 2, label: 'p' };
//                                 ^^^^^ ошибка
```
Логика: если объект создаётся прямо здесь, лишнее поле — почти наверняка опечатка. А переменная могла прийти откуда угодно и иметь свою жизнь.

**Номинативность, когда она нужна** — эмулируется брендом:
```ts
type UserId = string & { readonly __brand: 'UserId' };
type PostId = string & { readonly __brand: 'PostId' };
// теперь UserId и PostId несовместимы, хотя оба строки
```
Полезно для идентификаторов, единиц измерения, «проверенных» значений. В рантайме — обычная строка, поле `__brand` не существует.

## 5.3 Базовые типы

```ts
let n: number;          // все числа, включая целые — отдельного int нет
let s: string;
let b: boolean;
let big: bigint;        // 10n — произвольная точность
let sym: symbol;
let u: undefined;
let nl: null;
let arr: number[];      // или Array<number>
let tup: [number, string];              // кортеж, фиксированная длина
let named: [x: number, y: number];      // именованный кортеж
```

Отдельного целочисленного типа нет — `number` это IEEE 754 double. Для битовых операций всё приводится к int32. Для больших целых — `bigint`. Тебе это будет резать глаз: `Float32Array`, `Int16Array` и прочие типизированные массивы существуют и типизированы, но их элементы всё равно `number`.

## 5.4 `any`, `unknown`, `never`

Три специальных типа, разница между которыми критична.

**`any` — выключенный компилятор.** Разрешает всё. Ошибка не исчезает, а становится невидимой. Не используй.

**`unknown` — типобезопасный верх.** Может хранить что угодно, но использовать нельзя, пока не сузишь:
```ts
function handle(data: unknown) {
  data.foo;                                // ❌
  if (typeof data === 'string') data.toUpperCase();   // ✅
}
```
Это правильный тип для JSON с сервера, для `catch (e: unknown)`, для любых внешних данных.

**`never` — низ, пустое множество.** Значения не существует. Тип функции, которая не возвращается (бросает или зацикливается). И — главное применение — маркер недостижимости:

```ts
function assertNever(x: never): never {
  throw new Error(`Unexpected: ${x}`);
}
```
С его помощью компилятор проверяет, что `switch` покрыл все варианты. Подробно в уроке 08.

Иерархия: `never` ⊂ всё ⊂ `unknown`. `any` вне иерархии — он и сверху, и снизу одновременно, чем и ломает систему.

## 5.5 Вывод типов

TS выводит типы сам. Аннотировать всё подряд — плохой стиль: дублирование, которое разъезжается.

```ts
const x = 5;             // тип 5 (литеральный!) — const не изменится
let y = 5;               // тип number — let может стать другим числом
const arr = [1, 2, 3];   // number[]
const obj = { a: 1 };    // { a: number }
```

**Правило: аннотируй границы, не внутренности.**

```ts
// ✅ параметры и возврат публичной функции
function process(input: Float32Array, size: number): Spectrum { }

// ❌ лишнее — выведется само
const result: number = compute();
const items: string[] = data.map(d => d.name);
```

Возвращаемый тип аннотировать полезно у экспортируемых функций: это контракт, и он ловит ошибку в месте определения, а не в месте использования.

**Расширение литеральных типов (widening):**
```ts
const mode = 'fast';               // тип 'fast'
let mode2 = 'fast';                // тип string — расширился

const config = { mode: 'fast' };   // { mode: string } — поля расширяются!
```
Последнее часто мешает. Лечится через `as const` (урок 12).

## 5.6 `interface` vs `type`

```ts
interface User { id: number; name: string }
type User = { id: number; name: string };
```

Практически взаимозаменяемы. Отличия:

| | `interface` | `type` |
|---|---|---|
| Слияние объявлений | да | нет |
| Union, кортежи, примитивы | нет | да |
| Условные и mapped-типы | нет | да |
| Расширение | `extends` | `&` |

**Слияние объявлений** — два `interface` с одним именем сливаются. Нужно для расширения чужих типов (например, добавить поле в `Window`). В своём коде обычно нежелательно — молчаливое изменение типа издалека.

Рабочее правило: **`type` по умолчанию**, `interface` когда нужно слияние или публичный API библиотеки.

---

# Часть 2. Проработка

## Задача. Типизация конфигурации DSP-пайплайна

Настрой проект: в папке урока `npm init -y`, `npm i -D typescript`, `npx tsc --init`.

В `tsconfig.json` обязательно:
```json
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "noUncheckedIndexedAccess": true
  }
}
```

`strict: true` — не обсуждается. Без него TS теряет половину смысла: `null` перестаёт отслеживаться, параметры становятся `any`.

`noUncheckedIndexedAccess` — менее известный, но очень полезный: `arr[i]` получает тип `T | undefined`, потому что индекс может выйти за границы. Заставляет проверять. Тебе как системщику зайдёт.

```ts
// types.ts
export type WindowFn = 'hann' | 'hamming' | 'blackman' | 'rect';

export type FftConfig = {
  size: number;
  window: WindowFn;
  overlap: number;
};

export type SignalMeta = {
  sampleRate: number;
  channels: number;
  label?: string;              // необязательное → string | undefined
};

export type Spectrum = {
  readonly bins: Float32Array;  // readonly — нельзя переприсвоить поле
  readonly freqStep: number;
};
```

```ts
// process.ts
export function computeSpectrum(
  samples: Float32Array,
  cfg: FftConfig,
  meta: SignalMeta
): Spectrum {
  const bins = new Float32Array(cfg.size / 2);
  return { bins, freqStep: meta.sampleRate / cfg.size };
}
```

Что здесь стоит заметить:

**`WindowFn` как union литералов**, а не `string`. Компилятор теперь не пропустит опечатку `'hanning'`, а IDE даст автодополнение. Это самый дешёвый и самый недооценённый приём в TS.

**`overlap: number`** — тип слабоват, ведь допустимо только `[0, 1)`. TS не умеет ограничивать диапазоны чисел. Решается брендом или рантайм-валидацией через Zod (урок 30).

**`readonly` поверхностный.** `bins` нельзя переприсвоить, но содержимое `Float32Array` менять можно. Для настоящей неизменяемости массива есть `readonly number[]`, но у типизированных массивов такого нет.

**Проверка структурности:**
```ts
const cfg = { size: 1024, window: 'hann' as const, overlap: 0.5, extra: 1 };
computeSpectrum(data, cfg, meta);       // OK — лишнее поле в переменной
computeSpectrum(data, { size: 1024, window: 'hann', overlap: 0.5, extra: 1 }, meta);
//                                                                ^^^^^ ошибка на литерале
```

---

# Часть 3. Домашка

Папка `hw-05`, файлы `.ts`. Проверяй через `npx tsc --noEmit`.

**1.** Объясни, почему компилируется, и надо ли с этим что-то делать:
```ts
class Meters { constructor(public value: number) {} }
class Feet { constructor(public value: number) {} }
function draw(m: Meters) {}
draw(new Feet(10));
```
Затем сделай так, чтобы не компилировалось, — через бренд.

**2.** Что за типы и почему разные?
```ts
const a = 'hann';
let b = 'hann';
const c = { w: 'hann' };
const d = ['hann', 'rect'];
```
Наведи мышь в WebStorm, запиши выводы.

**3.** Напиши `parseConfig(raw: unknown): FftConfig`. Внутри — рантайм-проверки полей, при несоответствии бросай ошибку. Без единого `as`. Это упражнение на то, что типы не защищают от внешних данных.

**4.** Типизируй функцию `clamp(value, min, max)` так, чтобы она работала и с `number`, и с `bigint`, но не позволяла смешивать. Дженерики ещё не проходили — попробуй через перегрузки:
```ts
function clamp(v: number, min: number, max: number): number;
function clamp(v: bigint, min: bigint, max: bigint): bigint;
```

**5.** Найди три ошибки, которые пропустит `strict: false`, но поймает `strict: true`:
```ts
function find(arr: string[], target: string) {
  const idx = arr.indexOf(target);
  return arr[idx].toUpperCase();
}
function greet(name) { return 'Hi ' + name.trim(); }
let x: string = null;
```

**6.** Почему `unknown` здесь безопаснее `any`, и что сломается при замене?
```ts
async function loadJson(url: string): Promise<unknown> {
  const r = await fetch(url);
  return r.json();
}
```
