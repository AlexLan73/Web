# Урок 11. Conditional types, `infer`, mapped types

Метапрограммирование на типах. Здесь TS окончательно перестаёт быть «аннотациями» и становится языком, исполняемым компилятором.

Тебе это должно лечь ровно: логика та же, что в шаблонной метапрограмме C++, но синтаксис человеческий.

---

# Часть 1. Теория

## 11.1 Условные типы

```ts
type IsString<T> = T extends string ? true : false;

type A = IsString<'abc'>;     // true
type B = IsString<42>;        // false
```

Читается как тернарный оператор: `T extends U ? X : Y` — «если T является подтипом U, то X, иначе Y».

`extends` здесь — **не наследование**, а проверка совместимости. То есть «множество T является подмножеством U».

## 11.2 Распределение по union

Ключевой механизм, без которого половина утилит не работала бы.

Когда проверяемый тип — **голый параметр типа**, а на вход подан union, условный тип применяется **к каждому члену по отдельности**, а результаты объединяются.

```ts
type ToArray<T> = T extends any ? T[] : never;

type R = ToArray<string | number>;
// не (string|number)[], а string[] | number[]
```

Механика: `ToArray<string> | ToArray<number>`.

На этом построены `Exclude` и `Extract`:
```ts
type Exclude<T, U> = T extends U ? never : T;
type Extract<T, U> = T extends U ? T : never;

type X = Exclude<'a'|'b'|'c', 'a'>;
// ('a' extends 'a' ? never : 'a') | ('b' ... ) | ('c' ... )
// never | 'b' | 'c'  →  'b' | 'c'
```
`never` в union исчезает — это пустое множество, объединение с ним ничего не добавляет.

**Как отключить распределение** — обернуть в кортеж:
```ts
type IsUnion<T> = [T] extends [any] ? ... ;   // T больше не голый
type NoDistribute<T> = [T] extends [string] ? true : false;

type A = NoDistribute<string | number>;   // false — проверяется весь union целиком
```
Приём нужен часто. Запомни форму `[T] extends [U]`.

## 11.3 `infer` — захват типа

Позволяет вытащить часть типа в переменную прямо внутри условия.

```ts
type ElementOf<T> = T extends (infer E)[] ? E : never;
type A = ElementOf<string[]>;         // string

type Return<T> = T extends (...args: any[]) => infer R ? R : never;
type B = Return<() => number>;        // number

type Unwrap<T> = T extends Promise<infer U> ? U : T;
type C = Unwrap<Promise<Config>>;     // Config
```

Аналогия из C++: частичная специализация шаблона с выводом параметра. `template<class T> struct element_of<std::vector<T>> { using type = T; };` — тот же смысл, но без отдельной специализации.

**Несколько `infer` сразу:**
```ts
type Split<T> = T extends [infer Head, ...infer Tail] ? [Head, Tail] : never;
type A = Split<[1, 2, 3]>;      // [1, [2, 3]]
```

**`infer` с ограничением:**
```ts
type FirstString<T> = T extends [infer F extends string, ...any[]] ? F : never;
```

## 11.4 Рекурсия

Условные типы могут вызывать себя. Так пишутся `DeepPartial`, разбор строк, обход кортежей.

```ts
type DeepReadonly<T> = T extends object
  ? { readonly [K in keyof T]: DeepReadonly<T[K]> }
  : T;

type Flatten<T> = T extends (infer E)[] ? Flatten<E> : T;
type A = Flatten<number[][][]>;      // number
```

Глубина рекурсии ограничена (около 50 уровней, для хвостовой — до 1000). При превышении — ошибка «Type instantiation is excessively deep».

## 11.5 Mapped types

Преобразование каждого поля объекта.

```ts
type Mapped<T> = { [K in keyof T]: NewType };
```

Базовые примеры — это и есть реализации утилит из урока 10:
```ts
type Partial<T>  = { [K in keyof T]?: T[K] };
type Required<T> = { [K in keyof T]-?: T[K] };
type Readonly<T> = { readonly [K in keyof T]: T[K] };
type Mutable<T>  = { -readonly [K in keyof T]: T[K] };
```

`+`/`-` перед `?` и `readonly` добавляют или снимают модификатор. `-?` — «убрать необязательность».

**Переименование ключей через `as`:**
```ts
type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K]
};

type G = Getters<{ size: number; name: string }>;
// { getSize: () => number; getName: () => string }
```

**Фильтрация полей** — вернуть `never` в позиции ключа, и поле исчезнет:
```ts
type OnlyStrings<T> = {
  [K in keyof T as T[K] extends string ? K : never]: T[K]
};
```

Вот теперь читается загадочная конструкция из урока 10:
```ts
type Keys<T> = { [K in keyof T]: T[K] extends Function ? K : never }[keyof T];
```
Разбор по шагам: mapped type ставит в каждое поле либо его имя, либо `never`. Затем `[keyof T]` — indexed access по всем ключам сразу — достаёт union всех значений. `never` из union выпадает. Остаются имена полей-функций.

## 11.6 Template literal types

Строки на уровне типов.

```ts
type Event = `on${Capitalize<'click' | 'focus'>}`;   // 'onClick' | 'onFocus'
type Path = `/${string}`;
type Css = `${number}px`;
```

Union распределяется — комбинации перемножаются:
```ts
type Size = 'sm' | 'lg';
type Color = 'red' | 'blue';
type Class = `${Size}-${Color}`;
// 'sm-red' | 'sm-blue' | 'lg-red' | 'lg-blue'
```
Осторожно: комбинаторный взрыв реален. Три union по десять членов — тысяча типов, компилятор начнёт тормозить.

**Разбор строки через `infer`:**
```ts
type Params<S> = S extends `${string}:${infer P}/${infer Rest}`
  ? P | Params<`/${Rest}`>
  : S extends `${string}:${infer P}` ? P : never;

type A = Params<'/users/:id/posts/:postId'>;   // 'id' | 'postId'
```
Это не академическое упражнение — так устроена типизация роутеров (TanStack Router, урок 27): путь строкой, а параметры выводятся автоматически.

## 11.7 Когда остановиться

Метапрограммирование на типах затягивает — задача становится головоломкой ради головоломки. Практические критерии:

- Тип не читается за минуту → упрости или объяви явно
- Ошибка компилятора занимает 30 строк → тип слишком умный
- Компиляция заметно замедлилась → проверь глубину рекурсии и произведения union

Полезное правило: сложные типы уместны в **библиотечном коде**, где пишутся один раз и используются тысячи. В прикладном коде явный тип почти всегда лучше.

---

# Часть 2. Проработка

## Задача. Типобезопасный доступ по пути

Реальная задача: функция `getIn(obj, 'fft.window')` должна возвращать правильный тип.

**Шаг 1. Union всех допустимых путей.**
```ts
type Paths<T> = T extends object
  ? { [K in keyof T & string]:
      T[K] extends object
        ? K | `${K}.${Paths<T[K]>}`
        : K
    }[keyof T & string]
  : never;

type P = Paths<AppState>;
// 'source' | 'fft' | 'fft.size' | 'fft.window' | 'analysis' | ...
```

Разбор: mapped type для каждого ключа даёт либо сам ключ, либо ключ и все пути вглубь через шаблонную строку. Затем `[keyof T & string]` схлопывает объект в union значений. `& string` нужно, потому что ключом может быть `symbol`, а его в шаблон не подставить.

**Шаг 2. Тип значения по пути.**
```ts
type ValueAt<T, P extends string> =
  P extends `${infer K}.${infer Rest}`
    ? K extends keyof T ? ValueAt<T[K], Rest> : never
    : P extends keyof T ? T[P] : never;

type V = ValueAt<AppState, 'fft.window'>;    // WindowFn
```

Рекурсия по строке: отрезаем первый сегмент, спускаемся на уровень, повторяем. База — путь без точки.

**Шаг 3. Функция.**
```ts
function getIn<T, P extends Paths<T>>(obj: T, path: P): ValueAt<T, P> {
  return path.split('.').reduce<any>((acc, k) => acc?.[k], obj);
}

const w = getIn(state, 'fft.window');     // WindowFn
const x = getIn(state, 'fft.nope');       // ❌ не компилируется
```

Реализация нетипизирована внутри (`reduce<any>`) — это нормально. **Сложность прячется в сигнатуре, тело простое.** Так устроены почти все типизированные библиотеки: одна дыра внутри, полная безопасность снаружи.

**Проверь пределы.** Попробуй на структуре с массивами — `Paths` их не обрабатывает, массив это тоже `object`, и получится мусор. Доработка — упражнение в домашке.

---

# Часть 3. Домашка

Папка `hw-11`.

**1.** Реализуй сам, без встроенных: `MyExclude`, `MyExtract`, `MyNonNullable`, `MyReturnType`, `MyParameters`, `MyAwaited` (с рекурсией).

**2.** Объясни разницу и почему результаты разные:
```ts
type A<T> = T extends string ? 1 : 2;
type B<T> = [T] extends [string] ? 1 : 2;
type R1 = A<string | number>;
type R2 = B<string | number>;
```

**3.** Напиши `IsUnion<T>` — возвращает `true`, если `T` это union из двух и более членов. Подсказка: используй распределение и сравни результат с исходным типом.

**4.** `Merge<A, B>` — слияние двух объектов, где при конфликте побеждает `B`, и результат выглядит плоским (не `A & B`). Подсказка: mapped type по `keyof A | keyof B`.

**5.** Доработай `Paths<T>` из проработки: массивы должны давать индексный доступ `items.0.name` либо просто останавливать рекурсию. Выбери вариант, объясни выбор.

**6.** `CamelToSnake<S>` — преобразование `'sampleRate'` → `'sample_rate'` на уровне типов. Рекурсия по символам, `Uppercase` для проверки регистра.

**7.** Собери тип для типизированного роутера:
```ts
type Route = '/users/:userId/posts/:postId';
type P = RouteParams<Route>;    // { userId: string; postId: string }
```

**8.** Задача на понимание границ. Почему компилятор выдаст ошибку про избыточную глубину и как переписать хвостовой рекурсией?
```ts
type Repeat<T, N extends number, Acc extends T[] = []> =
  Acc['length'] extends N ? Acc : Repeat<T, N, [...Acc, T]>;
type A = Repeat<0, 2000>;
```
