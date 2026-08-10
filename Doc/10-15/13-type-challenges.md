# Урок 13. Практикум: type-challenges

Закрепление блока TypeScript. Теории почти нет — вместо неё техника решения и разбор приёмов.

---

# Часть 1. Теория

## 13.1 Как устроен полигон

Репозиторий `type-challenges` — задачи на чистых типах, без рантайма. Проверка через утилиту `Equal`, которая сравнивает типы на точное совпадение.

```bash
git clone https://github.com/type-challenges/type-challenges
```

Или решай в браузере на `tsch.js.org` — там песочница с проверкой.

Локально удобнее: WebStorm показывает выведенный тип по наведению, а это половина процесса отладки.

Формат задачи:
```ts
type MyPick<T, K> = any;   // твоя реализация

type cases = [
  Expect<Equal<MyPick<Todo, 'title'>, Expected1>>,
  Expect<Equal<MyPick<Todo, 'title' | 'completed'>, Expected2>>,
];
```
`Expect<Equal<A, B>>` не компилируется, если типы разошлись. Красное подчёркивание — тест не прошёл.

## 13.2 Техника отладки типов

Главная сложность — типы не выполняются пошагово. Приёмы:

**1. Промежуточные алиасы.** Разбивай цепочку на шаги:
```ts
type Step1<T> = keyof T;
type Step2<T> = Step1<T> extends string ? true : false;
```
Наводишь мышь на каждый — видишь результат.

**2. Проверка на конкретике.** Всегда параллельно с общим типом держи конкретный вызов:
```ts
type Debug = MyPick<{a: 1, b: 2}, 'a'>;   // наведи и посмотри
```

**3. `Prettify`** — разворачивает пересечения в плоский объект. Без него `A & B` показывается как `A & B`, а не как список полей:
```ts
type Prettify<T> = { [K in keyof T]: T[K] } & {};
```
Заведи сразу, будешь пользоваться постоянно.

**4. Ошибка компилятора обычно врёт про место.** «Type instantiation is excessively deep» указывает на строку использования, а причина в рекурсии типа. Смотри не туда, куда показали.

## 13.3 Приёмы, которые закрывают большинство задач

**Обход кортежа рекурсией:**
```ts
type Reverse<T extends any[]> =
  T extends [infer H, ...infer R] ? [...Reverse<R>, H] : [];
```
Отрезаем голову, рекурсия по хвосту, база — пустой кортеж.

**Счётчик через длину кортежа.** Арифметики на типах нет, но `['length']` работает:
```ts
type Length<T extends any[]> = T['length'];

type BuildTuple<N extends number, Acc extends any[] = []> =
  Acc['length'] extends N ? Acc : BuildTuple<N, [...Acc, any]>;

type Add<A extends number, B extends number> =
  [...BuildTuple<A>, ...BuildTuple<B>]['length'];
```
Так делается сложение. Умножение — рекурсией поверх сложения. Извращение, но именно так работают типизированные библиотеки единиц измерения.

**Разбор строки:**
```ts
type Chars<S extends string> =
  S extends `${infer C}${infer Rest}` ? [C, ...Chars<Rest>] : [];
```

**Отключение распределения:**
```ts
type IsNever<T> = [T] extends [never] ? true : false;
```
Без скобок `never` распределился бы в пустой union и вернул `never`, а не `true`. Классическая ловушка.

**Проверка на `any`:**
```ts
type IsAny<T> = 0 extends 1 & T ? true : false;
```
Работает, потому что `1 & any` даёт `any`, а `0 extends any` истинно. С любым другим типом `1 & T` даёт `never`.

**Хвостовая рекурсия** — накапливай в аккумуляторе, не собирай на возврате:
```ts
// плохо: глубина ~50
type Repeat<T, N, > = ... [T, ...Repeat<...>];

// хорошо: глубина ~1000
type Repeat<T, N extends number, Acc extends T[] = []> =
  Acc['length'] extends N ? Acc : Repeat<T, N, [...Acc, T]>;
```

## 13.4 Что из этого пригодится в React

Честно: напрямую — мало. Прикладной React-код почти не требует условных типов.

Косвенно — много:
- Читать типы библиотек. Сигнатуры `react-hook-form`, TanStack Query, Zod написаны именно так. Без этого блока они выглядят как шум
- Понимать ошибки компилятора. Когда TS выдаёт простыню на 40 строк, надо уметь найти в ней суть
- Дженерик-компоненты (урок 23) и типизированные пропсы с вариантами — там условные типы встречаются

Ставить целью решить все 150 задач не надо. **20–30 из easy и medium** дают нужный уровень чтения.

---

# Часть 2. Проработка

Разбор трёх задач разного уровня.

## Easy: `MyPick`

```ts
type MyPick<T, K extends keyof T> = {
  [P in K]: T[P]
};
```

Разбор: mapped type итерируется не по `keyof T`, а по переданному `K`. Ограничение `K extends keyof T` обязательно — иначе `T[P]` не скомпилируется, компилятор не знает, что `P` валидный ключ.

## Medium: `DeepReadonly`

```ts
type DeepReadonly<T> = T extends (...args: any[]) => any
  ? T
  : T extends object
    ? { readonly [K in keyof T]: DeepReadonly<T[K]> }
    : T;
```

Три ветки, и порядок важен:
1. Функция — вернуть как есть. Функции это тоже `object`, и без этой ветки мы бы разобрали их на поля
2. Объект — рекурсивно обойти поля
3. Примитив — вернуть как есть, база рекурсии

Типичная ошибка — забыть первую ветку. Массивы, кстати, обработаются второй веткой корректно: `readonly [K in keyof T]` для массива даёт `readonly T[]`.

## Medium: `Chainable`

Задача: типизировать построитель, где `.option(key, value)` накапливает поля, а `.get()` возвращает итог.

```ts
type Chainable<T = {}> = {
  option<K extends string, V>(
    key: K extends keyof T ? never : K,
    value: V
  ): Chainable<T & { [P in K]: V }>;

  get(): T;
};

declare const c: Chainable;
const result = c
  .option('size', 1024)
  .option('window', 'hann')
  .get();
// { size: number; window: string }
```

Ключевые моменты:

**Аккумулятор в параметре типа.** `Chainable<T>` возвращает `Chainable<T & новое поле>` — тип накапливается по цепочке вызовов. Тот же приём, что аккумулятор в хвостовой рекурсии.

**`K extends keyof T ? never : K`** запрещает повторный ключ. Если ключ уже есть, тип параметра становится `never`, и передать туда нельзя ничего. Изящный способ выразить ограничение через невозможность.

**Почему `K extends string`, а не просто `K`.** Без ограничения `K` мог бы вывестись как `string`, и mapped type дал бы индексную сигнатуру вместо конкретного поля.

Эта задача — концентрат всего блока: дженерики, ограничения, условные типы, mapped types, вывод. Если решишь её сам — блок закрыт.

---

# Часть 3. Домашка

Не файл, а список задач из репозитория. Решай в порядке возрастания.

**Easy (все):**
`Pick`, `Readonly`, `Tuple to Object`, `First of Array`, `Length of Tuple`, `Exclude`, `Awaited`, `If`, `Concat`, `Includes`, `Push`, `Unshift`, `Parameters`

**Medium (выбери 12–15):**
`Return Type`, `Omit`, `Readonly 2`, `Deep Readonly`, `Tuple to Union`, `Chainable Options`, `Last of Array`, `Pop`, `Promise.all`, `Type Lookup`, `Trim Left`, `Trim`, `Capitalize`, `Replace`, `Replace All`, `Append Argument`, `Permutation`, `Length of String`, `Flatten`, `Append to Object`, `Absolute`, `String to Union`, `Merge`

**Три задачи под наш проект — своими силами, не из репозитория:**

**1.** `UnitOf<T>` — система единиц. Определи типы `Hz`, `Sec`, `Sample` через бренд. Напиши типы `Mul<A, B>` и `Div<A, B>` так, чтобы `Div<Sample, Hz>` давал `Sec`, а `Mul<Hz, Sec>` — безразмерное число. Смешение единиц должно не компилироваться.

**2.** `EventMap` — типизированный эмиттер из домашки урока 09, но теперь с поддержкой namespace-событий: `'fft:done'`, `'fft:error'`, `'stream:packet'`. Напиши `EventsIn<'fft'>` — union событий одного namespace, выведенный из общей карты через template literal types.

**3.** `ValidateConfig<T>` — тип, который проверяет конфиг на уровне компиляции и в случае ошибки выдаёт **осмысленное сообщение** вместо `never`:
```ts
type R = ValidateConfig<{ size: 1000 }>;
// 'Ошибка: size должен быть степенью двойки'
```
Подсказка: возвращай строковый литерал с описанием вместо `never` — так делают библиотеки для читаемых ошибок.

Как закончишь — блок TypeScript закрыт, переходим к React.
