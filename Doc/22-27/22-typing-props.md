# Урок 22. Типизация props и `children`

Блок, где TypeScript и React стыкуются. Всё из блока 1 продолжает работать — просто теперь применяется к компонентам.

---

# Часть 1. Теория

## 22.1 База

```tsx
type Props = {
  label: string;
  value: number;
  unit?: string;                    // необязательный
  onChange: (v: number) => void;
  children?: React.ReactNode;
};

function Field({ label, value, unit = '', onChange, children }: Props) { }
```

Тип объявляется отдельно, не инлайном — переиспользуется, экспортируется, читается.

**Экспортируй тип props** публичных компонентов. Потребителям он нужен для обёрток:
```tsx
export type ButtonProps = { ... };
export function Button(props: ButtonProps) { }
```

**`React.FC` не используй** — повторю из урока 18, это самая частая устаревшая привычка. Обычная функция с типизированным параметром лучше во всём: не мешает дженерикам, не добавляет неявных props, не требует импорта.

## 22.2 Типы для содержимого

| Тип | Что покрывает |
|---|---|
| `ReactNode` | всё рендеримое: элементы, строки, числа, массивы, `null`, `false` |
| `ReactElement` | результат JSX, без строк и чисел |
| `JSX.Element` | почти то же, что `ReactElement` |
| `ComponentType<P>` | сам компонент как значение (не его результат) |

**По умолчанию — `ReactNode`.** Он самый широкий и не заставляет потребителя оборачивать строку в тег.

`ReactElement` берут, когда собираются инспектировать элемент — читать `props`, клонировать. Редкий случай.

`ComponentType<P>` — когда передают компонент, а не разметку:
```tsx
type Props = {
  icon: React.ComponentType<{ size: number }>;    // компонент
  header: React.ReactNode;                         // готовая разметка
};

<Panel icon={WaveIcon} header={<h2>FFT</h2>} />
```
Разница существенная: компонент можно вызвать с любыми props, готовый элемент — уже зафиксирован.

## 22.3 Наследование нативных props

```tsx
type ButtonProps = React.ComponentProps<'button'> & {
  variant?: 'primary' | 'ghost';
};

function Button({ variant = 'primary', className, ...rest }: ButtonProps) {
  return <button className={`btn btn-${variant} ${className ?? ''}`} {...rest} />;
}
```

`ComponentProps<'button'>` даёт весь набор: `onClick`, `disabled`, `type`, `form`, все `aria-*` и `data-*`. Актуален автоматически.

**Варианты:**
```tsx
React.ComponentProps<'input'>                    // включая ref
React.ComponentPropsWithoutRef<'input'>          // без ref — чаще нужен именно этот
React.ComponentProps<typeof MyComponent>         // props чужого компонента
```

**Конфликт имён.** Если своё свойство совпадает с нативным по имени, но не по типу, `&` даст `never`. Убирай нативное явно:
```tsx
type Props = Omit<React.ComponentProps<'input'>, 'onChange'> & {
  onChange: (value: number) => void;             // своя сигнатура
};
```
Типичный случай: хочется отдавать в `onChange` готовое значение, а не событие.

## 22.4 Взаимоисключающие props

Размеченное объединение из урока 08, применённое к props:

```tsx
type ButtonProps =
  | { as: 'button'; onClick: () => void; href?: never }
  | { as: 'link'; href: string; onClick?: never };

function Button(props: ButtonProps) {
  if (props.as === 'link') return <a href={props.href}>{...}</a>;
  return <button onClick={props.onClick}>{...}</button>;
}
```

`href?: never` в первом варианте — приём, запрещающий передать лишнее. Без него структурная типизация пропустит объект с обоими полями.

**Без дискриминанта** — через `never` в обеих ветках:
```tsx
type Props =
  | { value: string; defaultValue?: never }
  | { defaultValue: string; value?: never };
```
Это решение задачи 5 из урока 17: управляемый или неуправляемый, но не оба сразу.

**Ограничение.** Деструктурировать union в параметрах нельзя — TS не сузит:
```tsx
function Button({ as, href, onClick }: ButtonProps) {   // ❌ href может отсутствовать
```
Принимай `props` целиком, сужай внутри, деструктурируй после.

## 22.5 Полиморфные компоненты

Компонент, который рендерится любым тегом:

```tsx
type BoxProps<E extends React.ElementType> = {
  as?: E;
  children?: React.ReactNode;
} & Omit<React.ComponentPropsWithoutRef<E>, 'as' | 'children'>;

function Box<E extends React.ElementType = 'div'>({
  as, children, ...rest
}: BoxProps<E>) {
  const Component = as ?? 'div';
  return <Component {...rest}>{children}</Component>;
}

<Box as="a" href="/x">ссылка</Box>          // href проверяется
<Box as="button" onClick={f}>кнопка</Box>   // onClick проверяется
<Box href="/x">❌</Box>                      // у div нет href
```

Тип props меняется в зависимости от `as`. Красиво, но платится сложностью: сообщения об ошибках становятся нечитаемыми, вывод иногда ломается.

**Практический совет:** полиморфизм оправдан в дизайн-системе, где `Box` используют сотни раз. В прикладном коде два отдельных компонента проще.

## 22.6 Типизация дефолтов

```tsx
type Props = { size?: number; variant?: 'a' | 'b' };

function C({ size = 16, variant = 'a' }: Props) {
  // внутри size: number, variant: 'a' | 'b' — undefined уже снят
}
```

Деструктуризация с дефолтом сужает тип внутри функции. Снаружи props остаются необязательными. Это правильная схема: удобно и для потребителя, и для реализации.

**Не используй `defaultProps`** — устарел для функциональных компонентов, в React 19 удалён.

## 22.7 Частые ошибки

**Слишком широкий тип обработчика:**
```tsx
onChange: (e: any) => void;                              // ❌
onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;   // ✅ или лучше
onChange: (value: string) => void;                        // ✅✅ компонент не течёт наружу
```
Третий вариант предпочтительнее: потребитель получает значение, а не деталь реализации. Если завтра заменишь `<input>` на кастомный виджет, сигнатура не изменится.

**Массив вместо `readonly`:**
```tsx
items: Item[];              // компонент может мутировать
items: readonly Item[];     // ✅ честнее и принимает результат as const
```

**`object` и `{}` как типы:**
```tsx
config: object;             // ❌ ничего не даёт
config: {};                 // ❌ означает «не null и не undefined»
config: Record<string, unknown>;   // ✅ если правда произвольный
```

---

# Часть 2. Проработка

## Задача. Типизированная библиотека примитивов

Собираем `src/ui/` из компонентов, накопленных в блоке React, но теперь с полными типами.

```tsx
// src/ui/Button.tsx
import type { ComponentPropsWithoutRef, ReactNode } from 'react';

type Variant = 'primary' | 'ghost' | 'danger';

type BaseProps = {
  variant?: Variant;
  loading?: boolean;
  icon?: ReactNode;
};

export type ButtonProps = BaseProps &
  Omit<ComponentPropsWithoutRef<'button'>, keyof BaseProps>;

export function Button({
  variant = 'primary',
  loading = false,
  icon,
  children,
  disabled,
  className,
  ...rest
}: ButtonProps) {
  return (
    <button
      className={['btn', `btn-${variant}`, className].filter(Boolean).join(' ')}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? <Spinner size={14} /> : icon}
      {children}
    </button>
  );
}
```

**`Omit<..., keyof BaseProps>`** — защита от конфликта имён. Если у `<button>` появится нативный `loading`, наш перекроет его без появления `never`.

**`disabled || loading`** — во время загрузки кнопка неактивна автоматически. Логика в одном месте, потребитель об этом не думает.

**`className` вытащен из `rest`** и склеен, а не перезаписан. Частая ошибка — забыть это, и переданный снаружи класс потеряется.

```tsx
// src/ui/Field.tsx
import type { ReactNode } from 'react';

export type FieldProps = {
  label: ReactNode;
  hint?: ReactNode;
  error?: string;
  required?: boolean;
  children: ReactNode;
};

export function Field({ label, hint, error, required, children }: FieldProps) {
  return (
    <label className={`field ${error ? 'field-error' : ''}`}>
      <span className="field-label">
        {label}{required && <abbr title="обязательное">*</abbr>}
      </span>
      {children}
      {error ? (
        <small className="field-msg err" role="alert">{error}</small>
      ) : hint ? (
        <small className="field-msg">{hint}</small>
      ) : null}
    </label>
  );
}
```

`error` и `hint` взаимоисключающи по смыслу, но не по типу — здесь это допустимо, приоритет задан в разметке. Если хочется строгости — union props из 22.4.

**Числовое поле с осмысленной сигнатурой:**
```tsx
// src/ui/NumberInput.tsx
type NumberInputProps =
  Omit<ComponentPropsWithoutRef<'input'>, 'onChange' | 'value' | 'type'> & {
    value: number;
    onChange: (value: number) => void;
  };

export function NumberInput({ value, onChange, ...rest }: NumberInputProps) {
  return (
    <input
      type="number"
      value={value}
      onChange={e => {
        const n = Number(e.target.value);
        if (!Number.isNaN(n)) onChange(n);
      }}
      {...rest}
    />
  );
}
```

Три нативных props убраны и заменены своими. Потребитель работает с числом, конверсия и защита от `NaN` спрятаны внутри. `min`, `max`, `step`, `disabled` остались нативными и работают как обычно.

**Селект, типизированный union'ом** — здесь дженерики уже просятся, но пока обойдёмся конкретикой:
```tsx
// src/ui/WindowSelect.tsx
import { WINDOWS, type WindowFn } from '../types';

type Props = {
  value: WindowFn;
  onChange: (value: WindowFn) => void;
  disabled?: boolean;
};

export function WindowSelect({ value, onChange, disabled }: Props) {
  return (
    <select
      value={value}
      disabled={disabled}
      onChange={e => onChange(e.target.value as WindowFn)}
    >
      {Object.entries(WINDOWS).map(([key, info]) => (
        <option key={key} value={key}>{info.label}</option>
      ))}
    </select>
  );
}
```

`as WindowFn` — вынужденное, DOM отдаёт `string`. Но приведение безопасно по построению: значения `<option>` берутся из того же `WINDOWS`. Строже — валидировать:
```tsx
const parse = (v: string): WindowFn => (v in WINDOWS ? v as WindowFn : value);
```

В уроке 23 сделаем из этого дженерик-`Select<T>`, работающий с любым union.

**Проверь, что типы реально работают.** Попробуй:
```tsx
<Button variant="huge">❌</Button>
<NumberInput value="1024" onChange={...} />     ❌ строка
<WindowSelect value="hanning" onChange={...} /> ❌ опечатка
<Field label="Размер" />                        ❌ нет children
<Button onClick={() => {}} href="/x" />         ❌ у button нет href
```
Все пять должны подсветиться. Если какой-то прошёл — разберись почему, это важнее, чем написать следующий компонент.

---

# Часть 3. Домашка

**1.** Типизируй `Panel` из урока 18 полностью: слоты, поведение, нативные атрибуты `<section>`. Сделай так, чтобы `onToggle` без `collapsed` не компилировался.

**2.** Найди и объясни четыре проблемы:
```tsx
const Card: React.FC<{ items: any[], onClick: Function }> = (props) => {
  return <div className={props.className}>{props.children}</div>;
};
```

**3.** Компонент `Alert` с взаимоисключающими props: либо `error: Error`, либо `message: string`, но не оба и не ни одного. Реализуй через union, проверь все четыре случая.

**4.** Оберни `<a>` в компонент `Link`, который принимает все нативные атрибуты, но `href` делает обязательным, а `target="_blank"` автоматически добавляет `rel="noopener noreferrer"`.

**5.** Полиморфный `Text` из 22.5: `<Text as="h1">`, `<Text as="span">`, по умолчанию `<p>`. Убедись, что при `as="a"` требуется `href`, а при `as="p"` — не разрешается.

**6.** Почему тут `never` и как починить?
```tsx
type Props = React.ComponentProps<'input'> & { size: 'sm' | 'lg' };
```

**7.** Возьми `ConfigEditor` из урока 18 и перепиши на новых примитивах `Field` + `NumberInput` + `WindowSelect`. Сравни количество строк до и после.

**8.** Спроектируй props для компонента `SpectrumView`, который умеет три режима отображения: линия, столбцы, водопад. У водопада есть параметр глубины истории, у столбцов — ширина, у линии — толщина. Сделай так, чтобы параметр чужого режима передать было нельзя.
