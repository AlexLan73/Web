# Урок 18. Композиция через `children`

Как строить компоненты, которые не превращаются в свалку булевых флагов. В React наследования нет вообще — вся переиспользуемость держится на композиции.

---

# Часть 1. Теория

## 18.1 `children`

Всё между открывающим и закрывающим тегом попадает в `props.children`:

```tsx
<Card>
  <h2>Заголовок</h2>
  <p>Текст</p>
</Card>
```

```tsx
function Card({ children }: { children: React.ReactNode }) {
  return <div className="card">{children}</div>;
}
```

`children` — обычный props, просто с особым синтаксисом передачи. Эквивалентно:
```tsx
<Card children={<p>Текст</p>} />
```

**Тип — `React.ReactNode`**: элементы, строки, числа, массивы, фрагменты, `null`, `undefined`, `false`. Всё, что React умеет отрисовать.

Не путай с `React.ReactElement` — это конкретно результат JSX, без строк и чисел. Нужен редко, когда собираешься инспектировать элемент.

## 18.2 Проблема конфигурации флагами

Компонент, который пытается предусмотреть все случаи через props:

```tsx
<Panel
  title="FFT"
  showHeader
  showFooter
  headerIcon="wave"
  collapsible
  footerButtons={['save', 'reset']}
  bordered
  variant="compact"
/>
```

Симптомы: props растут с каждым новым требованием, внутри компонента ветвление на ветвлении, невозможно сделать что-то чуть-чуть иначе без ещё одного флага.

Корень проблемы: компонент пытается **знать** обо всех вариантах использования. Их бесконечно много.

## 18.3 Решение: слоты

Передавай содержимое вместо инструкций по его построению:

```tsx
type PanelProps = {
  header?: React.ReactNode;
  footer?: React.ReactNode;
  children: React.ReactNode;
};

function Panel({ header, footer, children }: PanelProps) {
  return (
    <section className="panel">
      {header && <div className="panel-header">{header}</div>}
      <div className="panel-body">{children}</div>
      {footer && <div className="panel-footer">{footer}</div>}
    </section>
  );
}
```

Использование:
```tsx
<Panel
  header={<><Icon name="wave" /> Параметры FFT</>}
  footer={<Button onClick={save}>Сохранить</Button>}
>
  <ConfigEditor value={config} onChange={setConfig} />
</Panel>
```

Панель больше ничего не знает про иконки, кнопки и заголовки. Она знает только про раскладку. Число возможных применений — неограниченно, число props — три.

**Правило:** props для **поведения и данных**, слоты для **содержимого**.

## 18.4 Составные компоненты

Когда слотов много, именованные подкомпоненты читаются лучше:

```tsx
function Panel({ children }: { children: React.ReactNode }) {
  return <section className="panel">{children}</section>;
}

Panel.Header = function Header({ children }: { children: React.ReactNode }) {
  return <div className="panel-header">{children}</div>;
};

Panel.Body = function Body({ children }: { children: React.ReactNode }) {
  return <div className="panel-body">{children}</div>;
};
```

```tsx
<Panel>
  <Panel.Header>Параметры FFT</Panel.Header>
  <Panel.Body><ConfigEditor {...props} /></Panel.Body>
</Panel>
```

Плюсы: структура видна в JSX, порядок и наличие частей контролирует пользователь, автодополнение подсказывает доступные части.

Минус: без Context части не могут обмениваться данными. Для `<Tabs>`, где заголовок должен знать активную вкладку, понадобится Context — и это законный случай его применения.

## 18.5 Render props

Когда компонент владеет данными, а как их отрисовать — решает потребитель:

```tsx
type Props<T> = {
  items: readonly T[];
  renderItem: (item: T, index: number) => React.ReactNode;
  renderEmpty?: () => React.ReactNode;
};

function List<T>({ items, renderItem, renderEmpty }: Props<T>) {
  if (items.length === 0) return <>{renderEmpty?.() ?? <p>Пусто</p>}</>;
  return <ul>{items.map((item, i) => <li key={i}>{renderItem(item, i)}</li>)}</ul>;
}
```

```tsx
<List
  items={runs}
  renderItem={run => <RunRow run={run} />}
/>
```

Вариант — функция как `children`:
```tsx
<DataLoader url="/api/runs">
  {(data, loading) => loading ? <Spinner /> : <RunList runs={data} />}
</DataLoader>
```

**Историческая заметка.** До хуков render props были основным способом переиспользовать логику. Сейчас для логики берут кастомные хуки (урок 21) — читается лучше, вложенности нет. Render props остались там, где нужно именно отрисовать чужие данные своим способом: таблицы, виртуализированные списки, графики.

## 18.6 Композиция против prop drilling

Приём из урока 17, теперь подробно.

**Проброс:**
```tsx
function Layout({ config, onChange }: Props) {
  return <aside><ConfigPanel config={config} onChange={onChange} /></aside>;
}

<Layout config={config} onChange={setConfig} />
```
`Layout` знает про `config`, хотя ему это не нужно. Изменится тип конфига — придётся править и `Layout`.

**Композиция:**
```tsx
function Layout({ sidebar, children }: {
  sidebar: React.ReactNode;
  children: React.ReactNode;
}) {
  return <><aside>{sidebar}</aside><main>{children}</main></>;
}

<Layout sidebar={<ConfigPanel config={config} onChange={setConfig} />}>
  <Chart data={bins} />
</Layout>
```

`Layout` теперь ничего не знает о предметной области. Элемент создаётся **там, где есть данные**, и передаётся готовым.

Дополнительный эффект: `Layout` не перерисовывается при изменении `config`. Он получает уже созданный элемент; изменение приведёт к новому элементу в props, но сам `Layout` останется тем же — React обновит только поддерево.

Это самый недооценённый приём в React. Большая часть жалоб на prop drilling решается здесь, без Context и без стора.

## 18.7 Утилиты для работы с children

```tsx
React.Children.count(children)
React.Children.map(children, child => ...)
React.Children.toArray(children)
React.isValidElement(child)
React.cloneElement(child, { extraProp: 1 })
```

**Используй редко.** Инспекция и модификация детей — хрупкий приём: ломается при обёртке в фрагмент, при условном рендере, при передаче массива. Официальная документация прямо не рекомендует `cloneElement`.

Если хочется передать данные детям — это Context. Если хочется ограничить, какие дети допустимы — это слоты с типизированными props.

## 18.8 Типизация

```tsx
type Props = {
  children: React.ReactNode;              // обычный случай
  children: React.ReactNode | ((x: T) => React.ReactNode);   // render prop
  render: (x: T) => React.ReactNode;      // явный render prop
};
```

**`React.FC` не используй.** Устаревший тип: раньше он неявно добавлял `children`, что скрывало ошибки, а с версии 18 перестал — и весь смысл пропал. Пиши обычную функцию с типизированными props.

```tsx
// ❌
const Panel: React.FC<Props> = ({ children }) => ...

// ✅
function Panel({ children }: Props) { ... }
```

**Проброс нативных props** — когда компонент оборачивает элемент DOM:
```tsx
type ButtonProps = React.ComponentProps<'button'> & {
  variant?: 'primary' | 'ghost';
};

function Button({ variant = 'primary', ...rest }: ButtonProps) {
  return <button className={`btn btn-${variant}`} {...rest} />;
}
```
`React.ComponentProps<'button'>` даёт все атрибуты кнопки — `onClick`, `disabled`, `type`, `aria-*`. Не надо перечислять руками, и типы всегда актуальны.

---

# Часть 2. Проработка

## Задача. Панель на слотах

Переписываем раскладку `dsp-panel`, чтобы компоненты не знали друг о друге.

```tsx
// src/ui/Panel.tsx
import type { ReactNode } from 'react';

type Props = {
  title: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  collapsed?: boolean;
  onToggle?: () => void;
};

export function Panel({ title, actions, children, collapsed = false, onToggle }: Props) {
  return (
    <section className="panel">
      <header className="panel-head">
        {onToggle && (
          <button className="panel-toggle" onClick={onToggle}>
            {collapsed ? '▸' : '▾'}
          </button>
        )}
        <h2>{title}</h2>
        {actions && <div className="panel-actions">{actions}</div>}
      </header>
      {!collapsed && <div className="panel-body">{children}</div>}
    </section>
  );
}
```

Обрати внимание на разделение: `collapsed` и `onToggle` — это **поведение**, они props. `title`, `actions`, `children` — **содержимое**, они слоты.

Панель управляемая: сама не хранит `collapsed`, получает извне. По правилу из урока 17 — потому что родитель может захотеть, например, свернуть все панели разом.

```tsx
// src/ui/Field.tsx
type FieldProps = {
  label: ReactNode;
  hint?: ReactNode;
  children: ReactNode;
};

export function Field({ label, hint, children }: FieldProps) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {hint && <small className="field-hint">{hint}</small>}
    </label>
  );
}
```

Теперь `ConfigEditor` из урока 17 упрощается:
```tsx
export function ConfigEditor({ value, onChange, disabled }: Props) {
  const patch = (p: Partial<FftConfig>) => onChange({ ...value, ...p });
  const resolution = 44100 / value.size;

  return (
    <fieldset disabled={disabled}>
      <Field label="Размер FFT" hint={`${resolution.toFixed(2)} Гц на бин`}>
        <select value={value.size}
          onChange={e => patch({ size: Number(e.target.value) as FftSize })}>
          {FFT_SIZES.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
      </Field>

      <Field label="Окно" hint={WINDOWS[value.window].label}>
        <select value={value.window}
          onChange={e => patch({ window: e.target.value as WindowFn })}>
          {Object.entries(WINDOWS).map(([k, i]) =>
            <option key={k} value={k}>{i.label}</option>)}
        </select>
      </Field>
    </fieldset>
  );
}
```

`Field` не знает ничего про FFT. `Panel` не знает про `Field`. Каждый уровень отвечает за одну вещь.

**Сборка — вот где видна польза:**
```tsx
export default function App() {
  const [config, setConfig] = useState<FftConfig>(DEFAULT_CONFIG);
  const [analysis, setAnalysis] = useState<Analysis>({ status: 'idle' });
  const [runs, setRuns] = useState<Run[]>([]);
  const [collapsed, setCollapsed] = useState({ cfg: false, runs: false });

  const isBusy = analysis.status === 'running';

  return (
    <Layout
      sidebar={
        <Panel
          title="Параметры"
          collapsed={collapsed.cfg}
          onToggle={() => setCollapsed(c => ({ ...c, cfg: !c.cfg }))}
          actions={<Button onClick={() => setConfig(DEFAULT_CONFIG)}>Сброс</Button>}
        >
          <ConfigEditor value={config} onChange={setConfig} disabled={isBusy} />
        </Panel>
      }
    >
      <Panel title="Результат" actions={<StatusLine analysis={analysis} />}>
        <SpectrumView analysis={analysis} />
      </Panel>

      <Panel
        title={`Прогоны (${runs.length})`}
        collapsed={collapsed.runs}
        onToggle={() => setCollapsed(c => ({ ...c, runs: !c.runs }))}
      >
        <RunList runs={runs} onDelete={id => setRuns(rs => rs.filter(r => r.id !== id))} />
      </Panel>
    </Layout>
  );
}
```

**Что мы получили.**

`Layout` и `Panel` — чистые примитивы раскладки, переиспользуемые в любом проекте. Ни один из них не импортирует `types.ts`.

Всё доменное знание сосредоточено в `App` и в специализированных компонентах. Граница между «библиотечным» и «прикладным» кодом проходит по признаку «знает ли компонент про FFT».

Проброса нет ни одного уровня: `config` идёт напрямую из `App` в `ConfigEditor`, потому что элемент создаётся там же, где живут данные.

---

# Часть 3. Домашка

**1.** Перепиши через слоты, убрав флаги:
```tsx
<Dialog
  title="Удалить прогон?"
  showCancel
  confirmLabel="Удалить"
  danger
  icon="warning"
  onConfirm={...}
  onCancel={...}
/>
```

**2.** Реализуй `<Tabs>` составными компонентами: `Tabs`, `Tabs.List`, `Tabs.Tab`, `Tabs.Panel`. Активная вкладка — состояние внутри `Tabs`. Тебе понадобится Context, чтобы `Tab` знал, активен ли он. Напиши это; Context мы формально не проходили, но здесь он в чистом виде.

**3.** Типизируй `Button` так, чтобы он принимал все нативные атрибуты кнопки плюс свои. Затем сделай вариант, который может рендериться либо как `<button>`, либо как `<a>` — с корректными типами для каждого случая (подсказка: union props из урока 08).

**4.** Найди проблему и перепиши через композицию:
```tsx
function Toolbar({ config, onChange, runs, onDelete, analysis, onRun }) {
  return <div className="toolbar">
    <ConfigSummary config={config} />
    <RunCount runs={runs} />
    <RunButton analysis={analysis} onRun={onRun} />
  </div>;
}
```

**5.** Реализуй `<Show when={...} fallback={...}>` — компонент условного рендера. Затем объясни, почему в React такой компонент обычно не нужен и чем он хуже обычного `{cond ? a : b}`.

**6.** Render prop. Напиши `<Measure>`, который замеряет время рендера своих детей и передаёт результат наружу:
```tsx
<Measure>{(ms) => <span>Отрисовано за {ms} мс</span>}</Measure>
```
Подумай, где здесь ловушка с бесконечным циклом.

**7.** Объясни, почему второй вариант не вызывает перерисовку `Layout` при изменении `config`, а первый вызывает:
```tsx
<Layout config={config}><Chart /></Layout>
<Layout sidebar={<Panel config={config} />}><Chart /></Layout>
```
