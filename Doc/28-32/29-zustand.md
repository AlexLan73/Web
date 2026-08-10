# Урок 29. Zustand — клиентское состояние

Когда состояние нужно в нескольких несвязанных местах, а поднимать его до корня — значит перерисовывать полприложения на каждое изменение.

---

# Часть 1. Теория

## 29.1 Когда нужен внешний стор

Порядок из урока 17 остаётся в силе: сначала локальное состояние, потом подъём, потом композиция, и только потом стор.

**Признаки, что пора:**
- состояние нужно в компонентах, у которых нет общего предка кроме корня
- подъём до корня вызывает перерисовку всего дерева
- Context перерисовывает всех потребителей при изменении любого поля
- состояние переживает размонтирование компонентов

**Признаки, что не надо:**
- данные приходят с сервера → Query (урок 28)
- состояние живёт в URL → роутер (урок 27)
- нужно в одном поддереве → подъём или композиция

**Про Context.** Он решает передачу, но не оптимизацию: любое изменение значения перерисовывает **всех** потребителей, даже читающих одно неизменившееся поле. Для темы и локали это не важно — они меняются раз в сессию. Для часто меняющегося состояния — проблема.

Zustand решает именно её: подписка на срез, а не на всё.

## 29.2 Основы

```bash
npm i zustand
```

```ts
// src/store/settings.ts
import { create } from 'zustand';

type SettingsState = {
  theme: 'light' | 'dark';
  units: 'hz' | 'khz';
  precision: number;

  setTheme: (theme: 'light' | 'dark') => void;
  setUnits: (units: 'hz' | 'khz') => void;
  reset: () => void;
};

const initial = { theme: 'dark', units: 'hz', precision: 2 } as const;

export const useSettings = create<SettingsState>()((set) => ({
  ...initial,
  setTheme: (theme) => set({ theme }),
  setUnits: (units) => set({ units }),
  reset: () => set(initial),
}));
```

Использование — как хук, без провайдера:
```tsx
const theme = useSettings(s => s.theme);
const setTheme = useSettings(s => s.setTheme);
```

**Двойные скобки `create<T>()(...)`** — не опечатка. Такая форма нужна для корректного вывода типов при использовании middleware. Пиши всегда так.

## 29.3 Селекторы — главное правило

**Всегда подписывайся на минимальный срез.**

```tsx
const store = useSettings();                    // ❌ рендер на любое изменение
const theme = useSettings(s => s.theme);        // ✅ только при смене темы
```

Селектор вызывается при каждом изменении стора, результат сравнивается через `Object.is`. Совпал — рендера нет.

**Ловушка с объектами:**
```tsx
const { theme, units } = useSettings(s => ({ theme: s.theme, units: s.units }));
// ❌ новый объект каждый раз → рендер всегда
```

Два решения:
```tsx
// 1. Отдельные подписки — проще и обычно лучше
const theme = useSettings(s => s.theme);
const units = useSettings(s => s.units);

// 2. useShallow — поверхностное сравнение
import { useShallow } from 'zustand/react/shallow';
const { theme, units } = useSettings(useShallow(s => ({ theme: s.theme, units: s.units })));
```

**Действия стабильны** — их можно брать без опасений, ссылка не меняется:
```tsx
const setTheme = useSettings(s => s.setTheme);   // никогда не вызовет рендер
```

## 29.4 Обновление состояния

```ts
set({ theme: 'light' });                          // частичное слияние
set(s => ({ count: s.count + 1 }));               // от предыдущего
set({ a: 1 }, true);                              // ЗАМЕНА всего состояния
```

`set` по умолчанию делает поверхностное слияние — как `setState` в классах React. Вложенные объекты заменяются целиком:
```ts
set(s => ({ view: { ...s.view, zoom: 2 } }));     // распаковка обязательна
```

Глубокие структуры — `immer`:
```ts
import { immer } from 'zustand/middleware/immer';

export const useStore = create<State>()(immer((set) => ({
  view: { zoom: 1, range: { from: 0, to: 22050 } },
  setZoom: (zoom) => set(s => { s.view.zoom = zoom; }),      // «мутация» безопасна
})));
```
Immer перехватывает мутации прокси и строит новый объект. Внутри `set` можно писать императивно.

## 29.5 Middleware

**Персистентность:**
```ts
import { persist, createJSONStorage } from 'zustand/middleware';

export const useSettings = create<SettingsState>()(
  persist(
    (set) => ({ ...initial, setTheme: (theme) => set({ theme }) }),
    {
      name: 'dsp:settings',
      storage: createJSONStorage(() => localStorage),
      partialize: (s) => ({ theme: s.theme, units: s.units }),   // без функций
      version: 1,
      migrate: (persisted, version) => {
        if (version === 0) return { ...(persisted as object), units: 'hz' };
        return persisted as SettingsState;
      },
    }
  )
);
```

**`partialize` обязателен** — иначе в хранилище попытаются сохраниться функции-действия, что даст мусор.

**`version` + `migrate`** — структура состояния меняется, а у пользователя в браузере лежит старая. Без миграции приложение упадёт на несуществующем поле.

**Devtools:**
```ts
import { devtools } from 'zustand/middleware';
create<State>()(devtools(persist(..., { name: 'settings' })));
```
Порядок обёрток важен: `devtools` снаружи.

## 29.6 Организация

**Несколько маленьких сторов лучше одного большого.** Стор на предметную область: настройки, вид, подключение к прибору. Меньше связность, проще тестировать, меньше лишних рендеров.

**Слайсы**, если стор всё же один:
```ts
type ViewSlice = { zoom: number; setZoom: (z: number) => void };
type SelectionSlice = { selected: string[]; toggle: (id: string) => void };

const createViewSlice: StateCreator<ViewSlice & SelectionSlice, [], [], ViewSlice> =
  (set) => ({ zoom: 1, setZoom: (zoom) => set({ zoom }) });

export const useStore = create<ViewSlice & SelectionSlice>()((...a) => ({
  ...createViewSlice(...a),
  ...createSelectionSlice(...a),
}));
```

**Доступ вне React** — часто недооценённая возможность:
```ts
useSettings.getState().theme;                       // прочитать
useSettings.setState({ theme: 'light' });           // записать
useSettings.subscribe(s => console.log(s.theme));   // подписаться
```
Работает в воркерах-обёртках, в обработчиках сокета, в императивном коде canvas. Не нужен ни хук, ни компонент.

## 29.7 Производные значения

```ts
// ❌ хранить производное — рассинхрон (урок 17)
type State = { items: Item[]; count: number };

// ✅ считать в селекторе
const count = useStore(s => s.items.length);
```

Селектор с вычислением — нормально, но помни про сравнение по ссылке:
```tsx
const visible = useStore(s => s.items.filter(i => i.on));   // ❌ новый массив всегда
const visible = useStore(useShallow(s => s.items.filter(i => i.on)));  // ✅
```

Для дорогих вычислений — селектор возвращает исходные данные, `useMemo` считает:
```tsx
const items = useStore(s => s.items);
const visible = useMemo(() => items.filter(i => i.on), [items]);
```

---

# Часть 2. Проработка

## Задача. Настройки отображения и выделение

Два стора для `dsp-panel`, каждый решает свою задачу.

**Стор 1. Настройки — глобальные, редко меняются, переживают перезагрузку.**

```ts
// src/store/settings.ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

export type Theme = 'light' | 'dark';
export type FreqUnit = 'hz' | 'khz';

type State = {
  theme: Theme;
  freqUnit: FreqUnit;
  dbRange: { min: number; max: number };
  showGrid: boolean;
  expertMode: boolean;
};

type Actions = {
  setTheme: (theme: Theme) => void;
  setFreqUnit: (unit: FreqUnit) => void;
  setDbRange: (range: Partial<State['dbRange']>) => void;
  toggleGrid: () => void;
  toggleExpert: () => void;
  reset: () => void;
};

const initial: State = {
  theme: 'dark',
  freqUnit: 'hz',
  dbRange: { min: -120, max: 0 },
  showGrid: true,
  expertMode: false,
};

export const useSettings = create<State & Actions>()(
  persist(
    (set) => ({
      ...initial,
      setTheme: (theme) => set({ theme }),
      setFreqUnit: (freqUnit) => set({ freqUnit }),
      setDbRange: (range) => set(s => ({ dbRange: { ...s.dbRange, ...range } })),
      toggleGrid: () => set(s => ({ showGrid: !s.showGrid })),
      toggleExpert: () => set(s => ({ expertMode: !s.expertMode })),
      reset: () => set(initial),
    }),
    {
      name: 'dsp:settings',
      storage: createJSONStorage(() => localStorage),
      partialize: ({ theme, freqUnit, dbRange, showGrid, expertMode }) =>
        ({ theme, freqUnit, dbRange, showGrid, expertMode }),
      version: 1,
    }
  )
);
```

`partialize` перечисляет поля явной деструктуризацией — при добавлении нового поля компилятор не напомнит, но зато функции точно не попадут. Альтернатива — `Omit<State & Actions, keyof Actions>`, но она молча ломается при переименовании.

**Стор 2. Выделение — часто меняется, не персистится.**

```ts
// src/store/selection.ts
import { create } from 'zustand';

type State = {
  selectedIds: Set<string>;
  lastClickedId: string | null;
};

type Actions = {
  toggle: (id: string, shift?: boolean, allIds?: readonly string[]) => void;
  selectAll: (ids: readonly string[]) => void;
  clear: () => void;
  isSelected: (id: string) => boolean;
};

export const useSelection = create<State & Actions>()((set, get) => ({
  selectedIds: new Set(),
  lastClickedId: null,

  toggle: (id, shift = false, allIds = []) => set(s => {
    const next = new Set(s.selectedIds);

    if (shift && s.lastClickedId) {
      const from = allIds.indexOf(s.lastClickedId);
      const to = allIds.indexOf(id);
      if (from >= 0 && to >= 0) {
        const [a, b] = from < to ? [from, to] : [to, from];
        for (let i = a; i <= b; i++) {
          const cur = allIds[i];
          if (cur) next.add(cur);
        }
        return { selectedIds: next, lastClickedId: id };
      }
    }

    next.has(id) ? next.delete(id) : next.add(id);
    return { selectedIds: next, lastClickedId: id };
  }),

  selectAll: (ids) => set({ selectedIds: new Set(ids) }),
  clear: () => set({ selectedIds: new Set(), lastClickedId: null }),
  isSelected: (id) => get().selectedIds.has(id),
}));
```

**Разбор.**

**`new Set(s.selectedIds)` — копия обязательна.** Мутация существующего `Set` не изменит ссылку, и Zustand не заметит (то же правило, что в уроке 15).

**`get()` для чтения внутри действий.** `isSelected` — не селектор, а метод; вызывать его из компонента как `useSelection(s => s.isSelected(id))` **нельзя**: результат `boolean`, но подписка будет на весь стор... точнее, селектор вернёт новое значение только при изменении, и это как раз сработает. А вот `useSelection().isSelected(id)` подпишет на всё. Правильно:
```tsx
const selected = useSelection(s => s.selectedIds.has(id));   // ✅ подписка на boolean
```

**Shift-выделение диапазона** требует знать порядок элементов — он приходит из компонента параметром `allIds`. Стор не знает про сортировку и фильтры, они живут в URL (урок 27). Это правильное разделение: стор хранит выделение, не список.

**Использование в строке таблицы:**
```tsx
function RunRow({ run, allIds }: { run: Run; allIds: readonly string[] }) {
  const selected = useSelection(s => s.selectedIds.has(run.id));
  const toggle = useSelection(s => s.toggle);
  const freqUnit = useSettings(s => s.freqUnit);

  const peak = freqUnit === 'khz'
    ? `${(run.peakHz / 1000).toFixed(3)} кГц`
    : `${run.peakHz.toFixed(1)} Гц`;

  return (
    <tr
      className={selected ? 'row selected' : 'row'}
      onClick={e => toggle(run.id, e.shiftKey, allIds)}
    >
      <td>{run.label}</td>
      <td>{peak}</td>
    </tr>
  );
}
```

**Вот ради чего всё.** Тысяча строк в таблице. Клик по одной меняет `selectedIds` — но перерисуются только **две** строки: та, что была выделена, и та, что стала. Остальные 998 подписаны на `s.selectedIds.has(their_id)`, значение не изменилось, `Object.is` совпал, рендера нет.

С Context перерисовались бы все тысяча. С подъёмом состояния — вся таблица. Это и есть та задача, ради которой берут Zustand.

**Панель массовых действий — потребитель другого среза:**
```tsx
function BulkActions({ allIds }: { allIds: readonly string[] }) {
  const count = useSelection(s => s.selectedIds.size);
  const { clear, selectAll } = useSelection(useShallow(s => ({
    clear: s.clear, selectAll: s.selectAll,
  })));
  const del = useDeleteRuns();

  if (count === 0) return null;

  return (
    <div className="bulk">
      Выбрано: {count}
      <Button onClick={() => selectAll(allIds)}>Все</Button>
      <Button onClick={clear}>Снять</Button>
      <Button variant="danger" onClick={() => {
        del.mutate([...useSelection.getState().selectedIds]);
        clear();
      }}>Удалить</Button>
    </div>
  );
}
```

`useSelection.getState()` в обработчике — чтение вне подписки. Значение нужно только в момент клика, подписываться на него незачем.

**Проверь.** Открой React DevTools → Profiler, включи подсветку рендеров. Кликай по строкам большой таблицы — должны мигать только две. Потом временно замени селектор на `useSelection()` без аргумента и повтори: замигает всё.

---

# Часть 3. Домашка

**1.** Настрой стор настроек с персистентностью. Перезагрузи страницу — тема и единицы должны сохраниться, а функции-действия не должны появиться в `localStorage`.

**2.** Что не так и как исправить двумя способами?
```tsx
const { theme, units } = useSettings(s => ({ theme: s.theme, units: s.units }));
```

**3.** Миграция. Добавь в состояние поле `precision`, подними `version` до 2, напиши `migrate`. Проверь на старых данных в `localStorage`, что приложение не падает.

**4.** Реализуй стор подключения к прибору: состояние соединения (union из урока 08), действия подключения/отключения, счётчик попыток. Эффект подключения — где ему жить, в сторе или в компоненте? Обоснуй.

**5.** Слайсы. Раздели стор на `viewSlice` и `selectionSlice` с корректной типизацией `StateCreator`. Объясни, зачем понадобились четыре параметра типа.

**6.** Измерь. Таблица на 2000 строк, выделение через Zustand и через Context. Сравни в профайлере число перерисованных компонентов на один клик и время кадра.

**7.** Доступ вне React. Сделай так, чтобы обработчик WebSocket из урока 19 писал статистику пакетов прямо в стор через `setState`, без хуков. Компонент со счётчиком подписан на срез и обновляется раз в секунду.

**8.** Архитектурное. У тебя теперь четыре места хранения: URL, Query, Zustand, `useReducer`. Составь таблицу «что где и почему», найди дублирование и устрани его.
