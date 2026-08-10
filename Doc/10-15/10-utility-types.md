# Урок 10. Utility types

Стандартная библиотека типов. Всё это реализовано на конструкциях из урока 11 — сначала научимся пользоваться, потом разберём устройство.

---

# Часть 1. Теория

## 10.1 Модификаторы полей

```ts
type Config = { size: number; window: WindowFn; overlap: number };

Partial<Config>    // все поля необязательны: { size?: number; ... }
Required<Config>   // все обязательны — снимает ?
Readonly<Config>   // все readonly
```

**`Partial` — для патчей и обновлений:**
```ts
function updateConfig(cfg: Config, patch: Partial<Config>): Config {
  return { ...cfg, ...patch };
}
updateConfig(cfg, { size: 2048 });     // остальное не требуется
```

Ловушка: `Partial` делает поля необязательными, но не разрешает `undefined` явно при `exactOptionalPropertyTypes`. И он **поверхностный** — вложенные объекты остаются обязательными.

```ts
type DeepPartial<T> = { [K in keyof T]?: DeepPartial<T[K]> };   // урок 11
```

**`Readonly` тоже поверхностный.** Массив внутри останется изменяемым.

## 10.2 Выбор полей

```ts
Pick<Config, 'size' | 'window'>     // { size: number; window: WindowFn }
Omit<Config, 'overlap'>             // { size: number; window: WindowFn }
```

`Pick` — белый список, `Omit` — чёрный.

**Важное различие в надёжности.** `Pick<T, K>` требует `K extends keyof T` — опечатка в ключе не скомпилируется. `Omit` этого **не** требует: `Omit<Config, 'nope'>` компилируется молча и ничего не убирает. Если поле переименуют, `Omit` тихо перестанет работать.

Строгий вариант, стоит завести у себя:
```ts
type StrictOmit<T, K extends keyof T> = Omit<T, K>;
```

## 10.3 Работа с union

```ts
Exclude<'a' | 'b' | 'c', 'a'>              // 'b' | 'c'
Extract<Shape, { kind: 'circle' }>          // только вариант circle
NonNullable<string | null | undefined>      // string
```

`Extract` — то, чем достают вариант размеченного объединения (урок 08).

**Не путай `Omit` и `Exclude`:** `Omit` убирает поля объекта, `Exclude` — члены union.

## 10.4 Словари

```ts
Record<string, number>              // { [k: string]: number }
Record<WindowFn, number>            // ровно четыре ключа, все обязательны!
```

Второй вариант — очень полезный приём. Ключи берутся из union, поэтому забыть вариант нельзя:

```ts
const coefficients: Record<WindowFn, number> = {
  hann: 0.5,
  hamming: 0.54,
  blackman: 0.42,
  // ❌ отсутствует 'rect'
};
```

Таблица, синхронизированная с типом. Добавил окно в union — компилятор потребовал коэффициент.

Для необязательного заполнения — `Partial<Record<K, V>>`.

## 10.5 Извлечение из функций

```ts
type Fn = (a: number, b: string) => Promise<Config>;

Parameters<Fn>          // [a: number, b: string]
ReturnType<Fn>          // Promise<Config>
Awaited<ReturnType<Fn>> // Config
ConstructorParameters<typeof MyClass>
InstanceType<typeof MyClass>
ThisParameterType<Fn>
```

`Awaited<T>` рекурсивно снимает промисы — работает и с `Promise<Promise<T>>`.

Типичное применение — переиспользование типа без его объявления:
```ts
const makeConfig = (size: number, window: WindowFn) => ({ size, window, overlap: 0.5 });
type Config = ReturnType<typeof makeConfig>;
```
Тип выводится из реализации, дублирования нет. Обратная сторона: изменение функции молча меняет тип по всей базе. Для внутреннего кода удобно, для публичного API лучше объявлять явно.

## 10.6 Строковые

```ts
Uppercase<'hann'>      // 'HANN'
Lowercase<'HANN'>      // 'hann'
Capitalize<'hann'>     // 'Hann'
Uncapitalize<'Hann'>   // 'hann'
```

Сами по себе редко нужны, но в связке с template literal types (урок 11) дают генерацию имён:
```ts
type Setter<K extends string> = `set${Capitalize<K>}`;
type A = Setter<'size'>;     // 'setSize'
```

## 10.7 Комбинирование

Утилиты складываются, и на этом строится большая часть практической работы с типами:

```ts
// обновление сущности: id обязателен, остальное опционально
type Update<T> = Partial<Omit<T, 'id'>> & Pick<T, 'id'>;

// то, что уходит на сервер: без служебных полей, всё readonly
type Dto<T> = Readonly<Omit<T, 'createdAt' | 'updatedAt'>>;

// только поля-функции объекта
type Methods<T> = Pick<T, {
  [K in keyof T]: T[K] extends Function ? K : never
}[keyof T]>;
```

Последнее выглядит загадочно — это mapped type с фильтрацией, разберём в уроке 11. Пока просто отметь, что такое возможно.

## 10.8 Где грань

Утилиты хороши, пока читаются. Когда тип превращается в `Partial<Omit<Extract<Record<...>>>>` на три строки — остановись и объяви явный тип. Читаемость важнее ловкости: этот код будут читать чаще, чем писать.

---

# Часть 2. Проработка

## Задача. Слои типов для DSP-панели

Один доменный тип, из него — все остальные, без дублирования.

```ts
type Analysis = {
  id: string;
  createdAt: number;
  source: string;
  fft: { size: number; window: WindowFn; overlap: number };
  spectrum: Float32Array;
  elapsedMs: number;
};
```

**Что приходит от пользователя при создании** — служебные поля сервер проставит сам:
```ts
type CreateAnalysis = Omit<Analysis, 'id' | 'createdAt' | 'spectrum' | 'elapsedMs'>;
// { source: string; fft: {...} }
```

**Что можно менять** — только конфигурацию:
```ts
type PatchAnalysis = Partial<Pick<Analysis, 'source' | 'fft'>>;
```

**Что показываем в списке** — без тяжёлых данных:
```ts
type AnalysisSummary = Omit<Analysis, 'spectrum'>;
```

**Форма в UI** — все поля строки, потому что `<input>` отдаёт строки:
```ts
type FormValues = { [K in keyof CreateAnalysis]: string };
```
Это уже mapped type, но простой — сопоставление ключей с новым типом значения.

**Таблица окон, синхронизированная с union:**
```ts
type WindowInfo = { label: string; alpha: number };

const windows: Record<WindowFn, WindowInfo> = {
  hann:     { label: 'Ханна',    alpha: 0.5  },
  hamming:  { label: 'Хэмминга', alpha: 0.54 },
  blackman: { label: 'Блэкмана', alpha: 0.42 },
  rect:     { label: 'Прямоуг.', alpha: 1    },
};

// список для выпадающего меню — берётся из таблицы, не дублируется
const options = Object.entries(windows).map(([value, info]) => ({
  value: value as WindowFn,
  label: info.label,
}));
```

Заметь `value as WindowFn` — вынужденное приведение. `Object.entries` типизирован как `[string, V][]`, потому что в рантайме у объекта могут оказаться и другие ключи (через прототип или мутацию). Это сознательное решение TS в пользу безопасности, и одно из мест, где `as` оправдан.

**Проверь на себе.** Добавь `'kaiser'` в `WindowFn` и запусти `tsc --noEmit` — объект `windows` подсветится как неполный. Тип и данные держатся вместе.

---

# Часть 3. Домашка

Папка `hw-10`.

**1.** Что вернут и почему разное?
```ts
type A = Omit<{a: 1, b: 2}, 'c'>;
type B = Exclude<'a' | 'b', 'c'>;
type C = Pick<{a: 1, b: 2}, 'c'>;
```

**2.** Реализуй `DeepPartial<T>` и `DeepReadonly<T>`. Проверь на вложенной структуре в три уровня. Учти массивы — они должны становиться `readonly T[]`.

**3.** Напиши `RequireAtLeastOne<T, K extends keyof T>` — тип, где из перечисленных ключей обязателен хотя бы один. Применение: у источника сигнала должен быть либо файл, либо URL.

**4.** Дано:
```ts
function compute(cfg: Config, samples: Float32Array): Promise<Spectrum> { ... }
```
Не объявляя новых типов вручную, получи: тип первого параметра, тип результата без промиса, тип кортежа всех параметров.

**5.** Почему `Omit` здесь не поймал ошибку, и как сделать, чтобы поймал?
```ts
type User = { id: number; name: string };
type T = Omit<User, 'nmae'>;      // опечатка
```

**6.** Собери `Record` для обработчиков всех вариантов `Analysis` из урока 08 так, чтобы пропуск варианта не компилировался. Сравни с подходом через `switch` + `assertNever` — в чём плюсы и минусы каждого.

**7.** Объясни, что делает и как читается:
```ts
type Keys<T> = { [K in keyof T]: T[K] extends Function ? K : never }[keyof T];
```
Разбери по шагам на конкретном объекте. Это упражнение на подготовку к уроку 11.
