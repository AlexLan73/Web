# Урок 20. `useRef`, `useMemo`, `useCallback`

Три хука, которые чаще всего используют не по делу. `useRef` — недооценён, два других — переоценены.

---

# Часть 1. Теория

## 20.1 `useRef` — ячейка вне цикла рендера

```tsx
const ref = useRef<T>(initial);
ref.current;              // чтение и запись
```

Возвращает объект `{ current: T }`, **один и тот же** на всё время жизни компонента.

Два отличия от состояния:
- изменение `ref.current` **не вызывает рендер**
- значение обновляется **немедленно**, а не к следующему рендеру

Мысленная модель: это поле экземпляра. Состояние — то, что видит пользователь; ref — то, что помнит компонент.

**Применение 1. Ссылка на DOM-узел:**
```tsx
const canvasRef = useRef<HTMLCanvasElement>(null);
return <canvas ref={canvasRef} />;
```
React запишет узел в `current` после монтирования, обнулит при размонтировании. Тип обязательно с `| null` в начальном значении — до монтирования там пусто.

**Применение 2. Хранение изменяемого значения:**
```tsx
const timerId = useRef<number | null>(null);
const socketRef = useRef<WebSocket | null>(null);
const renderCount = useRef(0);
```
Всё, что не влияет на отрисовку. Держать это в состоянии — лишние рендеры и риск рассинхрона.

**Применение 3. Предыдущее значение:**
```tsx
function usePrevious<T>(value: T): T | undefined {
  const ref = useRef<T>();
  useEffect(() => { ref.current = value; });
  return ref.current;
}
```
Эффект без зависимостей выполняется после каждого рендера, поэтому `ref.current` всегда отстаёт на один шаг.

**Применение 4. Обход stale closure:**
```tsx
const configRef = useRef(config);
configRef.current = config;         // обновляем при каждом рендере

useEffect(() => {
  const id = setInterval(() => {
    process(configRef.current);      // всегда актуальное значение
  }, 100);
  return () => clearInterval(id);
}, []);                              // зависимостей нет, интервал не пересоздаётся
```
Приём для случаев, когда пересоздавать подписку при каждом изменении дорого. Используй осознанно — это выход из декларативной модели.

**Чего нельзя:** читать или писать `ref.current` **во время рендера**. Это делает компонент нечистым. Только в обработчиках и эффектах.
```tsx
function Bad() {
  const ref = useRef(0);
  ref.current++;                     // ❌ побочный эффект в рендере
  return <div>{ref.current}</div>;
}
```

## 20.2 `useMemo` — кеширование вычисления

```tsx
const value = useMemo(() => compute(a, b), [a, b]);
```

Пересчитывает только при изменении зависимостей. В остальных случаях возвращает прошлый результат.

**Не гарантия.** React вправе выбросить кеш — например, при нехватке памяти. Не полагайся на `useMemo` для корректности, только для скорости.

**Когда действительно нужен:**

**1. Дорогое вычисление.** Дорогое — это миллисекунды, не микросекунды.
```tsx
const window = useMemo(() => buildWindow(size, type), [size, type]);
const sorted = useMemo(() => heavySort(items), [items]);
```

Порог: если вычисление занимает меньше миллисекунды, `useMemo` скорее замедлит — у него есть своя цена (сравнение зависимостей, хранение).

**2. Стабильная ссылка для зависимостей.** Часто важнее первого:
```tsx
const options = useMemo(() => ({ size, window }), [size, window]);
useEffect(() => { connect(url, options); }, [url, options]);
```
Без `useMemo` объект новый каждый рендер → эффект срабатывает каждый рендер.

**3. Стабильные props для мемоизированного ребёнка:**
```tsx
const data = useMemo(() => transform(raw), [raw]);
return <ExpensiveChart data={data} />;    // обёрнут в React.memo
```

**Когда не нужен:** всё остальное. Простая арифметика, `filter` по сотне элементов, конкатенация строк, форматирование — оставь как есть.

## 20.3 `useCallback` — то же для функций

```tsx
const handler = useCallback(() => doSomething(a), [a]);
// эквивалент
const handler = useMemo(() => () => doSomething(a), [a]);
```

Смысл только один: **стабильная ссылка на функцию**. Функции создаются заново каждый рендер, и это проблема, если функция попадает в зависимости эффекта или в props мемоизированного компонента.

```tsx
const onSelect = useCallback((id: string) => {
  setSelected(id);
}, []);                                  // setSelected стабилен, зависимостей нет

return <MemoizedList onSelect={onSelect} />;
```

**Без `React.memo` на ребёнке `useCallback` бесполезен.** Обычный компонент перерисуется при перерисовке родителя независимо от того, изменились props или нет. Стабильная функция ничего не даст.

Это самая частая бесполезная оптимизация в React-коде: `useCallback` на всё подряд «на всякий случай». Он добавляет код, добавляет зависимости, добавляет шанс на stale closure — и не даёт ничего.

## 20.4 `React.memo`

```tsx
const Row = React.memo(function Row({ item, onSelect }: Props) { ... });
```

Оборачивает компонент: если props не изменились (поверхностное сравнение), рендер пропускается.

**Работает только когда props стабильны.** Один нестабильный props — объект, массив, функция — и мемоизация не срабатывает никогда, а накладные расходы на сравнение остаются.

Поэтому `React.memo`, `useMemo` и `useCallback` применяются **вместе или никак**. Половинчатое применение — чистый убыток.

**Когда оправдано:**
- список из сотен строк, где меняется одна
- компонент с тяжёлым рендером (график, большая таблица)
- измерено профайлером, что тормозит именно это

**Когда нет:** всё остальное. React быстро рендерит; проблема почти всегда не в количестве рендеров, а в том, что делается внутри одного.

## 20.5 Порядок оптимизации

Прежде чем тянуться к мемоизации, попробуй по порядку:

**1. Убрать лишнее состояние.** Производные данные не хранить (урок 17).

**2. Опустить состояние вниз.** Если состояние нужно одному поддереву, вынеси его туда — родитель перестанет перерисовываться:
```tsx
// ❌ ввод в поле перерисовывает всё
function App() {
  const [q, setQ] = useState('');
  return <><input value={q} onChange={...} /><HeavyChart /></>;
}

// ✅ состояние внутри SearchBox, HeavyChart не трогается
function App() {
  return <><SearchBox /><HeavyChart /></>;
}
```

**3. Композиция через children.** Элемент, созданный в родителе и переданный как props, не пересоздаётся при рендере промежуточного компонента (урок 18):
```tsx
function Wrapper({ children }) {
  const [n, setN] = useState(0);
  return <div onClick={() => setN(n+1)}>{children}</div>;
}
<Wrapper><HeavyChart /></Wrapper>       // HeavyChart не перерисуется при клике
```

**4. Профилировать.** React DevTools → Profiler. Смотри, что реально долгое.

**5. И только теперь** — `memo` / `useMemo` / `useCallback`.

Первые три приёма бесплатны и улучшают структуру. Пятый добавляет сложность.

**Про React Compiler.** Начиная с React 19 существует компилятор, автоматически расставляющий мемоизацию. Если он включён в проекте, ручные `useMemo`/`useCallback` в большинстве случаев не нужны. Проверь настройки проекта, прежде чем оптимизировать руками.

## 20.6 Типизация

```tsx
// DOM-ссылка: null в начальном значении обязателен
const ref = useRef<HTMLCanvasElement>(null);       // RefObject, current только для чтения React

// изменяемое значение
const id = useRef<number | null>(null);            // MutableRefObject
const count = useRef(0);                            // MutableRefObject<number>
```

Разница тонкая, но компилятор её чувствует. `useRef<T>(null)` даёт `RefObject<T>` с `readonly current` — предназначен для `ref={}`. `useRef<T | null>(null)` даёт изменяемый вариант — для своих значений.

```tsx
const memo = useMemo<Float32Array>(() => build(size), [size]);
const cb = useCallback<(id: string) => void>(id => { ... }, []);
```
Аннотации обычно не нужны — тип выводится из тела.

**`React.memo` с дженериком** ломает вывод типов:
```tsx
const List = React.memo(function List<T>(props: Props<T>) { ... });
// тип теряет дженерик
```
Обход — приведение:
```tsx
const List = React.memo(ListImpl) as typeof ListImpl;
```

---

# Часть 2. Проработка

## Задача. Отрисовка потока 60 кадров в секунду

Это задача 8 из домашки урока 19 — теперь есть инструменты, чтобы решить её правильно.

**Проблема.** WebSocket шлёт 60 пакетов в секунду. Наивная реализация:
```tsx
socket.onmessage = e => setState({ status: 'open', lastPacket: data });
```
даёт 60 рендеров в секунду всего дерева. React справится, но впустую — на экране всё равно 60 кадров, а перерисовывается вся панель, включая параметры и список прогонов, которые не менялись.

**Решение: данные в ref, отрисовка по кадрам.**

```tsx
// src/SpectrumStream.tsx
import { useEffect, useRef } from 'react';

type Props = {
  socket: WebSocket | null;
  minDb?: number;
  maxDb?: number;
};

export function SpectrumStream({ socket, minDb = -120, maxDb = 0 }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const latest = useRef<Float32Array | null>(null);
  const frameId = useRef<number | null>(null);

  // приём данных — без состояния, без рендеров
  useEffect(() => {
    if (!socket) return;

    const onMessage = async (e: MessageEvent<Blob>) => {
      const buf = await e.data.arrayBuffer();
      latest.current = new Float32Array(buf);      // просто перезаписываем
    };

    socket.addEventListener('message', onMessage);
    return () => socket.removeEventListener('message', onMessage);
  }, [socket]);

  // цикл отрисовки — независим от потока данных
  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;

    const draw = () => {
      const bins = latest.current;
      if (bins) drawSpectrum(ctx, bins, canvas.width, canvas.height, minDb, maxDb);
      frameId.current = requestAnimationFrame(draw);
    };

    frameId.current = requestAnimationFrame(draw);

    return () => {
      if (frameId.current !== null) cancelAnimationFrame(frameId.current);
    };
  }, [minDb, maxDb]);

  return <canvas ref={canvasRef} width={800} height={300} />;
}
```

**Разбор.**

**Ноль рендеров при потоке данных.** Пакеты складываются в `latest.current`, компонент не перерисовывается вообще. React не участвует в горячем пути — и это правильно: он не предназначен для 60 Гц обновлений бинарных данных.

**Пропуск устаревших кадров бесплатно.** Если пакетов пришло больше, чем кадров отрисовки, `latest.current` просто перезаписывается. Рисуется последний. Это ровно то поведение, которое нужно для спектра в реальном времени — старые кадры не нужны.

**`requestAnimationFrame` синхронизирован с частотой экрана** и останавливается, когда вкладка неактивна. `setInterval` продолжал бы жечь процессор в фоне.

**Три `useRef` — все по делу:** DOM-узел, изменяемые данные вне рендера, идентификатор кадра для очистки. Ни одно из этих значений не должно вызывать рендер.

**Очистка в обоих эффектах.** Без `cancelAnimationFrame` цикл продолжится после размонтирования и обратится к мёртвому canvas.

**Где здесь React вообще нужен.** Он монтирует canvas, управляет жизненным циклом подписки, реагирует на изменение `socket` и параметров отображения. Всё остальное — императивный код, и это нормально: canvas и есть императивная система.

**Что если нужно показывать метрики.** Например, частоту пакетов в секунду. Тогда — отдельное состояние, обновляемое **раз в секунду**, а не на каждый пакет:

```tsx
const packetCount = useRef(0);
const [rate, setRate] = useState(0);

useEffect(() => {
  const id = setInterval(() => {
    setRate(packetCount.current);
    packetCount.current = 0;
  }, 1000);
  return () => clearInterval(id);
}, []);
```
Счётчик в ref, публикация в состояние по таймеру. Один рендер в секунду вместо шестидесяти.

Это общий приём: **высокочастотные данные держи в ref, в состояние выноси агрегаты с нужной частотой обновления.**

---

# Часть 3. Домашка

**1.** Что не так и как исправить?
```tsx
function Timer() {
  const [ms, setMs] = useState(0);
  let id: number;
  useEffect(() => {
    id = window.setInterval(() => setMs(m => m + 10), 10);
    return () => clearInterval(id);
  }, []);
}
```

**2.** Напиши `usePrevious<T>` и покажи на нём, как отследить направление изменения числа (вырос/упал).

**3.** Определи, какие из этих `useMemo` полезны, а какие вредны. Обоснуй каждый:
```tsx
const total = useMemo(() => a + b, [a, b]);
const label = useMemo(() => `${size} точек`, [size]);
const table = useMemo(() => buildWindowTable(size), [size]);
const style = useMemo(() => ({ width: `${w}px` }), [w]);
const filtered = useMemo(() => items.filter(i => i.on), [items]);
```
Для последнего — при каком размере `items` мемоизация начинает окупаться? Измерь.

**4.** Собери список из 1000 строк с `React.memo` на строке. Сначала передай `onSelect` без `useCallback` — открой профайлер, посмотри, сколько строк перерисовывается при клике. Затем добавь `useCallback`. Зафиксируй разницу в числах.

**5.** Реализуй хук `useThrottledState<T>(initial: T, ms: number)` — возвращает `[value, setValue]`, но значение обновляется не чаще раза в `ms`. Внутри — ref для последнего значения и таймер.

**6.** Приём с ref для обхода stale closure. Реализуй `useEventCallback` — хук, возвращающий стабильную функцию, которая всегда вызывает актуальную версию коллбэка:
```tsx
const onTick = useEventCallback(() => process(config));
useEffect(() => {
  const id = setInterval(onTick, 100);
  return () => clearInterval(id);
}, [onTick]);          // onTick стабилен, интервал не пересоздаётся
```

**7.** Опускание состояния. Дан компонент, где ввод в поле поиска перерисовывает тяжёлый график. Не используя `memo`, устрани лишние рендеры двумя способами — вынесением состояния вниз и композицией через children.

**8.** Объясни, почему это не работает, и что здесь должно быть вместо ref:
```tsx
function Counter() {
  const count = useRef(0);
  return <button onClick={() => count.current++}>{count.current}</button>;
}
```
