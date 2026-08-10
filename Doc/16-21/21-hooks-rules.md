# Урок 21. Правила хуков, кастомные хуки

Закрытие блока React. Правила ты уже понимаешь механически — в уроке 02 мы написали `useState` на массиве с курсором. Здесь — следствия и главный практический навык блока: вынос логики в свои хуки.

---

# Часть 1. Теория

## 21.1 Два правила

**1. Хуки вызываются только на верхнем уровне.** Не в условиях, не в циклах, не во вложенных функциях, не после раннего `return`.

**2. Хуки вызываются только из компонентов и других хуков.** Не из обычных функций, не из обработчиков, не из классов.

Причина первого — из урока 02: состояние хранится в массиве, привязка идёт по порядку вызова. Пропустил вызов — все последующие индексы съехали.

```tsx
// ❌ при isReady === false все последующие хуки смещаются
if (isReady) {
  const [data, setData] = useState(null);
}

// ❌ ранний return перед хуком
if (!items.length) return <Empty />;
const [sort, setSort] = useState('name');

// ✅ хуки первыми, условия после
const [sort, setSort] = useState('name');
if (!items.length) return <Empty />;
```

**Условная логика внутри хука — можно:**
```tsx
useEffect(() => {
  if (!url) return;             // ✅ условие внутри
  connect(url);
}, [url]);
```

**Переменное число хуков — нельзя.** Если нужно состояние для динамического списка — это состояние-массив в родителе или отдельный компонент на элемент.

Линтер `eslint-plugin-react-hooks` ловит оба правила. Он включён в шаблоне Vite; проверь, что работает.

## 21.2 Кастомный хук

Функция, имя которой начинается с `use` и которая вызывает другие хуки.

```tsx
function useToggle(initial = false) {
  const [on, setOn] = useState(initial);
  const toggle = useCallback(() => setOn(o => !o), []);
  return [on, toggle] as const;
}
```

Это **не** механизм переиспользования состояния — каждый вызов создаёт своё, независимое. Два компонента с `useToggle()` не связаны. Переиспользуется **логика**, не данные.

**Именование обязательно с `use`** — по нему линтер понимает, что внутри могут быть хуки, и применяет правила. Функция `getToggle` с `useState` внутри не будет проверена и сломается.

## 21.3 Что выносить

**Признаки, что пора выделить хук:**
- один и тот же набор `useState` + `useEffect` встречается в двух местах
- компонент содержит логику, не связанную с его отрисовкой
- в компоненте больше пяти хуков подряд
- логику хочется протестировать отдельно от разметки

**Хороший хук:**
- решает одну задачу
- имеет понятное имя-глагол или имя-существительное: `useDebounced`, `useStream`, `useLocalStorage`
- скрывает эффекты и очистку
- возвращает минимум необходимого

**Возврат.** Два значения — кортеж (как `useState`), больше — объект:
```tsx
return [value, setValue] as const;                 // кортеж, имена выбирает вызывающий
return { data, error, isLoading, refetch };        // объект, имена фиксированы
```
`as const` обязателен для кортежа — иначе выведется `(T | ((v: T) => void))[]`, массив union вместо пары.

## 21.4 Композиция хуков

Хуки складываются, и это основной способ строить сложную логику:

```tsx
function useAnalysisStream(url: string | null, config: FftConfig) {
  const socket = useSocket(url);
  const packets = usePacketBuffer(socket);
  const spectrum = useSpectrum(packets, config);
  const rate = useRate(packets);

  return { spectrum, rate, connected: socket !== null };
}
```

Каждый уровень отвечает за своё, тестируется отдельно, переиспользуется независимо. Это аналог разбиения на функции в обычном коде — просто с состоянием и жизненным циклом внутри.

## 21.5 Типизация

**Дженерик-хук:**
```tsx
function useLocalStorage<T>(key: string, initial: T) {
  const [value, setValue] = useState<T>(() => {
    try {
      const raw = localStorage.getItem(key);
      return raw ? (JSON.parse(raw) as T) : initial;
    } catch {
      return initial;
    }
  });

  useEffect(() => {
    localStorage.setItem(key, JSON.stringify(value));
  }, [key, value]);

  return [value, setValue] as const;
}
```
Тип выводится из начального значения — аннотация при вызове не нужна.

Заметь `useState(() => ...)` — ленивая инициализация из урока 15. Чтение из хранилища не должно происходить на каждом рендере.

**Перегрузки для необязательного начального значения:**
```tsx
function useRefValue<T>(initial: T): MutableRefObject<T>;
function useRefValue<T>(): MutableRefObject<T | undefined>;
function useRefValue<T>(initial?: T) { return useRef(initial); }
```

**Возврат размеченного объединения** — лучший способ типизировать асинхронный хук:
```tsx
type Async<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };

function useAsync<T>(fn: () => Promise<T>, deps: unknown[]): Async<T> { ... }
```
Потребитель обязан разобрать состояние, обратиться к `data` в ветке загрузки не сможет. Ровно то, что делает TanStack Query.

## 21.6 Ловушки

**Функция в зависимостях.** Хук возвращает функцию, она попадает в `deps` эффекта у потребителя — и если функция нестабильна, эффект зацикливается:
```tsx
function useApi() {
  const load = () => fetch(url);          // ❌ новая каждый рендер
  return { load };
}

// у потребителя
useEffect(() => { load(); }, [load]);     // бесконечный цикл
```
Оборачивай возвращаемые функции в `useCallback` — это единственное место, где он нужен почти всегда.

**Хук, зависящий от порядка вызова.** Если результат хука зависит от того, вызвали ли его до или после другого — архитектура сломана.

**Слишком общий хук.** `useEverything(config)`, делающий десять вещей, не переиспользуется никогда. Дели.

**Хук вместо функции.** Если логика не использует состояние, эффекты и контекст — это обычная функция, не хук. `useFormatBytes` без хуков внутри — просто `formatBytes`.

## 21.7 Тестирование

Хуки тестируются через `@testing-library/react`:
```tsx
import { renderHook, act } from '@testing-library/react';

test('useToggle переключается', () => {
  const { result } = renderHook(() => useToggle(false));
  expect(result.current[0]).toBe(false);
  act(() => result.current[1]());
  expect(result.current[0]).toBe(true);
});
```
`act` оборачивает изменения состояния, чтобы React успел применить рендер. Подробнее в уроке 32.

Возможность тестировать логику без разметки — веский аргумент за вынос в хук.

---

# Часть 2. Проработка

## Задача. Вынос логики панели в хуки

Возьмём `App.tsx`, накопивший к этому моменту состояние, эффекты и обработчики, и разложим.

**Хук 1. Конфигурация с историей.**
```tsx
// src/hooks/useConfig.ts
import { useState, useCallback } from 'react';
import type { FftConfig } from '../types';

export const DEFAULT_CONFIG: FftConfig = {
  size: 1024, window: 'hann', overlap: 0.5,
};

export function useConfig(initial: FftConfig = DEFAULT_CONFIG) {
  const [config, setConfig] = useState(initial);
  const [history, setHistory] = useState<FftConfig[]>([]);

  const patch = useCallback((p: Partial<FftConfig>) => {
    setConfig(c => {
      setHistory(h => [...h.slice(-9), c]);      // храним последние 10
      return { ...c, ...p };
    });
  }, []);

  const undo = useCallback(() => {
    setHistory(h => {
      const prev = h.at(-1);
      if (prev) setConfig(prev);
      return h.slice(0, -1);
    });
  }, []);

  const reset = useCallback(() => {
    setConfig(initial);
    setHistory([]);
  }, [initial]);

  return { config, patch, undo, reset, canUndo: history.length > 0 };
}
```

Возврат объектом — значений пять, кортеж был бы нечитаем. Все функции в `useCallback`, чтобы их можно было безопасно класть в зависимости у потребителя.

Обрати внимание на `setConfig(c => { setHistory(...); return ... })` — вызов одного сеттера внутри апдейтера другого. Работает, но на грани: апдейтер должен быть чистым. Честнее — `useReducer` с обоими полями в одном состоянии, чем мы и займёмся в уроке 25.

**Хук 2. Прогон анализа.**
```tsx
// src/hooks/useAnalysis.ts
import { useState, useRef, useCallback, useEffect } from 'react';
import type { Analysis, FftConfig } from '../types';

export function useAnalysis(config: FftConfig) {
  const [analysis, setAnalysis] = useState<Analysis>({ status: 'idle' });
  const abortRef = useRef<AbortController | null>(null);
  const configRef = useRef(config);
  configRef.current = config;                    // всегда актуальный

  const run = useCallback(async () => {
    abortRef.current?.abort();
    const ac = new AbortController();
    abortRef.current = ac;

    setAnalysis({ status: 'running', progress: 0 });
    const t0 = performance.now();

    try {
      const bins = await computeSpectrum(configRef.current, {
        signal: ac.signal,
        onProgress: p => setAnalysis({ status: 'running', progress: p }),
      });
      if (ac.signal.aborted) return;
      setAnalysis({
        status: 'done',
        bins,
        elapsedMs: Math.round(performance.now() - t0),
      });
    } catch (e) {
      if (ac.signal.aborted) return;
      setAnalysis({
        status: 'failed',
        reason: e instanceof Error ? e.message : String(e),
      });
    }
  }, []);

  const cancel = useCallback(() => {
    abortRef.current?.abort();
    setAnalysis({ status: 'idle' });
  }, []);

  // отмена при размонтировании
  useEffect(() => () => abortRef.current?.abort(), []);

  return { analysis, run, cancel, isBusy: analysis.status === 'running' };
}
```

**Разбор.**

**`configRef` вместо зависимости.** Если бы `run` зависел от `config`, он бы менялся при каждом движении ползунка — и все эффекты потребителя пересрабатывали бы. Ref держит актуальное значение, `run` остаётся стабильным. Приём из урока 20.

**`AbortController` в ref.** Изменяемое значение, не влияющее на отрисовку. Позволяет отменить предыдущий прогон при запуске нового — защита от гонки из урока 19.

**Проверка `signal.aborted` после `await`.** Обязательна: между началом ожидания и его концом компонент мог размонтироваться или запуститься новый прогон. Без проверки — обновление состояния мёртвого компонента и перезапись свежего результата старым.

**Очистка при размонтировании** — `useEffect(() => () => ..., [])`. Стрелка, возвращающая стрелку: setup ничего не делает, cleanup отменяет.

**`e instanceof Error`** — `catch` даёт `unknown` (урок 07), бросить могли что угодно.

**Хук 3. Сохранённые прогоны с персистентностью.**
```tsx
// src/hooks/useRuns.ts
export function useRuns() {
  const [runs, setRuns] = useLocalStorage<Run[]>('dsp:runs', []);

  const add = useCallback((run: Omit<Run, 'id'>) => {
    setRuns(rs => [...rs, { ...run, id: crypto.randomUUID() }]);
  }, [setRuns]);

  const remove = useCallback((id: string) => {
    setRuns(rs => rs.filter(r => r.id !== id));
  }, [setRuns]);

  const clear = useCallback(() => setRuns([]), [setRuns]);

  return { runs, add, remove, clear };
}
```

Композиция: `useRuns` построен поверх `useLocalStorage` из 21.5. Персистентность спрятана — потребитель про неё не знает.

`Omit<Run, 'id'>` — id генерируется внутри, снаружи его передавать не нужно и нельзя. Утилита из урока 10 выражает это в типе.

**Что осталось в компоненте:**
```tsx
export default function App() {
  const { config, patch, undo, reset, canUndo } = useConfig();
  const { analysis, run, cancel, isBusy } = useAnalysis(config);
  const { runs, add, remove } = useRuns();

  const handleSave = () => {
    if (analysis.status !== 'done') return;
    add({
      label: `FFT ${config.size} / ${config.window}`,
      config,
      peakHz: findPeak(analysis.bins),
      elapsedMs: analysis.elapsedMs,
    });
  };

  return (
    <Layout sidebar={
      <Panel title="Параметры" actions={
        <>
          <Button onClick={undo} disabled={!canUndo}>Отменить</Button>
          <Button onClick={reset}>Сброс</Button>
        </>
      }>
        <ConfigEditor value={config} onChange={patch} disabled={isBusy} />
      </Panel>
    }>
      <Panel title="Результат" actions={<StatusLine analysis={analysis} />}>
        <Button onClick={isBusy ? cancel : run}>
          {isBusy ? 'Отменить' : 'Запустить'}
        </Button>
        <Button onClick={handleSave} disabled={analysis.status !== 'done'}>
          Сохранить
        </Button>
        <SpectrumCanvas bins={analysis.status === 'done' ? analysis.bins : null} />
      </Panel>

      <Panel title={`Прогоны (${runs.length})`}>
        <RunList runs={runs} onDelete={remove} />
      </Panel>
    </Layout>
  );
}
```

Компонент стал чистой сборкой: три хука, один обработчик, разметка. Ни одного `useEffect`, ни одного `useRef` — вся механика внутри хуков.

**Проверь себя.** `handleSave` обращается к `analysis.bins` — компилируется только внутри проверки `analysis.status !== 'done'` (ранний возврат). Размеченное объединение из урока 08 продолжает работать через все слои.

---

# Часть 3. Домашка

**1.** Найди все нарушения правил хуков и исправь:
```tsx
function Panel({ items, showChart }: Props) {
  if (items.length === 0) return <Empty />;
  const [sort, setSort] = useState('name');
  items.forEach(i => { const [on] = useState(false); });
  if (showChart) useEffect(() => draw(), [items]);
  const handleClick = () => { const [x] = useState(0); };
}
```

**2.** Напиши `useMediaQuery(query: string): boolean` — реактивно отслеживает CSS-медиазапрос через `matchMedia`. Не забудь отписку и начальное значение без мигания.

**3.** `useInterval(callback, delay: number | null)` — таймер, где `null` останавливает. Коллбэк должен всегда быть актуальным без пересоздания интервала. Подсказка: приём с ref из урока 20.

**4.** Собери `useAsync<T>` из 21.5 полностью: принимает функцию, возвращает размеченное объединение, отменяет предыдущий запрос при повторном вызове, не обновляет состояние после размонтирования.

**5.** Композиция. Построй `useFilteredRuns(runs, query)` поверх `useDebounced` из урока 19 — фильтрация с задержкой ввода. Затем добавь сортировку, не ломая существующий интерфейс хука.

**6.** Почему у потребителя бесконечный цикл? Найди причину и исправь в хуке, а не у потребителя:
```tsx
function useApi(url: string) {
  const [data, setData] = useState(null);
  const load = () => fetch(url).then(r => r.json()).then(setData);
  return { data, load };
}
// потребитель
const { data, load } = useApi('/api/runs');
useEffect(() => { load(); }, [load]);
```

**7.** Напиши тесты для `useToggle` и `useDebounced` через `renderHook`. Для второго понадобятся фейковые таймеры Vitest — разберись с `vi.useFakeTimers()`.

**8.** Архитектурное. Разбей `useConfig` из проработки так, чтобы история изменений стала отдельным переиспользуемым хуком `useHistory<T>(value, setValue)`, работающим с любым состоянием. Объясни, что усложнилось и что упростилось.
