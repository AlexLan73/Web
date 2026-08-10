# Урок 17. Подъём состояния, однонаправленный поток

Архитектурный урок. Синтаксиса почти нет — есть правила размещения состояния, от которых зависит, будет ли приложение поддерживаемым.

---

# Часть 1. Теория

## 17.1 Однонаправленный поток

Единственный разрешённый способ передачи в React:

- **Данные идут вниз** — через props
- **События идут вверх** — через коллбэки в props

Обратной связи нет. Ребёнок не может изменить состояние родителя напрямую — только вызвать функцию, которую родитель ему дал, и родитель сам решит, что делать.

```tsx
function Parent() {
  const [value, setValue] = useState(0);
  return <Child value={value} onChange={setValue} />;
}

function Child({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  return <input value={value} onChange={e => onChange(Number(e.target.value))} />;
}
```

Аналогия из твоей области: это шина с одним ведущим. Периферия не пишет в память ведущего — она выставляет запрос, ведущий его обрабатывает. Предсказуемость покупается за счёт лишнего этапа.

**Что это даёт.** Чтобы понять, почему значение стало таким, достаточно найти владельца состояния и посмотреть, кто вызывает его сеттер. Список мест ограничен и виден в коде. В системах с двусторонним связыванием (Angular 1, Vue с `v-model` без явных событий) такой поиск превращается в расследование.

## 17.2 Подъём состояния

Правило размещения:

> Состояние живёт в **ближайшем общем предке** всех компонентов, которым оно нужно.

Ниже — компоненты не увидят. Выше — лишние перерисовки и раздутый родитель.

**До подъёма** — два независимых состояния, синхронизировать нечем:
```tsx
function Panel() {
  return <><SizeSelect /><Resolution /></>;   // каждый со своим useState
}
```

**После подъёма:**
```tsx
function Panel() {
  const [size, setSize] = useState<FftSize>(1024);
  return (
    <>
      <SizeSelect value={size} onChange={setSize} />
      <Resolution size={size} />
    </>
  );
}
```

Дети стали **управляемыми** — у них нет своего состояния, они полностью определяются props.

## 17.3 Управляемые и неуправляемые компоненты

**Неуправляемый** — хранит состояние внутри:
```tsx
function Input() {
  const [value, setValue] = useState('');
  return <input value={value} onChange={e => setValue(e.target.value)} />;
}
```
Родитель не знает значение и не может его задать.

**Управляемый** — значение и обработчик приходят снаружи:
```tsx
function Input({ value, onChange }: Props) {
  return <input value={value} onChange={e => onChange(e.target.value)} />;
}
```

**Как выбирать.** По умолчанию — неуправляемый, пока значение никому больше не нужно. Как только понадобилось снаружи (валидация, сброс, синхронизация с другим полем) — поднимай.

Гибкий вариант — поддерживать оба режима:
```tsx
function Input({ value, defaultValue, onChange }: Props) {
  const [internal, setInternal] = useState(defaultValue ?? '');
  const isControlled = value !== undefined;
  const current = isControlled ? value : internal;

  const handle = (v: string) => {
    if (!isControlled) setInternal(v);
    onChange?.(v);
  };
  return <input value={current} onChange={e => handle(e.target.value)} />;
}
```
Так устроены компоненты из библиотек. В своём коде городить это стоит, только если компонент действительно переиспользуется в обоих режимах.

**Частая ошибка:** переключение между режимами на лету. Если `value` был `undefined`, а стал строкой, React выдаст предупреждение — поле сменило тип. Определяйся при монтировании.

## 17.4 Prop drilling и что с ним делать

Проброс props через промежуточные компоненты, которым они не нужны:

```tsx
<App config={c}>
  <Layout config={c}>
    <Sidebar config={c}>
      <ConfigPanel config={c} />   // только здесь реально используется
```

Три уровня — терпимо. Пять — сигнал.

Решения по возрастанию тяжести:

**1. Композиция вместо проброса** (урок 18) — часто снимает проблему целиком:
```tsx
<Layout sidebar={<ConfigPanel config={c} />} />
```
`Layout` больше не знает про `config` — он получает готовый элемент.

**2. Context** — для действительно глобального: тема, локаль, текущий пользователь. Не для часто меняющихся данных: любое изменение перерисует всех потребителей.

**3. Внешнее хранилище** — Zustand (урок 29). Для состояния, которое нужно во многих несвязанных местах.

Порядок важен: большинство берётся первым способом, а начинают почему-то с третьего.

## 17.5 Что вообще не должно быть состоянием

Проверочный список. Значение **не** нужно класть в `useState`, если оно:

- **Вычислимо из props или другого состояния** — считай при рендере
- **Не влияет на отрисовку** — таймер, id соединения, предыдущее значение → `useRef` (урок 20)
- **Приходит с сервера** → TanStack Query (урок 28), у него свой кеш
- **Живёт в URL** — фильтры, номер страницы, выбранная вкладка → роутер (урок 27)
- **Константа** — вынеси за пределы компонента

Последнее часто упускают:
```tsx
function Panel() {
  const options = ['a', 'b', 'c'];    // новый массив каждый рендер
}

const OPTIONS = ['a', 'b', 'c'];      // ✅ один раз на модуль
function Panel() { }
```

## 17.6 Типизация коллбэков

```tsx
type Props = {
  value: FftConfig;
  onChange: (next: FftConfig) => void;
  onDelete?: () => void;                    // необязательный
  onSelect: (id: string, shift: boolean) => void;
};
```

**Возвращай `void`, а не `boolean`** — если результат не используется. Тип `() => void` разрешает передать функцию с любым возвратом, это удобно:
```tsx
<Button onClick={() => setCount(c => c + 1)} />   // setCount возвращает void, ок
```

**Именование:** `onSomething` для props-коллбэков, `handleSomething` для реализаций. Соглашение всей экосистемы.

**Функциональный сеттер в props** — когда ребёнку нужно обновить на основе предыдущего:
```tsx
type Props = { onChange: (updater: (prev: FftConfig) => FftConfig) => void };
```
Работает, но обычно избыточно. Проще передать конкретное действие: `onSizeChange(size)`.

---

# Часть 2. Проработка

## Задача. Разделение панели на компоненты

Берём `App.tsx` из урока 15 — там всё в одном компоненте — и разбираем на части, не потеряв связность.

**Состояние остаётся в `App`**, потому что `config` нужен и редактору, и превью, и кнопке запуска.

```tsx
// src/ConfigEditor.tsx
import { WINDOWS, FFT_SIZES, type FftConfig, type FftSize, type WindowFn } from './types';

type Props = {
  value: FftConfig;
  onChange: (next: FftConfig) => void;
  disabled?: boolean;
};

export function ConfigEditor({ value, onChange, disabled = false }: Props) {
  // локальный хелпер — обновление одного поля без потери остальных
  const patch = (p: Partial<FftConfig>) => onChange({ ...value, ...p });

  return (
    <fieldset disabled={disabled}>
      <legend>Параметры</legend>

      <label>
        Размер FFT
        <select
          value={value.size}
          onChange={e => patch({ size: Number(e.target.value) as FftSize })}
        >
          {FFT_SIZES.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
      </label>

      <label>
        Окно
        <select
          value={value.window}
          onChange={e => patch({ window: e.target.value as WindowFn })}
        >
          {Object.entries(WINDOWS).map(([k, info]) => (
            <option key={k} value={k}>{info.label}</option>
          ))}
        </select>
      </label>

      <label>
        Перекрытие: {Math.round(value.overlap * 100)}%
        <input
          type="range" min={0} max={0.9} step={0.05}
          value={value.overlap}
          onChange={e => patch({ overlap: Number(e.target.value) })}
        />
      </label>
    </fieldset>
  );
}
```

**`patch` через `Partial<FftConfig>`** — приём из урока 10. Один хелпер вместо трёх раскрытий спреда. Типы проверяют, что ключ существует и значение подходит.

**Компонент полностью управляемый** — ни одного `useState`. Он чистая функция от props, и это делает его тривиальным для тестирования и переиспользования.

**`disabled` пробрасывается на `fieldset`** — нативный HTML отключает все вложенные поля сразу. Меньше кода, чем передавать `disabled` в каждый `input`.

**Сборка в `App`:**
```tsx
export default function App() {
  const [config, setConfig] = useState<FftConfig>({
    size: 1024, window: 'hann', overlap: 0.5,
  });
  const [analysis, setAnalysis] = useState<Analysis>({ status: 'idle' });
  const [runs, setRuns] = useState<Run[]>([]);

  const isBusy = analysis.status === 'running';

  const handleRun = () => { /* ...урок 19 */ };

  const handleDelete = (id: string) =>
    setRuns(rs => rs.filter(r => r.id !== id));

  return (
    <main>
      <h1>DSP-панель</h1>
      <ConfigEditor value={config} onChange={setConfig} disabled={isBusy} />
      <button onClick={handleRun} disabled={isBusy}>Запустить</button>
      <StatusLine analysis={analysis} />
      <RunList runs={runs} onDelete={handleDelete} />
    </main>
  );
}
```

**Что здесь важно.**

**`isBusy` — производное.** Не отдельное состояние, а вычисление из `analysis`. Рассинхрона быть не может по построению.

**`onChange={setConfig}`** передаётся напрямую — сигнатура `(next: FftConfig) => void` совпадает с сеттером. Обёртка не нужна.

**`handleDelete` использует функциональную форму** `setRuns(rs => ...)`. Это правило из урока 15: обновление зависит от предыдущего значения.

**Всё состояние в одном месте.** Читая `App`, видно полную картину: что хранится, кто меняет, при каких условиях. Дети — чистые функции отображения.

**Проверь, что поток действительно однонаправленный.** Поставь `console.log` в `App` и в `ConfigEditor`. Подвигай ползунок: событие идёт вверх (`onChange` → `setConfig`), состояние меняется, `App` перерисовывается, новое значение идёт вниз в props. Полный круг на каждое движение — и это нормально, React с этим справляется.

---

# Часть 3. Домашка

**1.** Два поля: частота в Гц и период в мс. Изменение любого пересчитывает другое. Реализуй через подъём состояния — какое значение хранить, чтобы не было рассинхрона и дрейфа при округлении?

**2.** Сделай `ConfigEditor` неуправляемым (со своим состоянием) и объясни, что сломается в `App`. Затем верни как было.

**3.** Найди все значения, которые не должны быть состоянием, и объясни по каждому:
```tsx
function Panel({ runs }: { runs: Run[] }) {
  const [count, setCount] = useState(runs.length);
  const [hasRuns, setHasRuns] = useState(runs.length > 0);
  const [sorted, setSorted] = useState<Run[]>([]);
  const [timerId, setTimerId] = useState<number | null>(null);
  const [labels] = useState(['a', 'b', 'c']);
}
```

**4.** Prop drilling. Дана цепочка `App → Layout → Sidebar → Filters`, и `Filters` нужен `config`. Реши задачу композицией, не используя Context. Покажи оба варианта кода.

**5.** Компонент с поддержкой обоих режимов из 17.3 — реализуй полностью, с типами. Сделай так, чтобы TypeScript **не позволял** передать одновременно `value` и `defaultValue`. Подсказка: union props из урока 08.

**6.** Реализуй мастер из трёх шагов: выбор источника, настройка FFT, подтверждение. Состояние шага и накопленные данные — где разместить? Кнопка «назад» должна сохранять уже введённое.

**7.** Объясни, почему это не работает, и почини не поднимая состояние:
```tsx
function Parent() {
  let value = 0;
  return <><Child onChange={v => { value = v; }} /><span>{value}</span></>;
}
```
