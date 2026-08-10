# Урок 04. Деструктуризация, spread, современный синтаксис

Утилитарный урок. Ничего концептуально нового, но без этого синтаксиса React-код нечитаем — там он в каждой строке.

---

# Часть 1. Теория

## 4.1 Деструктуризация объектов

```js
const user = { id: 1, name: 'Alex', role: 'admin' };

const { name, role } = user;
const { name: userName } = user;              // переименование
const { theme = 'dark' } = user;              // значение по умолчанию
const { id, ...rest } = user;                 // rest: { name, role }
```

Значение по умолчанию срабатывает **только на `undefined`**, не на `null` и не на `0`:
```js
const { count = 10 } = { count: 0 };      // 0, не 10
const { count = 10 } = { count: null };   // null, не 10
```

Вложенная деструктуризация:
```js
const { config: { host, port } } = server;
```
Осторожно: `config` при этом **не объявляется**. Если нужен и он — `const { config, config: { host } } = server`.

## 4.2 Деструктуризация в параметрах

Так пишутся все React-компоненты:
```js
function Button({ label, onClick, disabled = false }) { }

// вместо
function Button(props) {
  const label = props.label;
}
```

Именованные аргументы, которых в JS нет как языковой конструкции. Порядок не важен, значения по умолчанию на месте, вызов самодокументируем.

Защита от вызова без аргумента:
```js
function f({ a = 1 } = {}) { }
f();      // работает
```

## 4.3 Деструктуризация массивов

```js
const [first, second] = arr;
const [, , third] = arr;              // пропуск позиций
const [head, ...tail] = arr;
const [a, b] = [b, a];                // обмен
```

Именно так работает `useState`:
```js
const [count, setCount] = useState(0);
```
Хук возвращает массив из двух элементов. Массив, а не объект — чтобы имена выбирал ты: `[count, setCount]`, `[name, setName]`. С объектом пришлось бы каждый раз переименовывать.

## 4.4 Spread

**Объекты** — поверхностное копирование с переопределением:
```js
const updated = { ...user, role: 'user' };         // копия с заменой поля
const merged = { ...defaults, ...overrides };      // правое побеждает
```

**Массивы**:
```js
const combined = [...a, ...b];
const copy = [...arr];
const withNew = [...arr, item];
const without = arr.filter(x => x.id !== id);
```

Это основа работы с состоянием в React. Мутировать нельзя — React сравнивает по ссылке:

```js
// ❌ мутация: ссылка та же, React не заметит
user.role = 'admin';
setUser(user);

// ✅ новый объект
setUser({ ...user, role: 'admin' });
```

**Spread поверхностный.** Вложенные объекты остаются общими:
```js
const copy = { ...state };
copy.nested.value = 1;      // изменил и оригинал тоже!
```
Для вложенного обновления — распаковка на каждом уровне:
```js
setState({
  ...state,
  filter: { ...state.filter, window: 'hann' }
});
```
Когда вложенность больше трёх уровней — это сигнал, что структуру состояния пора уплощать, либо брать Immer.

## 4.5 Опциональная цепочка и `??`

```js
const city = user?.address?.city;        // undefined вместо ошибки
const first = arr?.[0];
const result = callback?.();             // вызов, если функция есть
```

`?.` останавливает вычисление и возвращает `undefined`, как только встретил `null` или `undefined`.

**Нулевое слияние `??`** — берёт правое только при `null`/`undefined`:
```js
const port = config.port ?? 8080;
```

Отличие от `||` критично:
```js
0 || 100          // 100 — ноль ложный, а это валидное значение!
0 ?? 100          // 0 ✅
'' || 'default'   // 'default'
'' ?? 'default'   // ''
```

Правило: для чисел и строк всегда `??`. `||` только когда действительно нужно «любое ложное значение».

## 4.6 Что ещё встретишь постоянно

**Сокращённая запись свойств:**
```js
const name = 'Alex';
const obj = { name };                  // { name: 'Alex' }
```

**Вычисляемые ключи:**
```js
const key = 'dynamic';
const obj = { [key]: 1, [`${key}_2`]: 2 };
```

**Методы массивов** — вместо циклов пишутся они, всегда возвращают новый массив:
```js
arr.map(f)        // преобразование
arr.filter(p)     // отбор
arr.reduce(f, x)  // свёртка
arr.find(p)       // первый подходящий
arr.some(p) / arr.every(p)
arr.flatMap(f)
```

**Осторожно, мутирующие:** `sort`, `reverse`, `splice`, `push`, `pop` меняют массив на месте. В React перед ними обязательна копия:
```js
const sorted = [...items].sort(byName);       // ✅
const sorted = items.toSorted(byName);        // ✅ современный вариант
```

**Опциональные аргументы функций** и остаточные параметры:
```js
const sum = (...nums) => nums.reduce((a, b) => a + b, 0);
```

---

# Часть 2. Проработка

## Задача. Обновление вложенного состояния

Типичная структура состояния DSP-панели:

```js
const state = {
  signal: { sampleRate: 44100, channels: 2 },
  fft: { size: 1024, window: 'hann', overlap: 0.5 },
  view: { min: -120, max: 0 },
};
```

**Задача:** сменить размер FFT на 2048, не мутируя `state`.

```js
// ❌ мутация — React не увидит
state.fft.size = 2048;

// ❌ поверхностная копия — fft всё ещё общий объект
const wrong = { ...state };
wrong.fft.size = 2048;              // испортил и оригинал

// ✅ распаковка на каждом уровне до изменяемого поля
const next = {
  ...state,
  fft: { ...state.fft, size: 2048 },
};
```

Проверка: `next !== state` **и** `next.fft !== state.fft`, но `next.view === state.view`. Неизменённые ветки переиспользуются — это persistent data structure, и именно на этом строится оптимизация React.

**Обобщённый апдейтер** — пригодится:
```js
const updateFft = (state, patch) => ({
  ...state,
  fft: { ...state.fft, ...patch },
});

updateFft(state, { size: 2048, window: 'hamming' });
```

**Обновление элемента массива по id:**
```js
const items = [{ id: 1, on: false }, { id: 2, on: true }];

const toggled = items.map(it =>
  it.id === 1 ? { ...it, on: !it.on } : it
);
```
`map` создаёт новый массив, но неизменённые элементы остаются теми же объектами — по ссылке. Это позволяет React пропустить их перерисовку.

---

# Часть 3. Домашка

Файл `hw-04.mjs`.

**1.** Напиши `pick(obj, keys)` и `omit(obj, keys)` через деструктуризацию и `Object.entries`. Без мутаций.

**2.** Что выведет и почему по-разному?
```js
const cfg = { retries: 0, name: '', timeout: null };
console.log(cfg.retries || 3, cfg.retries ?? 3);
console.log(cfg.name || 'anon', cfg.name ?? 'anon');
console.log(cfg.timeout || 5000, cfg.timeout ?? 5000);
```

**3.** `deepMerge(a, b)` — рекурсивное слияние объектов. Простые значения из `b` перекрывают, вложенные объекты сливаются, массивы заменяются целиком.

**4.** Дано состояние из проработки. Напиши чистую функцию `setIn(state, path, value)`, где `path` — массив ключей: `setIn(state, ['fft', 'window'], 'blackman')`. Рекурсивно, без мутаций.

**5.** Есть массив объектов `{ id, name, score }`. Одним конвейером получи: отобрать `score > 50`, отсортировать по убыванию, взять топ-3, вернуть массив имён. Без мутации исходного массива — проверь это явно.

**6.** Найди ошибку и объясни, почему React не перерисует список:
```js
function addItem(state, item) {
  state.items.push(item);
  return { ...state };
}
```
