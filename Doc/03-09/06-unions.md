# Урок 06. Union, intersection, literal types

Здесь начинается то, ради чего TS вообще стоит учить. Типы как множества значений и операции над ними.

---

# Часть 1. Теория

## 6.1 Типы — это множества

Рабочая ментальная модель: **тип = множество допустимых значений**.

| Тип | Множество |
|---|---|
| `never` | ∅ |
| `'hann'` | ровно одно значение |
| `boolean` | `{true, false}` |
| `number` | все числа |
| `unknown` | всё |

Присваивание разрешено, когда множество источника — подмножество приёмника. Всё остальное следует отсюда.

## 6.2 Литеральные типы

Тип, содержащий ровно одно значение:

```ts
type Yes = 'yes';
const a: Yes = 'yes';       // OK
const b: Yes = 'no';        // ❌
```

Сам по себе бесполезен. Смысл появляется в объединении.

## 6.3 Union — объединение множеств

```ts
type WindowFn = 'hann' | 'hamming' | 'blackman' | 'rect';
type Id = number | string;
type Nullable<T> = T | null;
```

Три причины, почему union литералов — самый ценный приём в TS:

1. Компилятор ловит опечатки (`'hanning'` не пройдёт)
2. IDE даёт автодополнение прямо в месте вызова
3. Рефакторинг: добавил вариант — компилятор показал все места, которые надо обновить

**Ключевое правило работы с union:** доступны только те операции, которые допустимы для **всех** членов.

```ts
function f(x: string | number) {
  x.toFixed(2);        // ❌ у string нет toFixed
  x.toString();        // ✅ есть у обоих
}
```

С union объектов — только общие поля:
```ts
type A = { kind: 'a'; foo: string };
type B = { kind: 'b'; bar: number };

function g(x: A | B) {
  x.kind;              // ✅ есть в обоих
  x.foo;               // ❌ нет в B
}
```
Как получить доступ к `foo` — урок 07 (narrowing) и 08 (discriminated unions).

**Контринтуитивное:** union типов **сужает** набор операций, хотя множество значений расширяет. Больше значений → меньше того, что с ними гарантированно можно сделать.

## 6.4 Intersection — пересечение

```ts
type WithId = { id: number };
type WithName = { name: string };
type Entity = WithId & WithName;      // { id: number; name: string }
```

Для объектов работает как слияние полей. Логика: значение должно принадлежать обоим множествам одновременно, значит иметь всё сразу.

**Для примитивов пересечение обычно пусто:**
```ts
type Impossible = string & number;    // never
```
Кроме случая с литералами того же типа — на этом и построен бренд:
```ts
type UserId = string & { __brand: 'UserId' };
```
Формально это «строка, у которой есть поле `__brand`» — недостижимо в рантайме, но компилятор считает тип населённым и использует его для номинативности.

**Конфликт полей даёт `never`:**
```ts
type X = { a: string } & { a: number };   // a: never — присвоить нельзя
```

**`&` vs `extends`:** результат почти тот же, но `interface extends` проверяет совместимость и ругается при конфликте, а `&` молча создаёт `never`. Для отладки `extends` лучше.

## 6.5 Распределение union по операциям

Важнейший механизм. Union «протекает» через многие конструкции:

```ts
type Fn = (x: string) => void | (x: number) => void;   // не то же, что
type Fn2 = (x: string | number) => void;
```

Первый — функция, принимающая **либо** строку, либо число (но неизвестно какую), второй — принимающая любое из двух. Разница в вариантности, важна при передаче коллбэков.

Полезное следствие: union внутри массива и массив union — разные вещи.
```ts
type A = (string | number)[];      // массив, элементы разные
type B = string[] | number[];      // либо массив строк, либо массив чисел
```
`B` строже: нельзя положить строку в массив чисел. `A` разрешает смешивать.

## 6.6 Опциональность и `null`

```ts
type User = {
  id: number;
  name?: string;              // string | undefined
  email: string | null;
};
```

`?` и `| undefined` — почти одно и то же, но не совсем:
```ts
type A = { x?: number };            // поле можно не указывать
type B = { x: number | undefined }; // поле указать ОБЯЗАТЕЛЬНО, можно undefined

const a: A = {};                    // OK
const b: B = {};                    // ❌ x отсутствует
```

**Соглашение по смыслу:** `undefined` — «значения нет / не задано», `null` — «явно пусто». Ошибка большинства кодовых баз — использовать оба вперемешку. Выбери одно. В React-мире практика — `undefined` для «не передано», `null` для «загружено и пусто».

Проверка сразу на оба:
```ts
if (value != null) { }        // единственный случай, где == уместен
```

## 6.7 `keyof` и `typeof`

Два оператора, соединяющие мир значений и мир типов.

**`typeof`** (в позиции типа) — взять тип существующего значения:
```ts
const defaults = { size: 1024, window: 'hann' };
type Defaults = typeof defaults;      // { size: number; window: string }
```

**`keyof`** — union ключей типа:
```ts
type Keys = keyof Defaults;           // 'size' | 'window'
```

В связке — типобезопасный доступ по ключу:
```ts
function get<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}
get(defaults, 'size');       // number
get(defaults, 'nope');       // ❌
```
`T[K]` — indexed access, тип поля по ключу. Дженерики разберём в 09, но конструкция настолько частая, что запомни форму сейчас.

---

# Часть 2. Проработка

## Задача. Моделирование состояния загрузки

Классическая задача, где union решает реальную проблему.

**Плохо — «плоская» структура:**
```ts
type State = {
  loading: boolean;
  data: Spectrum | null;
  error: Error | null;
};
```

Что не так: тип допускает бессмысленные комбинации. `{ loading: true, data: {...}, error: {...} }` — компилируется, а смысла не имеет. Восемь комбинаций трёх полей, валидны три. Компилятор не помогает — приходится помнить самому.

**Хорошо — union состояний:**
```ts
type State =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: Spectrum }
  | { status: 'error'; error: Error };
```

Теперь недопустимые состояния **невыразимы**. `data` физически существует только в успехе, `error` — только в ошибке. Это и есть «making illegal states unrepresentable» — центральная идея типизированного дизайна.

Прямая аналогия с `std::variant` — размеченное объединение. Отличие: тег (`status`) ты пишешь руками, зато можно выбрать любое поле и любой набор значений.

Работа с ним:
```ts
function render(state: State): string {
  switch (state.status) {
    case 'idle':    return 'Ожидание';
    case 'loading': return 'Загрузка...';
    case 'success': return `Бинов: ${state.data.bins.length}`;   // data доступна!
    case 'error':   return state.error.message;                  // error доступна!
  }
}
```

Внутри каждой ветки TS **сужает** тип до конкретного варианта, и нужные поля становятся видны. Механику разберём в уроке 07, применение — в 08.

**Проверь на себе разницу.** С плоской структурой:
```ts
if (state.data) { }        // а вдруг loading тоже true? непонятно
```
С union — состояние всегда однозначно.

## Мелкое, но полезное: `satisfies` при описании таблиц

```ts
const windows = {
  hann:     { alpha: 0.5 },
  hamming:  { alpha: 0.54 },
  blackman: { alpha: 0.42 },
} satisfies Record<string, { alpha: number }>;

type WindowFn = keyof typeof windows;    // 'hann' | 'hamming' | 'blackman'
```

Union выводится из объекта, а не дублируется руками. Добавил окно — тип обновился сам. Подробно про `satisfies` в уроке 12.

---

# Часть 3. Домашка

Папка `hw-06`.

**1.** Опиши тип события WebSocket для стрима данных: подключено, отключено с кодом, получен пакет с `Float32Array` и меткой времени, ошибка с сообщением. Через union. Затем напиши функцию-обработчик со `switch`.

**2.** Почему не компилируется и как починить двумя разными способами?
```ts
type Shape = { kind: 'circle'; r: number } | { kind: 'rect'; w: number; h: number };
function area(s: Shape) { return s.r * s.r * Math.PI; }
```

**3.** Что за типы получатся? Объясни каждый.
```ts
type A = ('a' | 'b') & ('b' | 'c');
type B = { x: number } & { y: string };
type C = { x: number } & { x: string };
type D = string & {};
type E = never | string;
type F = unknown & string;
```

**4.** Реализуй бренд для частоты и времени:
```ts
type Hz = number & { readonly __unit: 'Hz' };
type Sec = number & { readonly __unit: 'Sec' };
```
Напиши конструкторы `hz(n)`, `sec(n)` и функцию `period(f: Hz): Sec`. Убедись, что `period(sec(5))` не компилируется.

**5.** Дан объект. Не дублируя строки руками, получи из него union ключей и union значений.
```ts
const codes = { ok: 200, notFound: 404, serverError: 500 } as const;
// нужно: type Code = 'ok' | 'notFound' | 'serverError'
// нужно: type Value = 200 | 404 | 500
```

**6.** Перепиши в union состояний и объясни, какие невозможные комбинации это устраняет:
```ts
type Upload = {
  file: File | null;
  progress: number;
  done: boolean;
  cancelled: boolean;
  error?: string;
};
```
