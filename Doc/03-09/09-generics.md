# Урок 09. Generics — параметризация типов

Тебе здесь будет легче, чем большинству: это шаблоны C++, только с выводом типов и без инстанцирования в рантайме.

---

# Часть 1. Теория

## 9.1 Зачем

Дженерик — способ написать код, работающий с любым типом, **не теряя информацию о нём**.

```ts
function first(arr: unknown[]): unknown { return arr[0]; }   // тип потерян
function first<T>(arr: T[]): T { return arr[0]; }            // тип сохранён
```

`T` — параметр типа. Подставляется в момент использования и связывает вход с выходом.

**Отличие от шаблонов C++:** инстанцирования не происходит. `tsc` не генерирует по копии функции на каждый тип — типы стираются, остаётся одна функция. Поэтому нет раздувания кода, но нет и специализации по типу в рантайме.

## 9.2 Вывод из аргументов

Почти всегда параметр типа выводить не нужно — TS определит его сам:

```ts
first([1, 2, 3]);            // T = number
first(['a']);                // T = string
first<number>([1, 2]);       // явно — обычно избыточно
```

Явно указывают, когда вывод невозможен (нет аргумента нужного типа) или когда нужен более широкий тип, чем выведется.

## 9.3 Ограничения через `extends`

```ts
function longest<T extends { length: number }>(a: T, b: T): T {
  return a.length >= b.length ? a : b;
}

longest([1, 2], [1, 2, 3]);       // OK
longest('ab', 'abc');             // OK
longest(1, 2);                    // ❌ у number нет length
```

`T extends X` читается как «T должен быть подтипом X». Без ограничения `T` — это `unknown`, и делать с ним нельзя ничего.

**Ключевое отличие от C++.** Шаблоны C++ до концептов проверялись при инстанцировании — ошибка вылезала на месте использования, простынёй. TS проверяет тело функции **сразу**, по ограничению. Это ближе к concepts или к трейт-баундам Rust: контракт объявлен явно.

```ts
function bad<T>(x: T) { return x.length; }              // ❌ ошибка здесь и сейчас
function ok<T extends { length: number }>(x: T) { return x.length; }   // ✅
```

## 9.4 `keyof` в связке с дженериками

Самая частая рабочая конструкция:

```ts
function get<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

const cfg = { size: 1024, window: 'hann' as WindowFn };
get(cfg, 'size');        // number
get(cfg, 'window');      // WindowFn
get(cfg, 'nope');        // ❌
```

Три вещи работают вместе: `K extends keyof T` ограничивает ключ существующими, `T[K]` (indexed access) достаёт тип поля, вывод определяет оба параметра из аргументов.

Обобщение на путь из нескольких ключей:
```ts
function get2<T, K1 extends keyof T, K2 extends keyof T[K1]>(
  obj: T, k1: K1, k2: K2
): T[K1][K2] {
  return obj[k1][k2];
}
```

## 9.5 Значения по умолчанию

```ts
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

type A = Result<number>;              // E = Error
type B = Result<number, string>;      // E = string
```

Как аргументы по умолчанию в функциях, только для типов.

## 9.6 Дженерики в типах и интерфейсах

```ts
type Box<T> = { value: T };
type Pair<A, B> = [A, B];
type Dict<V> = Record<string, V>;

interface Repository<T, Id = number> {
  find(id: Id): Promise<T | null>;
  save(item: T): Promise<void>;
  list(): Promise<T[]>;
}
```

Рекурсивные дженерики тоже работают:
```ts
type Tree<T> = { value: T; children: Tree<T>[] };
type Json = string | number | boolean | null | Json[] | { [k: string]: Json };
```

## 9.7 Дженерик-классы и стрелки

```ts
class Buffer<T> {
  private items: T[] = [];
  push(item: T): void { this.items.push(item); }
  pop(): T | undefined { return this.items.pop(); }
}

const identity = <T,>(x: T): T => x;    // запятая обязательна в .tsx!
```

В `.tsx` файлах `<T>` парсится как JSX-тег. Обходится запятой `<T,>` или ограничением `<T extends unknown>`.

## 9.8 Типичные ошибки

**Дженерик без связи между входом и выходом — бессмысленен:**
```ts
function f<T>(x: unknown): T { return x as T; }    // это просто замаскированный as
```
Если `T` встречается только один раз в сигнатуре, он ничего не связывает. Такой дженерик — способ обмануть себя. Правило: **параметр типа должен появляться минимум дважды**.

**Слишком широкое ограничение:**
```ts
function process<T extends object>(x: T) { }       // почти любой объект
```
Ограничивай ровно тем, что используешь.

**Дженерик вместо union:**
```ts
function f<T extends 'a' | 'b'>(x: T) { }          // избыточно
function f(x: 'a' | 'b') { }                        // достаточно
```
Дженерик нужен, когда тип **связывает** аргументы с результатом. Если результат от него не зависит — бери union.

## 9.9 Вариантность коротко

TS проверяет совместимость дженериков по правилам подтипирования:

```ts
declare let animals: Animal[];
declare let dogs: Dog[];
animals = dogs;      // OK — массивы ковариантны
```

Массивы в TS ковариантны **намеренно небезопасно**: после присваивания можно положить `Cat` в `animals`, испортив `dogs`. Это одна из сознательных дыр — практичность выбрана вместо строгости.

Функции: параметры контравариантны, возврат ковариантен. Но с методами и опцией `strictFunctionTypes` есть исключения. Глубоко копать не надо, достаточно помнить: «функция, принимающая более общий тип, годится там, где ждут принимающую более частный».

---

# Часть 2. Проработка

## Задача. Типобезопасный кеш и Result

**Кеш с ключами и значениями:**

```ts
class Cache<K, V> {
  private map = new Map<K, V>();

  get(key: K): V | undefined { return this.map.get(key); }

  getOrCompute(key: K, compute: (key: K) => V): V {
    const existing = this.map.get(key);
    if (existing !== undefined) return existing;
    const value = compute(key);
    this.map.set(key, value);
    return value;
  }

  has(key: K): boolean { return this.map.has(key); }
}

const spectra = new Cache<string, Float32Array>();
spectra.getOrCompute('file1', name => compute(name));   // Float32Array
```

Обрати внимание на `compute: (key: K) => V` — параметры типа связывают аргумент коллбэка с ключом, а его возврат со значением. Ни одного `any`.

**Тонкость:** `V | undefined` в `get` не отличает «нет ключа» от «значение равно undefined». Если `V` может быть `undefined`, нужен другой протокол — например, возвращать `{ hit: boolean; value: V }`.

**Result вместо исключений** — тебе, вероятно, знакомо по Rust:

```ts
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

const ok = <T,>(value: T): Result<T, never> => ({ ok: true, value });
const err = <E,>(error: E): Result<never, E> => ({ ok: false, error });

function tryParse(raw: string): Result<FftConfig, string> {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!isFftConfig(parsed)) return err('Неверная структура');
    return ok(parsed);
  } catch {
    return err('Неверный JSON');
  }
}

const r = tryParse(input);
if (r.ok) {
  r.value.size;       // ✅ value доступно только здесь
} else {
  console.error(r.error);
}
```

Здесь встретились оба урока: дженерики параметризуют, размеченное объединение разбирает. `Result<T, never>` в `ok` — интересная деталь: тип ошибки пуст, значит при выводе union он схлопнется в тип, указанный в сигнатуре функции.

**Комбинаторы для Result** — тренировка на дженерики:
```ts
const map = <T, U, E>(r: Result<T, E>, f: (v: T) => U): Result<U, E> =>
  r.ok ? ok(f(r.value)) : r;

const unwrapOr = <T, E>(r: Result<T, E>, fallback: T): T =>
  r.ok ? r.value : fallback;
```

Заметь в `map`: в ветке `else` возвращается `r` напрямую, и это типизируется — `{ok:false, error:E}` подходит и под `Result<U,E>`, потому что при ошибке значение отсутствует.

---

# Часть 3. Домашка

Папка `hw-09`.

**1.** Напиши `groupBy<T, K extends string>(items: T[], key: (item: T) => K): Record<K, T[]>`. Проверь на массиве объектов.

**2.** `zip<A, B>(a: A[], b: B[]): [A, B][]` — попарное объединение по минимальной длине. Затем расширь до `zipWith<A, B, C>(a, b, f: (a: A, b: B) => C): C[]`.

**3.** Почему дженерик бессмысленный, и как переписать?
```ts
function parse<T>(raw: string): T { return JSON.parse(raw); }
const cfg = parse<FftConfig>(text);
```

**4.** `pick<T, K extends keyof T>(obj: T, keys: K[]): Pick<T, K>` — реализуй сам, с корректными типами. `Pick` встроенный использовать можно только в сигнатуре.

**5.** Типизируй событийный эмиттер так, чтобы имя события определяло тип полезной нагрузки:
```ts
type Events = {
  samples: Float32Array;
  meta: { rate: number };
  error: string;
};

emitter.on('samples', d => d.length);      // d: Float32Array
emitter.on('meta', d => d.rate);           // d: { rate: number }
emitter.emit('error', 42);                 // ❌
emitter.on('nope', () => {});              // ❌
```
Это реальная задача, встретишь её в любом проекте с WebSocket.

**6.** Реализуй `pipe` для двух и трёх функций с сохранением типов:
```ts
const f = pipe(
  (x: number) => x * 2,
  (x: number) => `${x}`,
  (s: string) => s.length,
);
f(5);      // number, и цепочка типов проверена
```

**7.** Объясни, почему компилируется и что сломается в рантайме:
```ts
class Animal { name = ''; }
class Dog extends Animal { bark() {} }
const dogs: Dog[] = [new Dog()];
const animals: Animal[] = dogs;
animals.push(new Animal());
dogs[1].bark();
```
