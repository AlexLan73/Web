# Урок 25. `useReducer` + discriminated union

Кульминация блока: размеченное объединение из урока 08 применяется дважды — к состоянию и к действиям. Получается конечный автомат, полностью проверяемый компилятором.

---

# Часть 1. Теория

## 25.1 Механика

```tsx
const [state, dispatch] = useReducer(reducer, initialState);
```

`reducer` — **чистая функция** `(state, action) => newState`. Никаких запросов, таймеров, мутаций, случайных чисел.

```tsx
function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'increment': return { ...state, count: state.count + 1 };
    default: return state;
  }
}
```

`dispatch(action)` ставит действие в очередь. Как и `setState`, применяется не сразу, батчится, вызывает рендер.

**`dispatch` стабилен** между рендерами — его можно класть в зависимости эффектов и в props мемоизированных компонентов без `useCallback`. Одно это часто оправдывает переход с `useState`.

**Ленивая инициализация:**
```tsx
const [state, dispatch] = useReducer(reducer, initialArg, init);
```
`init(initialArg)` вызовется один раз. Полезно для восстановления из хранилища.

## 25.2 Когда брать вместо `useState`

**Признаки:**
- несколько полей состояния меняются вместе по одному событию
- следующее состояние сложно зависит от предыдущего
- одно и то же изменение вызывается из разных мест
- в компоненте больше трёх-четырёх `useState`
- есть недопустимые комбинации, которые надо запретить
- логику хочется протестировать без React

**Признаки, что `useState` достаточно:** одно-два независимых значения, изменения тривиальные.

**Главный выигрыш** — не сокращение кода, а **вынос логики переходов из компонента**. Редьюсер — обычная функция, тестируется вызовом, читается целиком, не зависит от React.

## 25.3 Типизация действий

```tsx
type Action =
  | { type: 'setSize'; size: FftSize }
  | { type: 'setWindow'; window: WindowFn }
  | { type: 'setOverlap'; overlap: number }
  | { type: 'reset' }
  | { type: 'undo' };
```

Размеченное объединение. В каждой ветке `switch` доступны только поля этого действия — `action.size` в ветке `'reset'` не скомпилируется.

**`assertNever` в `default`** (урок 07) делает проверку исчерпывающей:
```tsx
function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'setSize':   return { ...state, size: action.size };
    case 'setWindow': return { ...state, window: action.window };
    case 'reset':     return initialState;
    default:          return assertNever(action);
  }
}
```
Добавил действие — компилятор показал незакрытую ветку.

**Именование.** Два подхода:
- команды: `'setSize'`, `'reset'` — что сделать
- события: `'sizeChanged'`, `'runRequested'` — что произошло

Второй лучше для сложных автоматов: одно событие может менять несколько полей, и редьюсер решает как. Первый проще для простых случаев.

## 25.4 Автомат: состояние тоже union

Самая мощная форма. Состояние — размеченное объединение, и редьюсер обрабатывает пару «состояние + действие»:

```tsx
type State =
  | { status: 'idle'; config: FftConfig }
  | { status: 'running'; config: FftConfig; progress: number }
  | { status: 'done'; config: FftConfig; bins: Float32Array }
  | { status: 'failed'; config: FftConfig; reason: string };

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'start':
      if (state.status === 'running') return state;      // уже идёт — игнор
      return { status: 'running', config: state.config, progress: 0 };

    case 'progress':
      if (state.status !== 'running') return state;      // не из того состояния
      return { ...state, progress: action.value };

    case 'finish':
      if (state.status !== 'running') return state;
      return { status: 'done', config: state.config, bins: action.bins };

    case 'cancel':
      return { status: 'idle', config: state.config };
  }
}
```

**Ключевой момент — проверки на текущее состояние.** Действие `'progress'` осмысленно только в `'running'`; в остальных случаях возвращаем состояние без изменений. Это защита от событий, пришедших не вовремя: отменённый запрос долетел, пользователь дважды нажал кнопку, пакет пришёл после отключения.

Так формулируется таблица переходов конечного автомата. Недопустимый переход — это `return state`, а не исключение и не порча данных.

Тебе это должно быть знакомо: то же самое, что автомат протокола в embedded, где на неожиданное событие в данном состоянии реакция — игнорировать.

## 25.5 Типизация `dispatch` в props

```tsx
type Props = {
  state: State;
  dispatch: React.Dispatch<Action>;
};
```

`React.Dispatch<Action>` — это `(action: Action) => void`.

**Передавать ли `dispatch` вниз.** Два подхода:

```tsx
// 1. dispatch напрямую — меньше кода, но ребёнок знает про действия
<ConfigEditor state={state} dispatch={dispatch} />

// 2. конкретные коллбэки — ребёнок ничего не знает про редьюсер
<ConfigEditor
  value={state.config}
  onSizeChange={size => dispatch({ type: 'setSize', size })}
/>
```

Второй правильнее архитектурно: компонент остаётся переиспользуемым и не связан с конкретным автоматом. Первый удобнее для глубоко вложенных компонентов внутри одной фичи.

## 25.6 Побочные эффекты

**Редьюсер обязан быть чистым.** Запросы, таймеры, запись в хранилище — снаружи.

Три места, где им жить:

**1. В обработчике** — если эффект следствие действия пользователя:
```tsx
const handleRun = async () => {
  dispatch({ type: 'start' });
  try {
    const bins = await compute(state.config);
    dispatch({ type: 'finish', bins });
  } catch (e) {
    dispatch({ type: 'failed', reason: String(e) });
  }
};
```

**2. В эффекте с зависимостью от состояния** — если эффект следствие того, что система в определённом состоянии:
```tsx
useEffect(() => {
  if (state.status !== 'running') return;
  const ac = new AbortController();
  compute(state.config, ac.signal)
    .then(bins => dispatch({ type: 'finish', bins }))
    .catch(e => { if (!ac.signal.aborted) dispatch({ type: 'failed', reason: String(e) }); });
  return () => ac.abort();
}, [state.status, state.config]);
```

Второй вариант декларативнее: «когда мы в состоянии `running` — должен идти расчёт». Отмена при выходе из состояния получается сама. Критерий выбора — тот же, что в уроке 19: эффект от действия или от состояния.

**3. В обёртке над `dispatch`** — если эффекты сложные, но их немного:
```tsx
const send = (action: Action) => {
  dispatch(action);
  if (action.type === 'save') persist(state);
};
```
Работает, но легко превращается в кашу. Для настоящей асинхронной логики берут внешние менеджеры (XState, Redux-саги) — в нашем проекте не понадобится.

## 25.7 Тестирование

Главный практический плюс редьюсера:

```ts
import { describe, test, expect } from 'vitest';

test('progress игнорируется вне running', () => {
  const idle: State = { status: 'idle', config: DEFAULT };
  const next = reducer(idle, { type: 'progress', value: 0.5 });
  expect(next).toBe(idle);              // тот же объект — изменений нет
});

test('start переводит в running', () => {
  const next = reducer({ status: 'idle', config: DEFAULT }, { type: 'start' });
  expect(next.status).toBe('running');
});
```

Ни React, ни рендера, ни моков. Чистая функция — чистые тесты. Всю таблицу переходов можно покрыть за десяток строк.

---

# Часть 2. Проработка

## Задача. Панель как конечный автомат

Переписываем `useConfig` + `useAnalysis` из урока 21 в один редьюсер. Там был подозрительный момент — вызов `setHistory` внутри апдейтера `setConfig`. Теперь он уходит.

```ts
// src/state/panel.ts
import type { FftConfig, FftSize, WindowFn } from '../types';

export type PanelState = {
  config: FftConfig;
  history: FftConfig[];
  analysis:
    | { status: 'idle' }
    | { status: 'running'; progress: number }
    | { status: 'done'; bins: Float32Array; elapsedMs: number }
    | { status: 'failed'; reason: string };
};

export type PanelAction =
  | { type: 'config/patch'; patch: Partial<FftConfig> }
  | { type: 'config/undo' }
  | { type: 'config/reset' }
  | { type: 'run/start' }
  | { type: 'run/progress'; value: number }
  | { type: 'run/finish'; bins: Float32Array; elapsedMs: number }
  | { type: 'run/fail'; reason: string }
  | { type: 'run/cancel' };

export const DEFAULT_CONFIG: FftConfig = {
  size: 1024, window: 'hann', overlap: 0.5,
};

export const initialState: PanelState = {
  config: DEFAULT_CONFIG,
  history: [],
  analysis: { status: 'idle' },
};

const MAX_HISTORY = 10;

export function panelReducer(state: PanelState, action: PanelAction): PanelState {
  switch (action.type) {
    case 'config/patch': {
      // во время расчёта параметры не меняем
      if (state.analysis.status === 'running') return state;
      return {
        ...state,
        config: { ...state.config, ...action.patch },
        history: [...state.history, state.config].slice(-MAX_HISTORY),
      };
    }

    case 'config/undo': {
      const prev = state.history.at(-1);
      if (!prev || state.analysis.status === 'running') return state;
      return {
        ...state,
        config: prev,
        history: state.history.slice(0, -1),
      };
    }

    case 'config/reset':
      if (state.analysis.status === 'running') return state;
      return { ...state, config: DEFAULT_CONFIG, history: [] };

    case 'run/start':
      if (state.analysis.status === 'running') return state;
      return { ...state, analysis: { status: 'running', progress: 0 } };

    case 'run/progress':
      if (state.analysis.status !== 'running') return state;
      return { ...state, analysis: { status: 'running', progress: action.value } };

    case 'run/finish':
      if (state.analysis.status !== 'running') return state;
      return {
        ...state,
        analysis: {
          status: 'done',
          bins: action.bins,
          elapsedMs: action.elapsedMs,
        },
      };

    case 'run/fail':
      if (state.analysis.status !== 'running') return state;
      return { ...state, analysis: { status: 'failed', reason: action.reason } };

    case 'run/cancel':
      return { ...state, analysis: { status: 'idle' } };

    default:
      return assertNever(action);
  }
}
```

**Разбор.**

**Вся логика в одном месте.** Правило «во время расчёта параметры не меняются» раньше жило в props (`disabled={isBusy}`), то есть в разметке. Теперь оно в редьюсере и работает независимо от UI. Разметка всё равно ставит `disabled` — но это уже подсказка пользователю, а не защита.

**История обновляется атомарно с конфигом.** Проблема из урока 21 ушла: одно действие — одно изменение состояния, никаких вложенных сеттеров.

**Проверки состояния перед каждым переходом.** `run/progress` вне `running` — игнор. Это защита от долетевших событий отменённого расчёта.

**Префиксы в именах действий** (`config/`, `run/`) — соглашение из Redux. Помогает при десятках действий, видно, к какой части состояния относится.

**`.at(-1)` и `.slice(-MAX_HISTORY)`** — короче ручной индексации и не ломаются на пустом массиве.

**Хук поверх редьюсера:**
```tsx
// src/hooks/usePanel.ts
import { useReducer, useEffect, useCallback } from 'react';
import { panelReducer, initialState } from '../state/panel';
import { computeSpectrum } from '../lib/dsp';

export function usePanel() {
  const [state, dispatch] = useReducer(panelReducer, initialState);

  // эффект от СОСТОЯНИЯ: пока running — идёт расчёт
  useEffect(() => {
    if (state.analysis.status !== 'running') return;

    const ac = new AbortController();
    const t0 = performance.now();

    computeSpectrum(state.config, {
      signal: ac.signal,
      onProgress: value => dispatch({ type: 'run/progress', value }),
    })
      .then(bins => {
        if (ac.signal.aborted) return;
        dispatch({
          type: 'run/finish',
          bins,
          elapsedMs: Math.round(performance.now() - t0),
        });
      })
      .catch(e => {
        if (ac.signal.aborted) return;
        dispatch({
          type: 'run/fail',
          reason: e instanceof Error ? e.message : String(e),
        });
      });

    return () => ac.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.analysis.status]);

  const patch = useCallback(
    (p: Partial<FftConfig>) => dispatch({ type: 'config/patch', patch: p }), []);

  return { state, dispatch, patch };
}
```

**Здесь единственное место в курсе, где я глушу линтер** — и объясню почему. Эффект должен запускаться при **входе** в состояние `running`, а не при изменении `config`. Конфиг читается один раз на старте расчёта. Полная зависимость `[state.analysis.status, state.config]` перезапускала бы расчёт при каждом движении ползунка.

Честнее было бы положить конфиг в само действие:
```ts
| { type: 'run/start'; config: FftConfig }
```
и хранить его внутри состояния `running`:
```ts
| { status: 'running'; progress: number; config: FftConfig }
```
Тогда зависимость `[state.analysis]` честная, а снимок конфига зафиксирован в момент старта. **Так правильнее — сделай это в домашке.**

**Отмена работает бесплатно.** `run/cancel` меняет статус на `idle`, эффект видит изменение зависимости, вызывается очистка, `ac.abort()` останавливает расчёт. Ни одной строки специально под отмену.

**Компонент:**
```tsx
export default function App() {
  const { state, dispatch, patch } = usePanel();
  const { config, analysis, history } = state;
  const isBusy = analysis.status === 'running';

  return (
    <Layout sidebar={
      <Panel title="Параметры" actions={
        <>
          <Button onClick={() => dispatch({ type: 'config/undo' })}
                  disabled={history.length === 0 || isBusy}>Отменить</Button>
          <Button onClick={() => dispatch({ type: 'config/reset' })}
                  disabled={isBusy}>Сброс</Button>
        </>
      }>
        <ConfigEditor value={config} onChange={patch} disabled={isBusy} />
      </Panel>
    }>
      <Panel title="Результат" actions={<StatusLine analysis={analysis} />}>
        <Button onClick={() => dispatch({
          type: isBusy ? 'run/cancel' : 'run/start',
        })}>
          {isBusy ? 'Отменить' : 'Запустить'}
        </Button>
        <SpectrumCanvas bins={analysis.status === 'done' ? analysis.bins : null} />
      </Panel>
    </Layout>
  );
}
```

Компонент стал полностью декларативным: читает состояние, отправляет действия. Ни одного `useState`, ни одного `useRef`, ни одного `useEffect`.

---

# Часть 3. Домашка

**1.** Реализуй правильную версию из проработки: конфиг передаётся в `run/start` и хранится в состоянии `running`. Убери глушение линтера, проверь, что изменение параметров во время расчёта не перезапускает его.

**2.** Напиши тесты на `panelReducer` — всю таблицу переходов. Минимум: старт из idle, повторный старт игнорируется, progress вне running игнорируется, finish переводит в done, cancel из любого состояния, undo на пустой истории.

**3.** Добавь действие `'run/retry'` — повтор последнего расчёта с теми же параметрами. Что нужно хранить в состоянии? Убедись, что компилятор показал все места, требующие обновления.

**4.** Ограничь историю не количеством, а «не сохранять, если конфиг не изменился». Два одинаковых `patch` подряд не должны плодить записи.

**5.** Перепиши форму из урока 24 на `useReducer`: поля, ошибки валидации, состояние отправки. Действия: изменение поля, валидация, отправка, успех, ошибка. Состояние — union.

**6.** Реализуй `useUndoRedo<T>(reducer, initial)` — обёртка над любым редьюсером, добавляющая undo/redo. Состояние: `{ past: T[], present: T, future: T[] }`. Действия оборачиваются, добавляются `UNDO` и `REDO`.

**7.** Автомат WebSocket-соединения с переподключением: состояния `disconnected`, `connecting`, `connected`, `reconnecting` с числом попыток, `failed` после N неудач. Напиши редьюсер и эффект. Экспоненциальная задержка между попытками.

**8.** Сравнение подходов. Возьми любой компонент с четырьмя `useState` и перепиши на `useReducer`. Сравни: количество строк, количество мест, где можно ошибиться, простоту тестирования. Сформулируй свой критерий выбора.
