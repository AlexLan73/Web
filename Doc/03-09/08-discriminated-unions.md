# Урок 08. Discriminated unions — моделирование состояний

Центральный урок блока. Если из всего TypeScript запомнить один приём — этот.

---

# Часть 1. Теория

## 8.1 Что это

**Размеченное объединение** — union объектов, где у каждого варианта есть общее поле с уникальным литеральным значением. Это поле называется дискриминантом или тегом.

```ts
type Shape =
  | { kind: 'circle'; radius: number }
  | { kind: 'rect'; width: number; height: number }
  | { kind: 'line'; from: Point; to: Point };
```

`kind` — дискриминант. По нему компилятор однозначно определяет вариант и открывает доступ к его полям.

Прямой аналог `std::variant` + `std::visit`. Отличия в лучшую сторону: тег виден в данных (удобно для сериализации, логов, отладки), сравнение — обычное `===`, и работает без визитеров.

**Требования к дискриминанту:** литеральный тип (строка, число, `boolean`), одинаковое имя во всех вариантах, различные значения. Строка предпочтительнее — читается в JSON и в отладчике.

## 8.2 Зачем: невыразимость недопустимых состояний

Основная идея типизированного дизайна:

> Если недопустимое состояние нельзя выразить типом, то его не будет и в рантайме.

Сравни. **Плоская структура:**
```ts
type Request = {
  isLoading: boolean;
  data?: Result;
  error?: Error;
};
```
Три поля → восемь комбинаций. Осмысленны три. Остальные пять — источник багов, которые компилятор не видит: `{ isLoading: true, error: e }`, `{ data: d, error: e }`, `{}`.

**Размеченное объединение:**
```ts
type Request =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: Result }
  | { status: 'error'; error: Error };
```
Ровно четыре состояния. Ни одного лишнего. `data` физически не существует нигде, кроме успеха — обратиться к ней случайно невозможно.

Это не про красоту. Это про то, что целый класс багов перестаёт компилироваться.

## 8.3 Разбор — сужение по дискриминанту

```ts
function area(s: Shape): number {
  switch (s.kind) {
    case 'circle': return Math.PI * s.radius ** 2;
    case 'rect':   return s.width * s.height;
    case 'line':   return 0;
  }
}
```

В каждой ветке `s` сужен до конкретного варианта. `s.radius` доступен только в `'circle'`.

Через `if` — то же самое:
```ts
if (s.kind === 'circle') return Math.PI * s.radius ** 2;
```

**Исчерпанность.** Если функция объявлена с типом возврата `number`, а `switch` покрыл не все варианты, TS сообщит: «не все пути возвращают значение». Это уже проверка, но слабая — молчит, если возврата нет.

Надёжный способ — `assertNever` из урока 07:
```ts
default: return assertNever(s);
```
Теперь добавление варианта в `Shape` немедленно ломает компиляцию во всех неполных `switch`. Компилятор становится списком дел.

## 8.4 Обобщённые вспомогательные типы

Извлечение варианта по тегу:
```ts
type ShapeOf<K extends Shape['kind']> = Extract<Shape, { kind: K }>;

type Circle = ShapeOf<'circle'>;    // { kind: 'circle'; radius: number }
```
`Extract<T, U>` оставляет из union только совместимые с `U` члены. Работает, потому что union распределяется по условным типам (урок 11).

Обратное — исключение:
```ts
type NotCircle = Exclude<Shape, { kind: 'circle' }>;
```

Список всех тегов:
```ts
type Kind = Shape['kind'];          // 'circle' | 'rect' | 'line'
```

## 8.5 Паттерн: конструкторы вариантов

Чтобы не писать теги руками:

```ts
const circle = (radius: number): Shape => ({ kind: 'circle', radius });
const rect = (width: number, height: number): Shape =>
  ({ kind: 'rect', width, height });
```

Плюс: опечатка в теге невозможна, создание короче, легко добавить валидацию.

## 8.6 Паттерн: диспетчер вместо `switch`

Когда веток много, `switch` разрастается. Альтернатива — таблица обработчиков:

```ts
type Handlers<R> = { [K in Shape['kind']]: (s: ShapeOf<K>) => R };

function match<R>(s: Shape, handlers: Handlers<R>): R {
  return handlers[s.kind](s as never);
}

const area = (s: Shape) => match(s, {
  circle: c => Math.PI * c.radius ** 2,
  rect:   r => r.width * r.height,
  line:   () => 0,
});
```

`[K in Shape['kind']]` — mapped type (урок 11). Ключи объекта берутся из union тегов, поэтому **пропустить обработчик нельзя** — компилятор потребует все.

`as never` внутри — вынужденная дыра: TS не умеет связать конкретный `s.kind` с соответствующим обработчиком в общем виде. Дыра локальная, спрятана в одной строке библиотечного кода.

## 8.7 Где это встретится в React

**`useReducer`** — экшены почти всегда размеченное объединение (урок 25):
```ts
type Action =
  | { type: 'setSize'; size: number }
  | { type: 'setWindow'; window: WindowFn }
  | { type: 'reset' };
```

**Состояние запроса** — TanStack Query отдаёт именно такой union, поэтому обращение к `data` вне ветки успеха не компилируется.

**Props компонента с вариантами:**
```ts
type ButtonProps =
  | { variant: 'link'; href: string }
  | { variant: 'button'; onClick: () => void };
```
Нельзя передать `href` кнопке и `onClick` ссылке. Ошибка ловится в JSX.

---

# Часть 2. Проработка

## Задача. Состояние DSP-панели целиком

Собираем всё вместе на реальной задаче.

```ts
type WindowFn = 'hann' | 'hamming' | 'blackman' | 'rect';

type Source =
  | { kind: 'file'; name: string; samples: Float32Array }
  | { kind: 'stream'; url: string; connected: boolean }
  | { kind: 'generator'; freq: number; amp: number };

type Analysis =
  | { status: 'idle' }
  | { status: 'running'; progress: number }
  | { status: 'done'; spectrum: Float32Array; elapsedMs: number }
  | { status: 'failed'; reason: string };

type AppState = {
  source: Source | null;
  fft: { size: number; window: WindowFn };
  analysis: Analysis;
};
```

**Получение отсчётов — разбор по источнику:**
```ts
async function getSamples(src: Source): Promise<Float32Array> {
  switch (src.kind) {
    case 'file':
      return src.samples;
    case 'stream':
      if (!src.connected) throw new Error('Нет соединения');
      return fetchChunk(src.url);
    case 'generator':
      return synthesize(src.freq, src.amp);
    default:
      return assertNever(src);
  }
}
```

**Отрисовка статуса:**
```ts
function statusLine(a: Analysis): string {
  switch (a.status) {
    case 'idle':    return 'Готов к запуску';
    case 'running': return `Обработка ${Math.round(a.progress * 100)}%`;
    case 'done':    return `Готово за ${a.elapsedMs} мс, ${a.spectrum.length} бинов`;
    case 'failed':  return `Ошибка: ${a.reason}`;
    default:        return assertNever(a);
  }
}
```

**Проверь, что тип действительно работает.** Попробуй написать:
```ts
const bad: Analysis = { status: 'running', spectrum: new Float32Array(10) };
// ❌ progress отсутствует, spectrum лишний
```

Компилятор не даёт собрать бессмысленное состояние. Это и есть польза.

**Теперь эксперимент на исчерпанность.** Добавь в `Analysis` вариант:
```ts
| { status: 'cancelled'; at: number }
```
Запусти `npx tsc --noEmit`. Обе функции подсветятся — компилятор перечислил все места, где надо дописать логику. Без `assertNever` они бы молча вернули `undefined` в рантайме.

**Переходы состояний как чистые функции:**
```ts
const startAnalysis = (s: AppState): AppState =>
  ({ ...s, analysis: { status: 'running', progress: 0 } });

const finishAnalysis = (s: AppState, spectrum: Float32Array, ms: number): AppState =>
  ({ ...s, analysis: { status: 'done', spectrum, elapsedMs: ms } });
```

Заметь: это уже почти редьюсер. В уроке 25 добавим экшены — тоже размеченным объединением — и получится готовый `useReducer`.

---

# Часть 3. Домашка

Папка `hw-08`.

**1.** Опиши размеченным объединением состояние соединения WebSocket: не подключено, подключается с числом попыток, подключено с временем установки, разорвано с кодом и причиной, ошибка. Напиши `describe(state): string` со `switch` и `assertNever`.

**2.** Реализуй `Extract`-подобный хелпер сам, без встроенного:
```ts
type MyExtract<T, U> = ...
type Circle = MyExtract<Shape, { kind: 'circle' }>;
```
Подсказка: условный тип `T extends U ? T : never`, распределяющийся по union. Если не получится — сделай в уроке 11, вернись сюда.

**3.** Напиши `match` из 8.6 полностью, с типами. Проверь три вещи: пропущенный обработчик не компилируется, лишний ключ не компилируется, тип возврата выводится автоматически.

**4.** Перепиши в размеченное объединение. Перечисли все недопустимые комбинации, которые устраняются:
```ts
type Player = {
  playing: boolean;
  paused: boolean;
  currentTrack?: Track;
  position?: number;
  error?: string;
  buffering: boolean;
};
```

**5.** Числовой дискриминант. Работает ли это, и в чём минус по сравнению со строковым?
```ts
type Msg = { code: 0; ok: true } | { code: 1; error: string };
```

**6.** Задача на вариантность. Почему это не компилируется и как правильно?
```ts
declare const shapes: Shape[];
const circles: Extract<Shape, { kind: 'circle' }>[] =
  shapes.filter(s => s.kind === 'circle');
```

**7.** Спроектируй тип для формы загрузки файла с валидацией. Состояния: пусто, файл выбран но не проверен, проверяется, проверен и валиден, проверен и невалиден со списком ошибок, отправляется с прогрессом, отправлен с id, ошибка отправки. Напиши функцию, возвращающую, какие кнопки активны в каждом состоянии.
