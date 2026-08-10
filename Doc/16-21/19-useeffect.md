# Урок 19. `useEffect` — синхронизация с внешним миром

Самый неправильно используемый хук в React. Большинство эффектов в реальном коде не нужны. Задача урока — научиться отличать те, что нужны.

---

# Часть 1. Теория

## 19.1 Что такое эффект

**`useEffect` — не «сделать что-то после рендера».** Это синхронизация React-состояния с чем-то, что живёт **вне** React.

Внешний мир — это:
- подписки: WebSocket, `addEventListener`, `IntersectionObserver`
- таймеры: `setInterval`, `setTimeout`
- императивные API браузера: canvas, `document.title`, focus, `localStorage`
- сторонние библиотеки со своим жизненным циклом
- запросы к серверу (хотя для них есть инструменты лучше)

Если во внешний мир ничего не выходит — эффект скорее всего не нужен.

```tsx
useEffect(() => {
  // подключаемся
  const socket = connect(url);

  return () => {
    // отключаемся
    socket.close();
  };
}, [url]);
```

Мысленная модель: эффект описывает, **как привести внешнюю систему в соответствие** с текущим состоянием. React вызывает его, когда состояние изменилось, и вызывает очистку, когда синхронизация больше не актуальна.

## 19.2 Механика

```tsx
useEffect(setup, deps?);
```

**Когда выполняется `setup`:**
- после монтирования — всегда
- после рендера, если хотя бы одна зависимость изменилась (`Object.is`)
- после каждого рендера, если `deps` не передан

**Когда выполняется очистка:**
- перед следующим `setup`
- при размонтировании

Порядок при изменении зависимости: очистка старого → setup нового. Не наоборот.

Эффект выполняется **после** того, как браузер отрисовал кадр. Если нужно до отрисовки (измерение размеров, чтобы избежать мигания) — `useLayoutEffect`, он синхронный и блокирует отрисовку.

**Массив зависимостей — не «когда запускать», а «от чего зависит».** Ты не выбираешь момент, ты честно перечисляешь всё, что эффект читает из области видимости компонента. React решает сам.

Врать в зависимостях — главный источник багов. Пустой массив при использовании `config` внутри = stale closure из урока 02.

## 19.3 StrictMode: двойной вызов

В разработке React вызывает `setup` → `cleanup` → `setup` при монтировании. Намеренно.

Смысл: если очистка написана неправильно, это вылезет сразу, а не в проде при первом переключении вкладки. Два подключения без закрытия, два таймера, дублирующиеся запросы — всё видно немедленно.

**Правило: эффект должен корректно переживать повторный запуск.** Если двойной вызов ломает логику — проблема в эффекте, а не в StrictMode. Отключать его не надо.

## 19.4 Когда эффект НЕ нужен

Это половина урока по важности.

**❌ Вычисление производных данных**
```tsx
const [items, setItems] = useState([]);
const [count, setCount] = useState(0);
useEffect(() => setCount(items.length), [items]);   // лишний рендер + рассинхрон

const count = items.length;                          // ✅
```

**❌ Сброс состояния при смене props**
```tsx
useEffect(() => setDraft(config), [config]);         // мигание старым значением

<Editor key={configId} config={config} />            // ✅ урок 16
```

**❌ Обработка события пользователя**
```tsx
useEffect(() => { if (submitted) send(data); }, [submitted]);   // зачем?

const handleSubmit = () => send(data);               // ✅ прямо в обработчике
```
Логика, привязанная к **действию**, живёт в обработчике. Логика, привязанная к **тому, что компонент отображается**, живёт в эффекте. Это главный критерий.

**❌ Цепочки эффектов**
```tsx
useEffect(() => { if (a) setB(...) }, [a]);
useEffect(() => { if (b) setC(...) }, [b]);          // каскад рендеров
```
Считай всё за один проход или используй `useReducer` (урок 25).

**❌ Инициализация приложения**
```tsx
useEffect(() => { initAnalytics(); }, []);           // выполнится дважды в StrictMode
```
Выноси на уровень модуля или вызывай до рендера.

Официальная статья на эту тему — «You Might Not Need an Effect» на react.dev. Прочитай целиком, она короткая и покрывает почти все случаи.

## 19.5 Когда эффект нужен

**Подписка на внешний источник:**
```tsx
useEffect(() => {
  const onResize = () => setWidth(window.innerWidth);
  window.addEventListener('resize', onResize);
  return () => window.removeEventListener('resize', onResize);
}, []);
```

**Императивный API:**
```tsx
useEffect(() => {
  const ctx = canvasRef.current?.getContext('2d');
  if (!ctx) return;
  drawSpectrum(ctx, bins);
}, [bins]);
```

**Синхронизация с браузером:**
```tsx
useEffect(() => { document.title = `${runs.length} прогонов`; }, [runs.length]);
```

**Таймер:**
```tsx
useEffect(() => {
  const id = setInterval(() => setTick(t => t + 1), 1000);
  return () => clearInterval(id);
}, []);
```
Функциональная форма `t => t + 1` позволяет обойтись пустыми зависимостями. С `setTick(tick + 1)` пришлось бы указать `[tick]`, и интервал пересоздавался бы каждую секунду.

## 19.6 Гонки при загрузке данных

Классическая проблема, о которой забывают.

```tsx
useEffect(() => {
  fetch(`/api/runs/${id}`)
    .then(r => r.json())
    .then(setData);            // ❌ гонка
}, [id]);
```

Пользователь быстро переключает `id`: 1 → 2. Запрос за первым может вернуться **после** второго, и в состоянии окажутся данные от `id=1`, хотя выбран `id=2`.

**Флаг актуальности:**
```tsx
useEffect(() => {
  let active = true;
  fetch(`/api/runs/${id}`)
    .then(r => r.json())
    .then(d => { if (active) setData(d); });
  return () => { active = false; };
}, [id]);
```

**`AbortController`** — лучше, реально отменяет запрос:
```tsx
useEffect(() => {
  const ac = new AbortController();
  fetch(url, { signal: ac.signal })
    .then(r => r.json())
    .then(setData)
    .catch(e => { if (e.name !== 'AbortError') setError(e); });
  return () => ac.abort();
}, [url]);
```

Обрати внимание на `catch`: отмена приходит как ошибка, её надо отфильтровать, иначе покажешь пользователю несуществующую проблему.

**Честный вывод:** правильная загрузка данных вручную — это гонки, отмена, кеш, повторы,状态 загрузки, инвалидация. Всё это уже написано в TanStack Query (урок 28). В проде эффекты для фетча почти не используют.

## 19.7 Зависимости

**Линтер `eslint-plugin-react-hooks`** проверяет полноту массива. Ставь обязательно — Vite-шаблон включает его по умолчанию.

Правило: **никогда не глуши предупреждение**. Если линтер требует зависимость, а добавление вызывает цикл — эффект спроектирован неправильно.

**Проблема нестабильных зависимостей.** Объекты и функции создаются заново каждый рендер:
```tsx
const options = { size: 1024 };
useEffect(() => { ... }, [options]);        // новый объект → эффект каждый рендер
```

Решения по предпочтительности:
1. **Перенести объект внутрь эффекта** — если он больше нигде не нужен
2. **Зависеть от примитивов**: `[options.size]` вместо `[options]`
3. **`useMemo` / `useCallback`** (урок 20) — последнее средство

```tsx
useEffect(() => {
  const options = { size };               // ✅ внутри
  connect(url, options);
}, [url, size]);                          // примитивы стабильны
```

## 19.8 Типизация

```tsx
useEffect(() => {
  const id = setInterval(tick, 1000);
  return () => clearInterval(id);
}, []);
```

**`setInterval` в браузере возвращает `number`, в Node — объект `Timeout`.** Если TypeScript видит типы Node, будет конфликт. Лечится либо `window.setInterval`, либо правильным `lib` в tsconfig без `@types/node` в клиентском коде.

**Функция очистки должна возвращать `void`**, не значение:
```tsx
useEffect(() => {
  return () => socket.close();          // ✅
  // return () => setActive(false);     // ⚠️ вернёт результат — обычно безобидно, но
});
```
Частая ошибка — краткая стрелка с async:
```tsx
useEffect(async () => { ... }, []);     // ❌ вернёт промис, React ждёт функцию очистки
```
Правильно:
```tsx
useEffect(() => {
  void (async () => { ... })();
}, []);
```

---

# Часть 2. Проработка

## Задача. Отрисовка спектра на canvas и стрим по WebSocket

Два канонических случая эффекта в одном компоненте.

**Canvas — императивный API:**
```tsx
// src/SpectrumCanvas.tsx
import { useEffect, useRef } from 'react';

type Props = {
  bins: Float32Array | null;
  minDb?: number;
  maxDb?: number;
};

export function SpectrumCanvas({ bins, minDb = -120, maxDb = 0 }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !bins) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const { width, height } = canvas;
    ctx.clearRect(0, 0, width, height);

    const range = maxDb - minDb;
    ctx.beginPath();
    for (let i = 0; i < bins.length; i++) {
      const db = Math.max(minDb, Math.min(maxDb, bins[i] ?? minDb));
      const x = (i / bins.length) * width;
      const y = height - ((db - minDb) / range) * height;
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.strokeStyle = '#4ade80';
    ctx.stroke();
  }, [bins, minDb, maxDb]);

  return <canvas ref={canvasRef} width={800} height={300} />;
}
```

**Почему это законный эффект:** canvas — внешняя императивная система. React не умеет её описывать декларативно, значит синхронизация вручную. Зависимости честные: перерисовываем при смене данных или диапазона.

**`bins[i] ?? minDb`** — из-за `noUncheckedIndexedAccess` (урок 12). Индексация даёт `number | undefined`, и компилятор прав: цикл мог бы выйти за границы.

**Очистка не нужна** — рисование не оставляет ресурсов. Это нормально, `return` необязателен.

**WebSocket — подписка с очисткой:**
```tsx
// src/useStream.ts
import { useEffect, useState } from 'react';

type StreamState =
  | { status: 'idle' }
  | { status: 'connecting' }
  | { status: 'open'; lastPacket: Float32Array | null }
  | { status: 'closed'; code: number };

export function useStream(url: string | null): StreamState {
  const [state, setState] = useState<StreamState>({ status: 'idle' });

  useEffect(() => {
    if (!url) {
      setState({ status: 'idle' });
      return;
    }

    setState({ status: 'connecting' });
    const socket = new WebSocket(url);

    socket.onopen = () => setState({ status: 'open', lastPacket: null });

    socket.onmessage = async (e: MessageEvent<Blob>) => {
      const buf = await e.data.arrayBuffer();
      setState({ status: 'open', lastPacket: new Float32Array(buf) });
    };

    socket.onclose = (e) => setState({ status: 'closed', code: e.code });

    return () => {
      socket.onmessage = null;      // снимаем обработчики до закрытия
      socket.close();
    };
  }, [url]);

  return state;
}
```

**Разбор.**

**Очистка обязательна.** Без `socket.close()` при каждом изменении `url` оставался бы висящий сокет. В StrictMode это вылезет сразу: увидишь два подключения в сетевой панели.

**Снятие обработчиков перед закрытием** — иначе `onclose` от закрываемого сокета выставит состояние `closed` уже после того, как новый сокет подключился.

**Зависимость `[url]`** — единственное, что эффект читает извне. Честно и стабильно, потому что примитив.

**`url: string | null`** — вместо отдельного флага «подключаться ли». Меньше состояний, невозможно рассинхронизировать.

**Это уже кастомный хук** — вынесенная логика с состоянием. Формально проходим в уроке 21, но приём естественный: если из компонента убрать эффект и состояние в отдельную функцию, начинающуюся с `use`, — получается хук.

**Использование:**
```tsx
function App() {
  const [url, setUrl] = useState<string | null>(null);
  const stream = useStream(url);

  return (
    <>
      <button onClick={() => setUrl('ws://localhost:8080/spectrum')}>
        Подключить
      </button>
      <button onClick={() => setUrl(null)}>Отключить</button>

      <StatusLine stream={stream} />
      <SpectrumCanvas bins={stream.status === 'open' ? stream.lastPacket : null} />
    </>
  );
}
```

Подключение и отключение — просто изменение состояния. Эффект сам приведёт сокет в соответствие. Это и есть декларативность применительно к внешним системам: ты описываешь желаемое, синхронизацию делает React.

---

# Часть 3. Домашка

**1.** Убери лишние эффекты, объясни каждый:
```tsx
const [runs, setRuns] = useState<Run[]>([]);
const [count, setCount] = useState(0);
const [fastest, setFastest] = useState<Run | null>(null);
const [isEmpty, setIsEmpty] = useState(true);

useEffect(() => setCount(runs.length), [runs]);
useEffect(() => setIsEmpty(runs.length === 0), [runs]);
useEffect(() => {
  setFastest(runs.reduce((a, b) => a.elapsedMs < b.elapsedMs ? a : b, runs[0]));
}, [runs]);
```

**2.** Почему счётчик останавливается на 1? Почини двумя способами.
```tsx
const [n, setN] = useState(0);
useEffect(() => {
  const id = setInterval(() => setN(n + 1), 1000);
  return () => clearInterval(id);
}, []);
```

**3.** Напиши хук `useDebounced<T>(value: T, ms: number): T` — возвращает значение с задержкой, сбрасывая таймер при каждом изменении. Проверь на поле поиска.

**4.** Воспроизведи гонку: сделай два запроса с искусственной задержкой (первый медленнее второго), быстро переключи id. Покажи неправильные данные, затем почини через флаг и через `AbortController`.

**5.** Хук `useEventListener` с корректной типизацией:
```tsx
useEventListener('keydown', e => { e.key });      // e: KeyboardEvent
useEventListener('resize', e => { });              // e: UIEvent
```
Подсказка: `WindowEventMap` из lib.dom.

**6.** Почему в StrictMode этот код создаёт две записи, и как исправить?
```tsx
useEffect(() => {
  setRuns(rs => [...rs, createRun()]);
}, []);
```

**7.** `useLayoutEffect`. Собери тултип, который позиционируется по размеру своего содержимого. Сделай на `useEffect` — увидишь мигание. Переделай на `useLayoutEffect` — мигание исчезнет. Объясни разницу в моменте выполнения.

**8.** Разбор архитектуры. В `SpectrumCanvas` перерисовка идёт в эффекте. Что произойдёт при 60 пакетах в секунду от WebSocket? Предложи решение — подсказка: `requestAnimationFrame` и `useRef` вместо состояния.
