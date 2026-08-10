# Урок 23. Дженерик-компоненты

Компонент, работающий с любым типом данных, не теряя информацию о нём. Дженерики из урока 09, применённые к React.

---

# Часть 1. Теория

## 23.1 Синтаксис

```tsx
type ListProps<T> = {
  items: readonly T[];
  renderItem: (item: T) => React.ReactNode;
  getKey: (item: T) => string | number;
};

function List<T>({ items, renderItem, getKey }: ListProps<T>) {
  return <ul>{items.map(i => <li key={getKey(i)}>{renderItem(i)}</li>)}</ul>;
}
```

Использование — параметр типа выводится из `items`:
```tsx
<List
  items={runs}
  getKey={r => r.id}                    // r: Run — выведено
  renderItem={r => <RunRow run={r} />}  // r: Run
/>
```

Ни одной аннотации в месте вызова. Это главная ценность: типы текут через компонент, коллбэки получают правильный тип автоматически.

## 23.2 Ловушка `.tsx`

В файлах `.tsx` стрелочная функция с `<T>` парсится как JSX-тег:

```tsx
const f = <T>(x: T) => x;              // ❌ ошибка разбора
const f = <T,>(x: T) => x;             // ✅ запятая
const f = <T extends unknown>(x: T) => x;   // ✅ ограничение
```

В обычных `function` проблемы нет:
```tsx
function List<T>(props: Props<T>) { }  // ✅ всегда работает
```

Ещё одна причина писать компоненты через `function`, а не через `const`.

## 23.3 Ограничения параметра

```tsx
type Props<T extends { id: string }> = {
  items: readonly T[];
  onSelect: (item: T) => void;
};

function Table<T extends { id: string }>({ items, onSelect }: Props<T>) {
  return <>{items.map(i => <Row key={i.id} onClick={() => onSelect(i)} />)}</>;
}
```

Раз у всех элементов есть `id`, можно не требовать `getKey`. Компромисс: компонент менее универсален, зато проще в использовании.

**Два параметра** — когда типы связаны:
```tsx
type SelectProps<T, V extends string | number> = {
  items: readonly T[];
  getValue: (item: T) => V;
  value: V;
  onChange: (value: V) => void;
};
```

## 23.4 Ограничение по ключам

Мощный приём — типизировать колонки таблицы ключами данных:

```tsx
type Column<T> = {
  key: keyof T & string;
  header: string;
  render?: (value: T[keyof T], row: T) => React.ReactNode;
};
```

Проблема: `T[keyof T]` — union всех типов значений, а не тип конкретного поля. Решается вынесением ключа в свой параметр:

```tsx
type Column<T, K extends keyof T = keyof T> = {
  key: K;
  header: string;
  render?: (value: T[K], row: T) => React.ReactNode;
};

type Columns<T> = { [K in keyof T]: Column<T, K> }[keyof T][];
```

Разбор `Columns<T>`: mapped type строит объект, где каждому ключу соответствует `Column` именно с этим ключом. Затем `[keyof T]` схлопывает в union, `[]` делает массив. Итог — массив колонок, где каждая знает свой точный тип значения.

Приём из урока 11 в чистом виде. Именно так типизированы таблицы в TanStack Table.

## 23.5 `React.memo` ломает дженерики

```tsx
const MemoList = React.memo(List);      // T потерян
```

`memo` типизирован через `ComponentType`, который не сохраняет параметры типа. Обход — приведение:

```tsx
const MemoList = React.memo(List) as typeof List;
```

Работает, но `memo` перестаёт учитываться в типах — это чисто рантайм-обёртка. Приемлемо.

Альтернатива — не мемоизировать дженерик-компоненты, а мемоизировать конкретные использования внутри.

## 23.6 `forwardRef` и дженерики

Та же проблема, решение похожее:

```tsx
function ListInner<T>(props: Props<T>, ref: React.Ref<HTMLUListElement>) {
  return <ul ref={ref}>...</ul>;
}

const List = React.forwardRef(ListInner) as <T>(
  props: Props<T> & { ref?: React.Ref<HTMLUListElement> }
) => React.ReactElement;
```

**В React 19 это упростилось:** `ref` стал обычным props, `forwardRef` для новых компонентов не нужен вообще:
```tsx
function List<T>({ items, ref }: Props<T> & { ref?: Ref<HTMLUListElement> }) {
  return <ul ref={ref}>...</ul>;
}
```
Проверь версию React в проекте, прежде чем писать `forwardRef`.

## 23.7 Когда дженерик не нужен

**Если тип фиксирован** — просто укажи его:
```tsx
function RunList({ runs }: { runs: Run[] }) { }        // ✅ проще
function RunList<T extends Run>({ runs }: Props<T>) { } // ❌ зачем?
```

**Правило из урока 09 действует:** параметр типа должен встречаться минимум дважды и **связывать** вход с выходом. Если `T` появляется только в `items` — дженерик не нужен.

**Если компонент используется один раз** — тем более. Универсальность окупается на третьем применении.

---

# Часть 2. Проработка

## Задача. Универсальный `Select` и таблица

**Селект для любого union.** Заменяет `WindowSelect` из урока 22 и все будущие однотипные.

```tsx
// src/ui/Select.tsx
type SelectProps<T extends string | number> = {
  value: T;
  options: readonly T[];
  onChange: (value: T) => void;
  getLabel?: (value: T) => React.ReactNode;
  disabled?: boolean;
  id?: string;
};

export function Select<T extends string | number>({
  value, options, onChange, getLabel, disabled, id,
}: SelectProps<T>) {
  return (
    <select
      id={id}
      value={value}
      disabled={disabled}
      onChange={e => {
        const raw = e.target.value;
        // возвращаем ИСХОДНОЕ значение из options, а не строку из DOM
        const found = options.find(o => String(o) === raw);
        if (found !== undefined) onChange(found);
      }}
    >
      {options.map(o => (
        <option key={String(o)} value={String(o)}>
          {getLabel?.(o) ?? String(o)}
        </option>
      ))}
    </select>
  );
}
```

**Ключевая деталь — поиск в `options` вместо приведения.** В уроке 22 мы писали `e.target.value as WindowFn` — это работало, но было заявлением без проверки. Здесь мы находим оригинальное значение в массиве, и приведение не нужно вообще: `found` уже имеет тип `T`. Заодно корректно работают числа — `FftSize` останется числом, а не станет строкой.

Применение:
```tsx
<Select
  value={config.window}
  options={Object.keys(WINDOWS) as WindowFn[]}
  onChange={w => patch({ window: w })}        // w: WindowFn
  getLabel={w => WINDOWS[w].label}
/>

<Select
  value={config.size}
  options={FFT_SIZES}
  onChange={size => patch({ size })}          // size: FftSize
  getLabel={s => `${s} точек`}
/>
```

Один компонент вместо двух, типы выводятся, `onChange` получает точный union.

**`Object.keys(WINDOWS) as WindowFn[]`** — приведение неизбежно: `Object.keys` типизирован как `string[]` по той же причине, что `Object.entries` в уроке 10. Заведи хелпер и используй везде:
```tsx
// src/lib/objects.ts
export const keysOf = <T extends object>(o: T) => Object.keys(o) as (keyof T & string)[];
export const entriesOf = <T extends object>(o: T) =>
  Object.entries(o) as [keyof T & string, T[keyof T]][];
```

**Таблица с типизированными колонками.**

```tsx
// src/ui/DataTable.tsx
type Column<T, K extends keyof T = keyof T> = {
  key: K;
  header: React.ReactNode;
  render?: (value: T[K], row: T) => React.ReactNode;
  align?: 'left' | 'right';
};

type AnyColumn<T> = { [K in keyof T]: Column<T, K> }[keyof T];

type Props<T> = {
  rows: readonly T[];
  columns: readonly AnyColumn<T>[];
  getKey: (row: T) => string | number;
  onRowClick?: (row: T) => void;
  empty?: React.ReactNode;
};

export function DataTable<T>({
  rows, columns, getKey, onRowClick, empty,
}: Props<T>) {
  if (rows.length === 0) return <>{empty ?? <p>Нет данных</p>}</>;

  return (
    <table>
      <thead>
        <tr>{columns.map(c => (
          <th key={String(c.key)} style={{ textAlign: c.align ?? 'left' }}>
            {c.header}
          </th>
        ))}</tr>
      </thead>
      <tbody>
        {rows.map(row => (
          <tr key={getKey(row)} onClick={() => onRowClick?.(row)}>
            {columns.map(c => (
              <td key={String(c.key)} style={{ textAlign: c.align ?? 'left' }}>
                {c.render
                  ? c.render(row[c.key] as never, row)
                  : String(row[c.key])}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

Применение:
```tsx
<DataTable
  rows={runs}
  getKey={r => r.id}
  columns={[
    { key: 'label', header: 'Название' },
    {
      key: 'peakHz',
      header: 'Пик',
      align: 'right',
      render: hz => `${hz.toFixed(1)} Гц`,     // hz: number — точный тип!
    },
    {
      key: 'elapsedMs',
      header: 'Время',
      align: 'right',
      render: (ms, row) => (
        <span title={row.label}>{ms} мс</span>   // ms: number, row: Run
      ),
    },
  ]}
  onRowClick={r => select(r.id)}                // r: Run
/>
```

**Что работает.** В `render` для `peakHz` параметр имеет тип `number`, для строкового поля был бы `string`. Опечатка в `key` не скомпилируется — только реальные ключи `Run`. Это результат `AnyColumn<T>` из 23.4.

**`row[c.key] as never` внутри** — вынужденная дыра. Компилятор не может связать конкретную колонку с её `render` в общем цикле: для него `columns` — массив union'а, и он не знает, что `c.render` и `row[c.key]` относятся к одному `K`. Дыра локальна, снаружи типизация полная.

Это общий паттерн из урока 11: **сложность в сигнатуре, дыра в реализации, безопасность на границе**. Так устроены все типизированные библиотеки.

**Проверь границы.** Попробуй:
```tsx
{ key: 'nope', header: 'X' }                          // ❌ нет такого поля
{ key: 'peakHz', render: (hz) => hz.toUpperCase() }   // ❌ number не строка
<DataTable rows={runs} columns={cols} />              // ❌ нет getKey
```

---

# Часть 3. Домашка

**1.** Почему не компилируется и как исправить двумя способами?
```tsx
const Identity = <T>(props: { value: T }) => props.value;
```

**2.** Дженерик `Autocomplete<T>`: список опций, фильтрация по строке, выбор. `getLabel` и `getKey` — обязательные, `renderOption` — необязательный. Проверь вывод типов во всех коллбэках.

**3.** Добавь в `DataTable` сортировку. Тип `sortBy` должен допускать только ключи, значения которых сравнимы (число, строка, дата). Подсказка: фильтрующий mapped type из урока 11.

**4.** Реализуй `useSelection<T>(items, getKey)` — хук множественного выбора, возвращающий `{ selected, toggle, selectAll, clear, isSelected }`. Типы должны течь: `toggle` принимает `T`, `selected` это `T[]`.

**5.** Что не так и почему `React.memo` ломает типы? Исправь:
```tsx
const List = React.memo(function List<T>({ items }: { items: T[] }) {
  return <ul>{items.map((i, k) => <li key={k}>{String(i)}</li>)}</ul>;
});
```

**6.** Напиши `keysOf` и `entriesOf` из проработки с корректными типами. Объясни, почему встроенные `Object.keys` и `Object.entries` типизированы слабее и в каком случае твоя версия соврёт.

**7.** Дженерик-форма: `<Form<T> initial={...} onSubmit={...}>` с полями, привязанными к ключам `T`. Поле `<Form.Field name="size">` должно принимать только существующие ключи, а его `value` — иметь тип соответствующего поля.

**8.** Разбери, когда дженерик избыточен. Для каждого — нужен или нет, обоснуй:
```tsx
function Badge<T extends string>({ text }: { text: T }) {}
function Tabs<T extends string>({ value, options, onChange }: {...}) {}
function Card<T>({ data, render }: { data: T; render: (d: T) => ReactNode }) {}
function Icon<T extends IconName>({ name }: { name: T }) {}
```
